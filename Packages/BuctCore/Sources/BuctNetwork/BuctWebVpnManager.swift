import Foundation

public struct BuctWebVpnAuthRequiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct BuctWebVpnStatus: Sendable, Equatable {
    public let hasTicket: Bool
    public let preferVpnHosts: [String]
    public let lastFailureReason: String
}

/// 北化 WebVPN（w.buct.edu.cn，Wengine 网关）按需认证与直连优先降级管理器。
public actor BuctWebVpnManager {
    public static let shared = BuctWebVpnManager()

    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let sidPortalBase = "https://sidportal.buct.edu.cn"
    private static let sidPortalUA =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/139.0.0.0 Mobile Safari/537.36"
    private static let preferVpnTTL: TimeInterval = 300
    private static let ticketSoftTTL: TimeInterval = 1_800
    private static let reloginCooldown: TimeInterval = 30
    private static let directTimeout: TimeInterval = 3.0

    private let transport: BuctHttpTransport

    private var readSidCookiesFn: (@Sendable () async -> String)?
    private var saveSidCookiesFn: (@Sendable (String) async -> Void)?
    private var readSavedCredentialsFn: (@Sendable () async -> (username: String, password: String)?)?
    private var readVpnTicketFn: (@Sendable () async -> String)?
    private var saveVpnTicketFn: (@Sendable (String) async -> Void)?

    private var cachedTicket: String = ""
    private var ticketFetchedAt: Date?
    private var preferVpnUntilByHost: [String: Date] = [:]
    private var lastReloginFailureAt: Date?
    private var lastReloginFailureReason: String = ""
    public private(set) var lastFailureReason: String = ""

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func configure(
        readSidCookies: @escaping @Sendable () async -> String,
        saveSidCookies: @escaping @Sendable (String) async -> Void,
        readSavedCredentials: @escaping @Sendable () async -> (username: String, password: String)?,
        readVpnTicket: @escaping @Sendable () async -> String,
        saveVpnTicket: @escaping @Sendable (String) async -> Void
    ) {
        self.readSidCookiesFn = readSidCookies
        self.saveSidCookiesFn = saveSidCookies
        self.readSavedCredentialsFn = readSavedCredentials
        self.readVpnTicketFn = readVpnTicket
        self.saveVpnTicketFn = saveVpnTicket
    }

    public func statusSnapshot() async -> BuctWebVpnStatus {
        let now = Date()
        let activeHosts = preferVpnUntilByHost
            .filter { $0.value > now }
            .map(\.key)
            .sorted()
        let persisted = await readVpnTicketFn?() ?? ""
        return BuctWebVpnStatus(
            hasTicket: !cachedTicket.isEmpty || !persisted.isEmpty,
            preferVpnHosts: activeHosts,
            lastFailureReason: lastFailureReason
        )
    }

    public func clearSession() {
        cachedTicket = ""
        ticketFetchedAt = nil
        preferVpnUntilByHost.removeAll()
        lastReloginFailureAt = nil
        lastReloginFailureReason = ""
        lastFailureReason = ""
    }

    public func clearPreferVpn(host: String? = nil) {
        if let host {
            preferVpnUntilByHost.removeValue(forKey: host.lowercased())
        } else {
            preferVpnUntilByHost.removeAll()
        }
    }

    public func activateWithCasTicket(_ casTicket: String) async -> String? {
        let cleanCas = casTicket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCas.isEmpty else { return nil }
        lastFailureReason = ""
        guard let initTicket = try? await fetchInitialVpnTicket(),
              let activeTicket = try? await activateVpnTicket(initialVpnTicket: initTicket, casTicket: cleanCas) else {
            return nil
        }
        cachedTicket = activeTicket
        ticketFetchedAt = Date()
        lastReloginFailureAt = nil
        lastReloginFailureReason = ""
        lastFailureReason = ""
        await saveVpnTicketFn?(activeTicket)
        return activeTicket
    }

    /// 统一请求入口：
    /// - 非校内专属域直接直连
    /// - 7 个校内专属域先 3s 直连探测；失败或校内拦截则自动切 w.buct.edu.cn WebVPN
    public func execute(
        _ request: URLRequest,
        cookieJar: MatchingMemoryCookieJar? = nil,
        timeout: TimeInterval = 20
    ) async throws -> HttpResponseData {
        guard let url = request.url, let host = url.host?.lowercased(),
              BuctWebVpnCodec.isCampusOnlyHost(host) else {
            return try await transport.send(request, cookieJar: cookieJar, timeout: timeout)
        }

        var directAttempted = false
        var directError: Error?

        if !shouldPreferVpn(host: host) {
            directAttempted = true
            do {
                let resp = try await transport.send(request, cookieJar: cookieJar, timeout: Self.directTimeout)
                if Self.isDirectCampusBlock(resp) {
                    markDirectFailed(host: host)
                } else {
                    markDirectSucceeded(host: host)
                    return resp
                }
            } catch {
                if Self.isDirectNetworkFailure(error) {
                    directError = error
                    markDirectFailed(host: host)
                } else {
                    throw error
                }
            }
        }

        guard let ticket = await ensureTicket(forceRefresh: false), !ticket.isEmpty else {
            if !directAttempted {
                clearPreferVpn(host: host)
                do {
                    let resp = try await transport.send(request, cookieJar: cookieJar, timeout: Self.directTimeout)
                    if Self.isDirectCampusBlock(resp) {
                        markDirectFailed(host: host)
                        throw BuctWebVpnAuthRequiredError(friendlyVpnAuthMessage())
                    }
                    markDirectSucceeded(host: host)
                    return resp
                } catch {
                    if Self.isDirectNetworkFailure(error) {
                        markDirectFailed(host: host)
                        throw BuctWebVpnAuthRequiredError(friendlyVpnAuthMessage())
                    }
                    throw error
                }
            }
            if let directError {
                throw BuctWebVpnAuthRequiredError("\(friendlyVpnAuthMessage())（直连异常：\(directError.localizedDescription)）")
            }
            throw BuctWebVpnAuthRequiredError(friendlyVpnAuthMessage())
        }

        let vpnRequest = try buildVpnRequest(from: request)
        let vpnResp: HttpResponseData
        do {
            vpnResp = try await transport.send(
                vpnRequest,
                cookieJar: cookieJar,
                overrideTicketCookie: ticket,
                timeout: timeout
            )
        } catch {
            if !directAttempted && Self.isDirectNetworkFailure(error) {
                clearPreferVpn(host: host)
                return try await transport.send(request, cookieJar: cookieJar, timeout: Self.directTimeout)
            }
            throw error
        }

        if Self.isVpnLoginRedirect(vpnResp) {
            guard let refreshed = await ensureTicket(forceRefresh: true), !refreshed.isEmpty else {
                throw BuctWebVpnAuthRequiredError(friendlyVpnAuthMessage())
            }
            let retryReq = try buildVpnRequest(from: request)
            let retryResp = try await transport.send(
                retryReq,
                cookieJar: cookieJar,
                overrideTicketCookie: refreshed,
                timeout: timeout
            )
            if Self.isVpnLoginRedirect(retryResp) {
                throw BuctWebVpnAuthRequiredError(friendlyVpnAuthMessage())
            }
            await updateTicketFromResponse(retryResp)
            return normalizeVpnResponse(retryResp, originalURL: url)
        }

        await updateTicketFromResponse(vpnResp)
        return normalizeVpnResponse(vpnResp, originalURL: url)
    }

    public func ensureTicket(forceRefresh: Bool) async -> String? {
        let now = Date()
        if !forceRefresh, !cachedTicket.isEmpty,
           let fetchedAt = ticketFetchedAt, now.timeIntervalSince(fetchedAt) < Self.ticketSoftTTL {
            return cachedTicket
        }
        if !forceRefresh, cachedTicket.isEmpty {
            let persisted = (await readVpnTicketFn?() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !persisted.isEmpty {
                cachedTicket = persisted
                ticketFetchedAt = now
                return persisted
            }
        }
        if forceRefresh {
            cachedTicket = ""
            ticketFetchedAt = nil
        }
        lastFailureReason = ""

        do {
            guard let initTicket = try await fetchInitialVpnTicket(),
                  let casTicket = await fetchCasTicketForVpn(),
                  let activeTicket = try await activateVpnTicket(initialVpnTicket: initTicket, casTicket: casTicket) else {
                return nil
            }
            cachedTicket = activeTicket
            ticketFetchedAt = Date()
            lastFailureReason = ""
            await saveVpnTicketFn?(activeTicket)
            return activeTicket
        } catch {
            if lastFailureReason.isEmpty {
                lastFailureReason = "net-error"
            }
            return nil
        }
    }

    private func shouldPreferVpn(host: String) -> Bool {
        guard let until = preferVpnUntilByHost[host] else { return false }
        return Date() < until
    }

    private func markDirectFailed(host: String) {
        preferVpnUntilByHost[host] = Date().addingTimeInterval(Self.preferVpnTTL)
    }

    private func markDirectSucceeded(host: String) {
        preferVpnUntilByHost.removeValue(forKey: host)
    }

    private func updateTicketFromResponse(_ response: HttpResponseData) async {
        let rotated = BuctHttpTransport.extractCookieValue(
            from: response.headers,
            name: BuctWebVpnCodec.vpnCookieName
        )
        if !rotated.isEmpty {
            cachedTicket = rotated
            ticketFetchedAt = Date()
            await saveVpnTicketFn?(rotated)
        }
    }

    private func buildVpnRequest(from original: URLRequest) throws -> URLRequest {
        var req = original
        if let url = original.url {
            req.url = try BuctWebVpnCodec.toVpnURL(url)
        }
        if req.value(forHTTPHeaderField: "Origin") != nil {
            req.setValue(BuctWebVpnCodec.vpnBase, forHTTPHeaderField: "Origin")
        }
        if let referer = req.value(forHTTPHeaderField: "Referer"),
           let refURL = URL(string: referer),
           let refHost = refURL.host?.lowercased(),
           refHost == "buct.edu.cn" || refHost.hasSuffix(".buct.edu.cn") {
            if let vpnRef = try? BuctWebVpnCodec.toVpnURL(refURL) {
                req.setValue(vpnRef.absoluteString, forHTTPHeaderField: "Referer")
            }
        }
        return req
    }

    private func normalizeVpnResponse(_ response: HttpResponseData, originalURL: URL) -> HttpResponseData {
        var headers = response.headers
        if response.isRedirect, let loc = response.header("Location"), !loc.isEmpty {
            if let resolved = URL(string: loc, relativeTo: response.url)?.absoluteURL,
               let unwrapped = BuctWebVpnCodec.fromVpnURL(resolved) {
                for key in Array(headers.keys) where key.caseInsensitiveCompare("Location") == .orderedSame {
                    headers[key] = unwrapped.absoluteString
                }
            }
        }
        headers["X-Buct-Via-WebVpn"] = "1"
        return HttpResponseData(
            url: originalURL,
            statusCode: response.statusCode,
            headers: headers,
            setCookieHeaders: response.setCookieHeaders,
            body: response.body,
            viaWebVpn: true
        )
    }

    private func fetchInitialVpnTicket() async throws -> String? {
        var req = URLRequest(url: URL(string: "\(BuctWebVpnCodec.vpnBase)/login")!)
        req.httpMethod = "GET"
        req.setValue(Self.sidPortalUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let resp = try await transport.send(req, timeout: 12)
        let ticket = BuctHttpTransport.extractCookieValue(from: resp.headers, name: BuctWebVpnCodec.vpnCookieName)
        if ticket.isEmpty {
            lastFailureReason = "init-http-\(resp.statusCode)-no-cookie"
            return nil
        }
        return ticket
    }

    private func fetchCasTicketForVpn() async -> String? {
        let casService = "\(BuctWebVpnCodec.vpnBase)/login?cas_login=true"
        let encodedService = casService.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? casService
        let casLoginURL = URL(string: "\(Self.sidPortalBase)/login?service=\(encodedService)")!

        let jar = MatchingMemoryCookieJar()
        let rawSidCookies = (await readSidCookiesFn?() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawSidCookies.isEmpty {
            jar.seed(cookieHeader: rawSidCookies, setByHost: Self.sidPortalHost)
        }

        var entryHTML = ""
        var probeReason = ""
        if !rawSidCookies.isEmpty {
            let probe = await followCasToVpnTicket(jar: jar, startURL: casLoginURL)
            if let ticket = probe.ticket {
                let refreshed = exportSidCookieHeader(jar: jar)
                if !refreshed.isEmpty && refreshed != rawSidCookies {
                    await saveSidCookiesIfAuthenticated(refreshed)
                }
                return ticket
            }
            entryHTML = probe.html
            probeReason = probe.reason
        }

        if let lastFail = lastReloginFailureAt, Date().timeIntervalSince(lastFail) < Self.reloginCooldown {
            lastFailureReason = probeReason.isEmpty ? "cooldown(\(lastReloginFailureReason))" : "\(probeReason),cooldown"
            return nil
        }

        guard let creds = await readSavedCredentialsFn?(),
              !creds.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !creds.password.isEmpty else {
            lastFailureReason = rawSidCookies.isEmpty ? "sid-empty,no-creds" : "cas-probe-fail,no-creds"
            return nil
        }

        let username = creds.username.trimmingCharacters(in: .whitespacesAndNewlines)
        var passwordData = Data(creds.password.utf8)
        defer { BuctCrypto.wipe(&passwordData) }

        if entryHTML.isEmpty {
            let probe = await followCasToVpnTicket(jar: jar, startURL: casLoginURL)
            if let ticket = probe.ticket {
                await saveSidCookiesIfAuthenticated(exportSidCookieHeader(jar: jar))
                lastReloginFailureAt = nil
                lastReloginFailureReason = ""
                return ticket
            }
            entryHTML = probe.html
            probeReason = probe.reason
        }

        if entryHTML.isEmpty {
            recordReloginFailure(probeReason.isEmpty ? "cas-entry-empty" : probeReason)
            return nil
        }

        var execution = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-page-flowkey") ?? ""
        var croypto = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-croypto") ?? ""
        var errorCode = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-error-msg")
            ?? BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-error-code")
            ?? ""
        var second = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "sso-second") ?? ""

        if !rawSidCookies.isEmpty && errorCode.isEmpty && (execution.isEmpty || croypto.isEmpty) {
            jar.clear()
            let cleanProbe = await followCasToVpnTicket(jar: jar, startURL: casLoginURL)
            if let ticket = cleanProbe.ticket {
                await saveSidCookiesIfAuthenticated(exportSidCookieHeader(jar: jar))
                lastReloginFailureAt = nil
                lastReloginFailureReason = ""
                return ticket
            }
            if !cleanProbe.html.isEmpty {
                entryHTML = cleanProbe.html
                execution = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-page-flowkey") ?? ""
                croypto = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-croypto") ?? ""
                errorCode = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-error-msg")
                    ?? BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "login-error-code")
                    ?? ""
                second = BuctSsoAuthClient.extractHtmlParagraphField(entryHTML, id: "sso-second") ?? ""
            }
        }

        if !errorCode.isEmpty {
            recordReloginFailure("relogin-err(\(errorCode))")
            return nil
        }
        if !second.isEmpty {
            recordReloginFailure("relogin-2fa")
            return nil
        }
        if execution.isEmpty || croypto.isEmpty {
            recordReloginFailure("relogin-no-params")
            return nil
        }

        guard let keyData = Data(base64Encoded: croypto),
              let encPwd = try? BuctCrypto.aesECBEncrypt(plaintext: passwordData, key: keyData).base64EncodedString(),
              let encCap = try? BuctCrypto.aesECBEncrypt(plaintext: Data("{}".utf8), key: keyData).base64EncodedString() else {
            recordReloginFailure("relogin-crypto-err")
            return nil
        }

        var postReq = URLRequest(url: casLoginURL)
        postReq.httpMethod = "POST"
        postReq.setValue(Self.sidPortalUA, forHTTPHeaderField: "User-Agent")
        postReq.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        postReq.setValue(Self.sidPortalBase, forHTTPHeaderField: "Origin")
        postReq.setValue(casLoginURL.absoluteString, forHTTPHeaderField: "Referer")
        postReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        postReq.httpBody = Self.formEncode([
            ("type", "UsernamePassword"),
            ("_eventId", "submit"),
            ("username", username),
            ("password", encPwd),
            ("croypto", croypto),
            ("execution", execution),
            ("captcha_code", ""),
            ("captcha_payload", encCap),
            ("geolocation", "")
        ])

        do {
            let resp = try await transport.send(postReq, cookieJar: jar, timeout: 15)
            guard resp.isRedirect, let loc = resp.header("Location"),
                  let resolved = URL(string: loc, relativeTo: casLoginURL)?.absoluteURL else {
                recordReloginFailure("relogin-post-http\(resp.statusCode)")
                return nil
            }
            if let directTicket = Self.extractTicketIfVpnCallback(resolved) {
                lastReloginFailureAt = nil
                lastReloginFailureReason = ""
                await saveSidCookiesIfAuthenticated(exportSidCookieHeader(jar: jar))
                return directTicket
            }
            let follow = await followCasToVpnTicket(jar: jar, startURL: resolved)
            guard let ticket = follow.ticket else {
                recordReloginFailure(follow.reason.isEmpty ? "relogin-no-ticket" : follow.reason)
                return nil
            }
            lastReloginFailureAt = nil
            lastReloginFailureReason = ""
            await saveSidCookiesIfAuthenticated(exportSidCookieHeader(jar: jar))
            return ticket
        } catch {
            recordReloginFailure("relogin-exc")
            return nil
        }
    }

    private func followCasToVpnTicket(
        jar: MatchingMemoryCookieJar,
        startURL: URL
    ) async -> (ticket: String?, html: String, reason: String) {
        if let t = Self.extractTicketIfVpnCallback(startURL) {
            return (t, "", "")
        }
        var current = startURL
        for _ in 0..<6 {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.sidPortalUA, forHTTPHeaderField: "User-Agent")
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            guard let resp = try? await transport.send(req, cookieJar: jar, timeout: 12) else {
                return (nil, "", "cas-net-err")
            }
            if resp.isRedirect {
                guard let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    return (nil, "", "cas-3xx-bad-loc")
                }
                if let t = Self.extractTicketIfVpnCallback(next) {
                    return (t, "", "")
                }
                let host = next.host?.lowercased() ?? ""
                guard host == Self.sidPortalHost || host == "portal.buct.edu.cn" else {
                    return (nil, "", "cas-redir-\(host)")
                }
                current = next
            } else if resp.isSuccessful {
                return (nil, resp.bodyString, "cas-http\(resp.statusCode)")
            } else {
                return (nil, "", "cas-http\(resp.statusCode)")
            }
        }
        return (nil, "", "cas-max-hops")
    }

    private func activateVpnTicket(initialVpnTicket: String, casTicket: String) async throws -> String? {
        let encoded = casTicket.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? casTicket
        let url = URL(string: "\(BuctWebVpnCodec.vpnBase)/login?cas_login=true&ticket=\(encoded)")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.sidPortalUA, forHTTPHeaderField: "User-Agent")

        var ticket = initialVpnTicket
        let resp = try await transport.send(req, overrideTicketCookie: ticket, timeout: 12)
        let rotated = BuctHttpTransport.extractCookieValue(from: resp.headers, name: BuctWebVpnCodec.vpnCookieName)
        if !rotated.isEmpty {
            ticket = rotated
        }
        if resp.isRedirect {
            if Self.isVpnLoginRedirect(resp) {
                lastFailureReason = "activate-302-login"
                return nil
            }
            return ticket
        }
        guard resp.isSuccessful else {
            lastFailureReason = "activate-http-\(resp.statusCode)"
            return nil
        }
        if resp.bodyString.contains("login-page-flowkey") {
            lastFailureReason = "activate-200-login"
            return nil
        }
        return ticket
    }

    private func exportSidCookieHeader(jar: MatchingMemoryCookieJar) -> String {
        let probeURL = URL(string: "\(Self.sidPortalBase)/login")!
        var merged: [String: String] = [:]
        var order: [String] = []
        for cookie in jar.loadForRequest(url: probeURL) where !cookie.value.isEmpty {
            if merged[cookie.name] == nil { order.append(cookie.name) }
            merged[cookie.name] = cookie.value
        }
        for cookie in jar.cookiesSetBy(host: Self.sidPortalHost, port: 443) where !cookie.value.isEmpty {
            if merged[cookie.name] == nil {
                order.append(cookie.name)
                merged[cookie.name] = cookie.value
            }
        }
        return order.compactMap { k in merged[k].map { "\(k)=\($0)" } }.joined(separator: "; ")
    }

    private func saveSidCookiesIfAuthenticated(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed.localizedCaseInsensitiveContains("SOURCEID_TGC=") {
            await saveSidCookiesFn?(trimmed)
        }
    }

    private func recordReloginFailure(_ reason: String) {
        lastReloginFailureAt = Date()
        lastReloginFailureReason = reason
        lastFailureReason = reason
    }

    private func friendlyVpnAuthMessage() -> String {
        if lastFailureReason.contains("relogin-2fa") {
            return "校外访问需通过 WebVPN 短信二次验证，请前往「我的」重新登录统一身份认证"
        }
        return "校外访问校内系统需要 WebVPN 票据，请先登录统一身份认证"
    }

    private static func extractTicketIfVpnCallback(_ url: URL) -> String? {
        guard url.host?.caseInsensitiveCompare(BuctWebVpnCodec.vpnHost) == .orderedSame,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let ticket = comps.queryItems?.first(where: { $0.name == "ticket" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ticket.isEmpty else {
            return nil
        }
        return ticket
    }

    public static func isDirectNetworkFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            let networkCodes: Set<Int> = [
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorNotConnectedToInternet
            ]
            return networkCodes.contains(ns.code)
        }
        return false
    }

    public static func isDirectCampusBlock(_ response: HttpResponseData) -> Bool {
        let code = response.statusCode
        let contentType = (response.header("Content-Type") ?? "").lowercased()
        if [403, 451, 502, 503].contains(code) {
            if contentType.contains("json") && response.bodyString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return false
            }
            return true
        }
        if code == 200 && contentType.contains("html") {
            let lower = String(response.bodyString.prefix(8192)).lowercased()
            let businessMarkers = [
                "一卡通查询平台", "raspublickey", "研究生管理信息系统", "graduate management", "login-page-flowkey"
            ]
            if businessMarkers.contains(where: { lower.contains($0) }) { return false }
            let blockMarkers = [
                "请使用vpn", "请使用 vpn", "请连接vpn", "请连接校园网", "仅限校内", "w.buct.edu.cn"
            ]
            return blockMarkers.contains(where: { lower.contains($0) })
        }
        return false
    }

    public static func isVpnLoginRedirect(_ response: HttpResponseData) -> Bool {
        guard response.isRedirect, let loc = response.header("Location"), !loc.isEmpty,
              let resolved = URL(string: loc, relativeTo: response.url)?.absoluteURL else {
            return false
        }
        if resolved.host?.caseInsensitiveCompare(BuctWebVpnCodec.vpnHost) == .orderedSame,
           resolved.path.hasPrefix("/login") {
            return true
        }
        let unwrapped = BuctWebVpnCodec.fromVpnURL(resolved) ?? resolved
        if unwrapped.host?.caseInsensitiveCompare(sidPortalHost) == .orderedSame,
           unwrapped.path.hasPrefix("/login") {
            let comps = URLComponents(url: unwrapped, resolvingAgainstBaseURL: false)
            let service = comps?.queryItems?.first(where: { $0.name == "service" })?.value ?? ""
            return service.isEmpty || service.localizedCaseInsensitiveContains(BuctWebVpnCodec.vpnHost)
        }
        return false
    }

    private static func formEncode(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let body = pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
