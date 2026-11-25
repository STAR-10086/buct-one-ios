import BuctModel
import BuctNetwork
import Foundation

public actor JwNoticeClient {
    private static let jwBase = "https://jwglxt.buct.edu.cn"
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let jwSsoService = "https://jwglxt.buct.edu.cn/sso/jziotlogin"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    private static let mobileUA =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/139.0.0.0 Mobile Safari/537.36"

    private let transport: BuctHttpTransport
    private let jar = MatchingMemoryCookieJar()
    private var authenticated = false

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func seedCookies(sidCookies: String, jwCookies: String) {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }
        let cleanJw = jwCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanJw.isEmpty {
            jar.seed(cookieHeader: cleanJw, setByHost: "jwglxt.buct.edu.cn")
            authenticated = true
        } else {
            authenticated = false
        }
    }

    public func exportJwCookies() -> String {
        jar.cookieHeaderFor(url: URL(string: "\(Self.jwBase)/jwglxt/")!)
    }

    public func fetchFullSnapshot(sidCookies: String, jwCookies: String) async throws -> JwNoticeSnapshot {
        seedCookies(sidCookies: sidCookies, jwCookies: jwCookies)
        if !authenticated {
            try await authenticateWithSso()
        }

        var remTuple: (total: Int, items: [JwReminderItem])?
        var annTuple: (total: Int, items: [JwAnnouncementItem])?
        var firstNonAuthError: Error?

        do {
            remTuple = try await fetchRemindersPage(page: 1, pageSize: 30)
        } catch let err as JwNoticeAuthExpiredError {
            throw err
        } catch {
            firstNonAuthError = error
        }

        do {
            annTuple = try await fetchAnnouncementsPage(page: 1, pageSize: 25)
        } catch let err as JwNoticeAuthExpiredError {
            throw err
        } catch {
            if firstNonAuthError == nil { firstNonAuthError = error }
        }

        if remTuple == nil && annTuple == nil {
            throw firstNonAuthError ?? NSError(domain: "JwNoticeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "教务消息同步失败"])
        }

        return JwNoticeSnapshot(
            reminders: remTuple?.items ?? [],
            reminderTotal: remTuple?.total ?? 0,
            announcements: annTuple?.items ?? [],
            announcementTotal: annTuple?.total ?? 0
        )
    }

    public func fetchRemindersPage(page: Int = 1, pageSize: Int = 30, keyword: String = "") async throws -> (total: Int, items: [JwReminderItem]) {
        let url = URL(string: "\(Self.jwBase)/jwglxt/xtgl/index_cxDbsy.html?doType=query")!
        var params: [(String, String)] = [
            ("flag", "1"),
            ("queryModel.showCount", "\(pageSize)"),
            ("queryModel.currentPage", "\(page)"),
            ("queryModel.sortName", "cjsj"),
            ("queryModel.sortOrder", "desc"),
            ("time", "0")
        ]
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            params.append(("gnmkmc", kw))
        }
        let resp = try await executePost(
            url: url,
            referer: "\(Self.jwBase)/jwglxt/xtgl/index_initMenu.html",
            params: params
        )
        return try JwNoticeParser.parseRemindersPage(resp.bodyString)
    }

    public func fetchAnnouncementsPage(page: Int = 1, pageSize: Int = 25, keyword: String = "") async throws -> (total: Int, items: [JwAnnouncementItem]) {
        let url = URL(string: "\(Self.jwBase)/jwglxt/xtgl/xwck_cxMoreXwList.html?doType=query")!
        var params: [(String, String)] = [
            ("queryModel.showCount", "\(pageSize)"),
            ("queryModel.currentPage", "\(page)"),
            ("queryModel.sortName", "fbsj"),
            ("queryModel.sortOrder", "desc"),
            ("time", "0")
        ]
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            params.append(("xwbt", kw))
        }
        let resp = try await executePost(
            url: url,
            referer: "\(Self.jwBase)/jwglxt/xtgl/xwck_cxMoreXwList.html",
            params: params
        )
        return try JwNoticeParser.parseAnnouncementsPage(resp.bodyString)
    }

    public func fetchAnnouncementDetail(item: JwAnnouncementItem) async throws -> JwAnnouncementDetail {
        let encoded = item.id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.id
        let url = URL(string: "\(Self.jwBase)/jwglxt/xtgl/xwck_ckXw.html?xwbh=\(encoded)&doType=save")!
        let resp = try await executeGet(
            url: url,
            accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            referer: "\(Self.jwBase)/jwglxt/xtgl/xwck_cxMoreXwList.html"
        )
        return JwNoticeParser.parseAnnouncementDetail(html: resp.bodyString, item: item)
    }

    private func executeGet(url: URL, accept: String, referer: String, allowReauth: Bool = true) async throws -> HttpResponseData {
        if !authenticated {
            try await authenticateWithSso()
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        let resp = try await transport.send(req, cookieJar: jar, timeout: 25)
        if isExpiredResponse(resp) {
            authenticated = false
            if allowReauth {
                try await authenticateWithSso()
                return try await executeGet(url: url, accept: accept, referer: referer, allowReauth: false)
            }
            throw JwNoticeAuthExpiredError()
        }
        guard resp.isSuccessful else {
            throw NSError(domain: "JwNoticeClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "教务系统请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp
    }

    private func executePost(url: URL, referer: String, params: [(String, String)], allowReauth: Bool = true) async throws -> HttpResponseData {
        if !authenticated {
            try await authenticateWithSso()
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue(Self.jwBase, forHTTPHeaderField: "Origin")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode(params)

        let resp = try await transport.send(req, cookieJar: jar, timeout: 25)
        if isExpiredResponse(resp) {
            authenticated = false
            if allowReauth {
                try await authenticateWithSso()
                return try await executePost(url: url, referer: referer, params: params, allowReauth: false)
            }
            throw JwNoticeAuthExpiredError()
        }
        guard resp.isSuccessful else {
            throw NSError(domain: "JwNoticeClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "教务系统请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp
    }

    private func isExpiredResponse(_ resp: HttpResponseData) -> Bool {
        if [401, 403].contains(resp.statusCode) || resp.isRedirect {
            return true
        }
        return JwNoticeParser.isJwLoginHtml(resp.bodyString)
    }

    private func authenticateWithSso() async throws {
        let encodedService = Self.jwSsoService.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? Self.jwSsoService
        var current = URL(string: "https://\(Self.sidPortalHost)/login?service=\(encodedService)")!

        for _ in 0..<12 {
            let host = current.host?.lowercased() ?? ""
            if (host == "jwglxt.buct.edu.cn" || host == Self.sidPortalHost) && current.scheme?.lowercased() == "http" {
                var comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
                comps?.scheme = "https"
                if let upgraded = comps?.url { current = upgraded }
            }

            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            let ua = (host == Self.sidPortalHost || host == "portal.buct.edu.cn") ? Self.mobileUA : Self.desktopUA
            req.setValue(ua, forHTTPHeaderField: "User-Agent")

            let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
            if resp.isRedirect {
                guard let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    break
                }
                let nextHost = next.host?.lowercased() ?? ""
                guard ["jwglxt.buct.edu.cn", Self.sidPortalHost, "portal.buct.edu.cn"].contains(nextHost) else {
                    break
                }
                current = next
                continue
            }

            if host == "jwglxt.buct.edu.cn" && resp.isSuccessful && !JwNoticeParser.isJwLoginHtml(resp.bodyString) {
                authenticated = true
                return
            }
            break
        }
        throw JwNoticeAuthExpiredError()
    }

    private func formEncode(_ pairs: [(String, String)]) -> Data {
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
