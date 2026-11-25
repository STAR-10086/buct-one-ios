import Foundation

public enum BuctSsoAuthOutcome: Sendable {
    case success(jwglxtCookie: String, sidCookie: String, vpnTicket: String?)
    case captchaRequired(imageData: Data, message: String)
    case secondarySmsRequired(maskedPhone: String)
    case invalidCredentials
    case failure(message: String)
}

public enum BuctSsoMode: Sendable {
    case teaching
    case sidPortalOnly
    case webVpn
}

/// 北化统一身份认证（sidportal.buct.edu.cn，金智 linkid）原生登录客户端。
public actor BuctSsoAuthClient {
    public static let authPortalBase = "https://sidportal.buct.edu.cn"
    public static let teachingServiceURL = "https://jwglxt.buct.edu.cn/sso/jziotlogin"
    private static let deviceIDFixed = "a1b2c3d4e5f60718293a4b5c6d7e8f90"
    private static let mobileUA =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/139.0.0.0 Mobile Safari/537.36"
    private static let browserUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Safari/537.36"

    private struct AttemptState {
        let username: String
        var passwordData: Data
        let serviceURL: URL
        let mode: BuctSsoMode
        let cookieJar: MatchingMemoryCookieJar
        var execution: String = ""
        var aesKey: String = ""
        let csrfKey: String
        let csrfValue: String
        var secondarySmsRequired: Bool = false

        mutating func erase() {
            BuctCrypto.wipe(&passwordData)
            execution = ""
            aesKey = ""
            cookieJar.clear()
        }
    }

    private let transport: BuctHttpTransport
    private let webVpn: BuctWebVpnManager
    private var activeAttempt: AttemptState?

    public init(transport: BuctHttpTransport = .shared, webVpn: BuctWebVpnManager = .shared) {
        self.transport = transport
        self.webVpn = webVpn
    }

    public func clearSensitiveState() {
        activeAttempt?.erase()
        activeAttempt = nil
    }

    public func login(username: String, password: String, mode: BuctSsoMode = .teaching) async -> BuctSsoAuthOutcome {
        clearSensitiveState()
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty, !password.isEmpty else {
            return .invalidCredentials
        }

        let serviceStr: String
        switch mode {
        case .teaching, .sidPortalOnly:
            serviceStr = Self.teachingServiceURL
        case .webVpn:
            serviceStr = "\(BuctWebVpnCodec.vpnBase)/login?cas_login=true"
        }

        let (csrfKey, csrfValue) = Self.generateCsrfPair()
        var attempt = AttemptState(
            username: cleanUser,
            passwordData: Data(password.utf8),
            serviceURL: URL(string: serviceStr)!,
            mode: mode,
            cookieJar: MatchingMemoryCookieJar(),
            csrfKey: csrfKey,
            csrfValue: csrfValue
        )

        let entryURL = loginURL(serviceURL: attempt.serviceURL)
        guard let entryResp = await followPortalRedirects(url: entryURL, attempt: attempt) else {
            attempt.erase()
            return .failure(message: "无法连接统一身份认证服务")
        }
        guard entryResp.isSuccessful else {
            attempt.erase()
            return .failure(message: "统一认证服务返回错误 (\(entryResp.statusCode))")
        }

        let html = entryResp.bodyString
        guard let execution = Self.extractHtmlParagraphField(html, id: "login-page-flowkey"),
              let aesKey = Self.extractHtmlParagraphField(html, id: "login-croypto") else {
            attempt.erase()
            return .failure(message: "无法获取统一认证登录参数")
        }
        attempt.execution = execution
        attempt.aesKey = aesKey
        activeAttempt = attempt
        return await submitCredentials(captchaCode: "")
    }

    public func submitCaptcha(_ captchaCode: String) async -> BuctSsoAuthOutcome {
        guard activeAttempt != nil else {
            return .failure(message: "登录会话已失效，请重新登录")
        }
        let code = captchaCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            return .failure(message: "请输入验证码")
        }
        return await submitCredentials(captchaCode: code)
    }

    public func refreshCaptcha() async -> Data? {
        guard let attempt = activeAttempt else { return nil }
        return await fetchCaptchaImage(jar: attempt.cookieJar)
    }

    public func prepareSecondarySmsCaptcha() async -> Result<Data, Error> {
        guard let attempt = activeAttempt, attempt.secondarySmsRequired else {
            return .failure(NSError(domain: "BuctSso", code: -1, userInfo: [NSLocalizedDescriptionKey: "二次验证会话已失效，请重新登录"]))
        }
        let url = URL(string: "\(Self.authPortalBase)/sso-extend/protected/api/aggregate/sms/publicNoToken/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applySecondaryApiHeaders(&req, attempt: attempt)
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["phone": attempt.username, "type": "DEFAULT"])

        do {
            let resp = try await transport.send(req, cookieJar: attempt.cookieJar, timeout: 15)
            if resp.isSuccessful && resp.body.count > 16 {
                return .success(resp.body)
            }
            return .failure(NSError(domain: "BuctSso", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取图形验证码失败，请稍后重试"]))
        } catch {
            return .failure(NSError(domain: "BuctSso", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取图形验证码失败，请检查网络"]))
        }
    }

    public func sendSecondarySmsCode(captchaCode: String) async -> Result<Int, Error> {
        guard let attempt = activeAttempt, attempt.secondarySmsRequired else {
            return .failure(NSError(domain: "BuctSso", code: -1, userInfo: [NSLocalizedDescriptionKey: "二次验证会话已失效，请重新登录"]))
        }
        let clean = captchaCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .failure(NSError(domain: "BuctSso", code: -2, userInfo: [NSLocalizedDescriptionKey: "请输入图形验证码"]))
        }
        let encodedCode = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clean
        let encodedUser = attempt.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? attempt.username
        let url = URL(string: "\(Self.authPortalBase)/sso-extend/protected/api/aggregate/sms/publicNoToken/sendCheckCaptcha/DEFAULT/\(encodedCode)/\(encodedUser)/0008")!

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applySecondaryApiHeaders(&req, attempt: attempt)

        do {
            let resp = try await transport.send(req, cookieJar: attempt.cookieJar, timeout: 15)
            let text = resp.bodyString
            let obj = (try? JSONSerialization.jsonObject(with: resp.body)) as? [String: Any]
            let code = obj?["code"] as? Int ?? -1
            let resultFlag = obj?["result"] as? Bool ?? false
            if resp.isSuccessful && (resultFlag || code == 200) {
                return .success(120)
            }
            if code == 2180000 || code == 1320009 || text.contains("2180000") || text.contains("1320009") {
                return .failure(NSError(domain: "BuctSso", code: 1320009, userInfo: [NSLocalizedDescriptionKey: "图形验证码错误，请重试"]))
            }
            if code == 13001016 || text.contains("13001016") {
                return .failure(NSError(domain: "BuctSso", code: 13001016, userInfo: [NSLocalizedDescriptionKey: "验证码还在有效期内，请勿重复发送"]))
            }
            if code == 13002022 || text.contains("BUSINESS_LIMIT") {
                return .failure(NSError(domain: "BuctSso", code: 13002022, userInfo: [NSLocalizedDescriptionKey: "短信发送过于频繁，请稍后再试"]))
            }
            let msg = Self.extractSecondaryError(obj: obj, fallback: "发送短信失败，请稍后重试")
            return .failure(NSError(domain: "BuctSso", code: code, userInfo: [NSLocalizedDescriptionKey: msg]))
        } catch {
            return .failure(NSError(domain: "BuctSso", code: -1, userInfo: [NSLocalizedDescriptionKey: "发送短信失败，请检查网络"]))
        }
    }

    public func submitSecondarySmsCode(smsCode: String, rememberDevice: Bool) async -> BuctSsoAuthOutcome {
        guard let attempt = activeAttempt, attempt.secondarySmsRequired else {
            return .failure(message: "二次验证会话已失效，请重新登录")
        }
        let cleanSms = smsCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanSms.count >= 4 else {
            return .failure(message: "请输入短信验证码")
        }

        let verifyURL = URL(string: "\(Self.authPortalBase)/linkid/protected/api/aggregate/sms/verify")!
        var verifyReq = URLRequest(url: verifyURL)
        verifyReq.httpMethod = "POST"
        applySecondaryApiHeaders(&verifyReq, attempt: attempt)
        verifyReq.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        verifyReq.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        verifyReq.httpBody = try? JSONSerialization.data(withJSONObject: [
            "phone": attempt.username,
            "token": cleanSms,
            "delete": false,
            "trustDevice": rememberDevice
        ])

        do {
            let resp = try await transport.send(verifyReq, cookieJar: attempt.cookieJar, timeout: 15)
            let obj = (try? JSONSerialization.jsonObject(with: resp.body)) as? [String: Any]
            let code = obj?["code"] as? Int ?? -1
            guard resp.isSuccessful && code == 200 else {
                let msg = Self.extractSecondaryError(obj: obj, fallback: "短信验证码错误或已过期")
                return .failure(message: msg)
            }
        } catch {
            return .failure(message: "短信验证失败，请检查网络")
        }

        let postURL = loginURL(serviceURL: attempt.serviceURL)
        var loginReq = URLRequest(url: postURL)
        loginReq.httpMethod = "POST"
        loginReq.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        loginReq.setValue(postURL.absoluteString, forHTTPHeaderField: "Referer")
        loginReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        loginReq.httpBody = Self.formEncode([
            ("username", attempt.username),
            ("password", cleanSms),
            ("type", "smsLogin"),
            ("_eventId", "submit"),
            ("geolocation", ""),
            ("execution", attempt.execution),
            ("captcha_code", ""),
            ("trustDevice", rememberDevice ? "true" : "false")
        ])

        do {
            let resp = try await transport.send(loginReq, cookieJar: attempt.cookieJar, timeout: 20)
            if resp.isRedirect {
                return await handleAuthRedirect(baseURL: postURL, location: resp.header("Location"))
            }
            guard resp.isSuccessful else {
                return .failure(message: "二次验证登录失败 (\(resp.statusCode))")
            }
            let html = resp.bodyString
            if Self.isSecondarySmsPage(html) {
                activeAttempt?.execution = Self.extractHtmlParagraphField(html, id: "login-page-flowkey")
                    ?? Self.extractInputValue(html, name: "execution")
                    ?? attempt.execution
                return .failure(message: "短信验证码错误或已过期，请重新获取")
            }
            return await handleLoginPageFailure(html: html)
        } catch {
            return .failure(message: "二次验证登录连接失败")
        }
    }

    // MARK: - Internal stages

    private func submitCredentials(captchaCode: String) async -> BuctSsoAuthOutcome {
        guard let attempt = activeAttempt else {
            return .failure(message: "登录会话已失效，请重新登录")
        }
        guard let keyData = Data(base64Encoded: attempt.aesKey),
              let encPwd = try? BuctCrypto.aesECBEncrypt(plaintext: attempt.passwordData, key: keyData).base64EncodedString(),
              let encCap = try? BuctCrypto.aesECBEncrypt(plaintext: Data("{}".utf8), key: keyData).base64EncodedString() else {
            clearSensitiveState()
            return .failure(message: "统一认证密码加密失败")
        }

        let postURL = loginURL(serviceURL: attempt.serviceURL)
        var req = URLRequest(url: postURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if attempt.mode == .sidPortalOnly {
            applyPortalBrowserHeaders(&req, referer: postURL.absoluteString)
            req.setValue("\(Self.authPortalBase)/", forHTTPHeaderField: "Origin")
        } else {
            req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
            req.setValue(postURL.absoluteString, forHTTPHeaderField: "Referer")
        }
        req.httpBody = Self.formEncode([
            ("type", "UsernamePassword"),
            ("_eventId", "submit"),
            ("username", attempt.username),
            ("password", encPwd),
            ("croypto", attempt.aesKey),
            ("execution", attempt.execution),
            ("captcha_code", captchaCode),
            ("captcha_payload", encCap),
            ("geolocation", "")
        ])

        do {
            let resp = try await transport.send(req, cookieJar: attempt.cookieJar, timeout: 25)
            if resp.isRedirect {
                if attempt.mode == .sidPortalOnly {
                    let sidCookie = exportSidCookie(from: attempt.cookieJar)
                    clearSensitiveState()
                    return .success(jwglxtCookie: "", sidCookie: sidCookie, vpnTicket: nil)
                }
                return await handleAuthRedirect(baseURL: postURL, location: resp.header("Location"))
            }
            guard resp.isSuccessful else {
                clearSensitiveState()
                return .failure(message: "统一认证返回错误 (\(resp.statusCode))")
            }
            return await handleLoginPageFailure(html: resp.bodyString)
        } catch {
            clearSensitiveState()
            return .failure(message: "统一认证提交连接失败")
        }
    }

    private func handleLoginPageFailure(html: String) async -> BuctSsoAuthOutcome {
        guard var attempt = activeAttempt else {
            return .failure(message: "登录会话已失效")
        }
        if Self.isSecondarySmsPage(html) {
            attempt.execution = Self.extractHtmlParagraphField(html, id: "login-page-flowkey")
                ?? Self.extractInputValue(html, name: "execution")
                ?? attempt.execution
            attempt.secondarySmsRequired = true
            activeAttempt = attempt
            let phoneMask = Self.extractSecondaryPhone(html)
            return .secondarySmsRequired(maskedPhone: phoneMask)
        }

        let errorCode = Self.extractHtmlParagraphField(html, id: "login-error-code") ?? ""
        let captchaURL = Self.extractHtmlParagraphField(html, id: "captcha-url") ?? ""
        switch errorCode {
        case "1030027", "1030031":
            clearSensitiveState()
            return .invalidCredentials
        case "1030028":
            clearSensitiveState()
            return .failure(message: "账号已被锁定，请联系学校处理")
        case "1320007":
            if let img = await fetchCaptchaImage(jar: attempt.cookieJar) {
                return .captchaRequired(imageData: img, message: "验证码错误，请重新输入")
            }
            clearSensitiveState()
            return .failure(message: "无法获取验证码，请稍后重试")
        default:
            let vendor = Self.extractHtmlParagraphField(html, id: "recaptchaVendor") ?? ""
            if !captchaURL.isEmpty || vendor == "system" {
                if let img = await fetchCaptchaImage(jar: attempt.cookieJar) {
                    return .captchaRequired(imageData: img, message: "请输入验证码")
                }
                clearSensitiveState()
                return .failure(message: "无法获取验证码，请稍后重试")
            }
            clearSensitiveState()
            return .failure(message: "统一认证登录失败，请检查账号密码或稍后重试")
        }
    }

    private func handleAuthRedirect(baseURL: URL, location: String?) async -> BuctSsoAuthOutcome {
        guard let attempt = activeAttempt,
              let loc = location, !loc.isEmpty,
              let resolved = URL(string: loc, relativeTo: baseURL)?.absoluteURL else {
            clearSensitiveState()
            return .failure(message: "统一认证未返回有效跳转地址")
        }

        if attempt.mode == .webVpn {
            return await completeWebVpnLogin(initialURL: resolved, jar: attempt.cookieJar)
        }

        var current = resolved
        for _ in 0..<12 {
            let host = current.host?.lowercased() ?? ""
            guard current.scheme?.lowercased() == "https",
                  host == "sidportal.buct.edu.cn" || host == "jwglxt.buct.edu.cn" else {
                clearSensitiveState()
                return .failure(message: "统一认证跳转域名异常")
            }

            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
            guard let resp = try? await transport.send(req, cookieJar: attempt.cookieJar, timeout: 25) else {
                clearSensitiveState()
                return .failure(message: "连接教务系统失败")
            }
            if resp.isRedirect {
                guard let nextLoc = resp.header("Location"),
                      let nextURL = URL(string: nextLoc, relativeTo: current)?.absoluteURL else {
                    clearSensitiveState()
                    return .failure(message: "教务系统跳转地址无效")
                }
                current = nextURL
                continue
            }
            let body = resp.bodyString
            if host == "jwglxt.buct.edu.cn" &&
                current.path.contains("/xtgl/index_initMenu.html") &&
                !body.contains("用户登录") && !body.contains("login_slogin") {
                let jwCookie = Self.stripRememberMe(
                    attempt.cookieJar.cookieHeaderFor(
                        url: URL(string: "https://jwglxt.buct.edu.cn/jwglxt/")!,
                        setByHost: "jwglxt.buct.edu.cn"
                    )
                )
                let sidCookie = exportSidCookie(from: attempt.cookieJar)
                clearSensitiveState()
                if jwCookie.isEmpty {
                    return .failure(message: "未获取到教务系统会话 Cookie")
                }
                return .success(jwglxtCookie: jwCookie, sidCookie: sidCookie, vpnTicket: nil)
            }
            clearSensitiveState()
            return .failure(message: "教务系统认证未完成，请重试")
        }
        clearSensitiveState()
        return .failure(message: "统一认证跳转次数过多")
    }

    private func completeWebVpnLogin(initialURL: URL, jar: MatchingMemoryCookieJar) async -> BuctSsoAuthOutcome {
        var current = initialURL
        for _ in 0..<4 {
            if current.host?.caseInsensitiveCompare(BuctWebVpnCodec.vpnHost) == .orderedSame {
                let comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
                let casTicket = comps?.queryItems?.first(where: { $0.name == "ticket" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !casTicket.isEmpty,
                      let vpnTicket = await webVpn.activateWithCasTicket(casTicket) else {
                    clearSensitiveState()
                    return .failure(message: "激活 WebVPN 票据失败")
                }
                let sidCookie = exportSidCookie(from: jar)
                clearSensitiveState()
                return .success(jwglxtCookie: "", sidCookie: sidCookie, vpnTicket: vpnTicket)
            }
            guard current.host?.caseInsensitiveCompare("sidportal.buct.edu.cn") == .orderedSame else {
                break
            }
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
            guard let resp = try? await transport.send(req, cookieJar: jar, timeout: 15),
                  resp.isRedirect,
                  let loc = resp.header("Location"),
                  let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                break
            }
            current = next
        }
        clearSensitiveState()
        return .failure(message: "WebVPN 未返回有效认证票据")
    }

    private func followPortalRedirects(url: URL, attempt: AttemptState) async -> HttpResponseData? {
        var current = url
        for _ in 0..<12 {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            if attempt.mode == .sidPortalOnly {
                applyPortalBrowserHeaders(&req, referer: current.absoluteString)
            } else {
                req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
            }
            guard let resp = try? await transport.send(req, cookieJar: attempt.cookieJar, timeout: 25) else {
                return nil
            }
            if resp.isRedirect {
                guard let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL,
                      next.host?.caseInsensitiveCompare("sidportal.buct.edu.cn") == .orderedSame else {
                    return nil
                }
                current = next
            } else {
                return resp
            }
        }
        return nil
    }

    private func fetchCaptchaImage(jar: MatchingMemoryCookieJar) async -> Data? {
        let url = URL(string: "\(Self.authPortalBase)/api/captcha/generate/DEFAULT")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        guard let resp = try? await transport.send(req, cookieJar: jar, timeout: 15),
              resp.isSuccessful, !resp.body.isEmpty else {
            return nil
        }
        return resp.body
    }

    private func loginURL(serviceURL: URL) -> URL {
        var comps = URLComponents(string: "\(Self.authPortalBase)/login")!
        comps.queryItems = [URLQueryItem(name: "service", value: serviceURL.absoluteString)]
        return comps.url!
    }

    private func applyPortalBrowserHeaders(_ req: inout URLRequest, referer: String) {
        req.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("\"Chromium\";v=\"154\", \"Google Chrome\";v=\"154\", \"Not A(Brand\";v=\"99\"", forHTTPHeaderField: "sec-ch-ua")
        req.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        req.setValue("\"Windows\"", forHTTPHeaderField: "sec-ch-ua-platform")
        req.setValue(referer, forHTTPHeaderField: "Referer")
    }

    private func applySecondaryApiHeaders(_ req: inout URLRequest, attempt: AttemptState) {
        req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue("zh_CN", forHTTPHeaderField: "sid-language")
        req.setValue(attempt.csrfKey, forHTTPHeaderField: "Csrf-Key")
        req.setValue(attempt.csrfValue, forHTTPHeaderField: "Csrf-Value")
        req.setValue(Self.deviceIDFixed, forHTTPHeaderField: "Device-Id")
        req.setValue(Self.authPortalBase, forHTTPHeaderField: "Origin")
        req.setValue("\(Self.authPortalBase)/login", forHTTPHeaderField: "Referer")
    }

    private func exportSidCookie(from jar: MatchingMemoryCookieJar) -> String {
        let raw = jar.cookieHeaderFor(
            url: URL(string: "\(Self.authPortalBase)/login")!,
            setByHost: "sidportal.buct.edu.cn"
        )
        return Self.stripRememberMe(raw)
    }

    public static func stripRememberMe(_ header: String) -> String {
        header.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("rememberMe=") }
            .joined(separator: "; ")
    }

    public static func generateCsrfPair() -> (key: String, value: String) {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var key = ""
        for _ in 0..<32 {
            key.append(chars[Int.random(in: 0..<chars.count)])
        }
        let encoded = Data(key.utf8).base64EncodedString()
        let halfIdx = encoded.index(encoded.startIndex, offsetBy: encoded.count / 2)
        let combined = String(encoded[..<halfIdx]) + encoded + String(encoded[halfIdx...])
        return (key, BuctCrypto.md5Hex(combined))
    }

    public static func extractHtmlParagraphField(_ html: String, id targetId: String) -> String? {
        let pattern = #"<p[^>]*id="([^"]+)"[^>]*>(.*?)</p>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: nsRange) {
            guard match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let valRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            if html[idRange] == targetId {
                let val = String(html[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                return val.isEmpty ? nil : val
            }
        }
        return nil
    }

    private static func extractInputValue(_ html: String, name: String) -> String? {
        let pattern = "<input[^>]*name=[\"']\(NSRegularExpression.escapedPattern(for: name))[\"'][^>]*value=[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static func isSecondarySmsPage(_ html: String) -> Bool {
        if html.contains("smsNoPhoneloginForm") || html.contains("二次身份验证") {
            return true
        }
        let ssoSecond = extractHtmlParagraphField(html, id: "sso-second") ?? ""
        guard ssoSecond.caseInsensitiveCompare("true") == .orderedSame else { return false }
        let loginType = extractHtmlParagraphField(html, id: "current-login-type") ?? ""
        return loginType.isEmpty || loginType.caseInsensitiveCompare("smsLogin") == .orderedSame
    }

    private static func extractSecondaryPhone(_ html: String) -> String {
        if let bound = extractHtmlParagraphField(html, id: "phone-number"),
           bound.count == 11, bound.allSatisfy(\.isNumber) {
            return "\(bound.prefix(3))****\(bound.suffix(4))"
        }
        if let regex = try? NSRegularExpression(pattern: #"已绑定手机号[：:]\s*([0-9*\s-]{7,})"#),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private static func extractSecondaryError(obj: [String: Any]?, fallback: String) -> String {
        if let data = obj?["data"] as? [String: Any],
           let err = data["errorMessage"] as? String, !err.isEmpty {
            return err
        }
        if let msg = obj?["message"] as? String, !msg.isEmpty {
            return msg
        }
        return fallback
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
