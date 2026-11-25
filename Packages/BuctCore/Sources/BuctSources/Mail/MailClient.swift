import BuctModel
import BuctNetwork
import Foundation

public actor MailClient {
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let ssoLoginURL = "https://sidportal.buct.edu.cn/login?service=https%3A%2F%2Fmailuser.buct.edu.cn%2Fbuct%2Fapi%2Flogin"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    private static let siriusAppName = "sirius-web"
    private static let siriusVersion = "1.67.0"
    private static let maxRedirectHops = 16
    private static let maxDownloadBytes: Int64 = 100 * 1024 * 1024

    private let transport: BuctHttpTransport
    private let jar = MatchingMemoryCookieJar()
    private var mailBase: String = ""
    private var mailHost: String = ""
    private var sid: String = ""

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func clearSession() {
        jar.clear()
        mailBase = ""
        mailHost = ""
        sid = ""
    }

    public func fetchInitialSnapshot(sidCookies: String, pageSize: Int = 30) async throws -> MailSnapshot {
        try await ensureAuthenticated(sidCookies: sidCookies)
        let account = (try? await fetchAccountInfo()) ?? MailAccountInfo()
        let folders = try await fetchFolders(sidCookies: sidCookies)
        let inbox = try await listMessages(sidCookies: sidCookies, folderId: MailFolder.inboxId, start: 0, limit: pageSize, unreadOnly: false)
        return MailSnapshot(account: account, folders: folders, inboxTotal: inbox.total, inboxMessages: inbox.messages)
    }

    public func fetchFolders(sidCookies: String) async throws -> [MailFolder] {
        try await withSessionRetry(sidCookies: sidCookies) {
            let text = try await postRpc(funcName: "mbox:getAllFolders", body: ["order": "custom_virtual"])
            return try MailParser.parseFolders(jsonString: text)
        }
    }

    public func listMessages(
        sidCookies: String,
        folderId: Int,
        start: Int = 0,
        limit: Int = 30,
        unreadOnly: Bool = false
    ) async throws -> (total: Int, messages: [MailMessageSummary]) {
        try await withSessionRetry(sidCookies: sidCookies) {
            let filter: [String: Any] = unreadOnly ? ["flags": ["read": false]] : [:]
            let payload: [String: Any] = [
                "fid": folderId,
                "start": start,
                "limit": limit,
                "summaryWindowSize": limit,
                "order": "date",
                "desc": true,
                "returnTotal": true,
                "returnTid": true,
                "returnTag": true,
                "returnAttachments": true,
                "skipLockedFolders": false,
                "filter": filter
            ]
            let text = try await postRpc(funcName: "mbox:listMessages", body: payload)
            return try MailParser.parseMessages(jsonString: text, defaultFolderId: folderId)
        }
    }

    public func readMessageDetail(sidCookies: String, messageId: String, folderId: Int) async throws -> MailMessageDetail {
        try await withSessionRetry(sidCookies: sidCookies) {
            let payload: [String: Any] = [
                "id": messageId,
                "level": 32,
                "mode": "html",
                "returnHeaders": ["Resent-From": "A", "Sender": "A"],
                "markRead": false
            ]
            let text = try await postRpc(
                funcName: "mbox:readMessage",
                extraQuery: "&l=read&uid=&supportTNEF=true",
                body: payload
            )
            return try MailParser.parseMessageDetail(jsonString: text, fallbackId: messageId, fallbackFolderId: folderId)
        }
    }

    public func setMessageRead(sidCookies: String, messageId: String, isRead: Bool) async throws {
        try await withSessionRetry(sidCookies: sidCookies) {
            let payload: [String: Any] = [
                "ids": [messageId],
                "attrs": ["flags": ["read": isRead]]
            ]
            let text = try await postRpc(funcName: "mbox:updateMessageInfos", body: payload)
            try MailParser.validateRpcSuccess(jsonString: text)
        }
    }

    public func moveMessage(sidCookies: String, messageId: String, targetFolderId: Int) async throws {
        try await withSessionRetry(sidCookies: sidCookies) {
            let payload: [String: Any] = [
                "ids": [messageId],
                "attrs": ["fid": targetFolderId]
            ]
            let text = try await postRpc(funcName: "mbox:updateMessageInfos", body: payload)
            try MailParser.validateRpcSuccess(jsonString: text)
        }
    }

    public func deleteMessagePermanently(sidCookies: String, messageId: String) async throws {
        try await withSessionRetry(sidCookies: sidCookies) {
            let payload: [String: Any] = ["ids": [messageId]]
            let text = try await postRpc(funcName: "mbox:deleteMessages", body: payload)
            try MailParser.validateRpcSuccess(jsonString: text)
        }
    }

    public func markFolderAllRead(sidCookies: String, folderId: Int) async throws {
        try await withSessionRetry(sidCookies: sidCookies) {
            let payload: [String: Any] = ["fid": folderId, "read": true]
            let text = try await postRpc(funcName: "mbox:markSeen", body: payload)
            try MailParser.validateRpcSuccess(jsonString: text)
        }
    }

    public func downloadAttachment(
        sidCookies: String,
        messageId: String,
        attachment: MailAttachment,
        cacheDirectory: URL
    ) async throws -> MailDownloadedFile {
        try await withSessionRetry(sidCookies: sidCookies) {
            let encHost = Self.percentEncode(mailHost)
            let encSid = Self.percentEncode(sid)
            let encPart = Self.percentEncode(attachment.partId)
            let encMid = Self.percentEncode(messageId)
            let urlStr = "\(mailBase)/js6/s?_host=\(encHost)&func=mbox%3AgetMessageData&sid=\(encSid)&mode=download&part=\(encPart)&mid=\(encMid)&email=&_appName=\(Self.siriusAppName)&trigger_type=user_click"
            guard let url = URL(string: urlStr) else {
                throw NSError(domain: "MailClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "附件地址无效"])
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            applyCommonHeaders(&req)
            let resp = try await transport.send(req, cookieJar: jar, timeout: 60)
            guard resp.statusCode == 200 else {
                if [301, 302, 401, 403].contains(resp.statusCode) {
                    throw MailSessionExpiredError()
                }
                throw NSError(domain: "MailClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "附件下载失败（HTTP \(resp.statusCode)）"])
            }
            if Int64(resp.body.count) > Self.maxDownloadBytes {
                throw NSError(domain: "MailClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "附件体积超过 100MB 限制"])
            }
            let ct = resp.header("Content-Type") ?? attachment.contentType
            let isHtmlName = attachment.filename.lowercased().hasSuffix(".html") || attachment.filename.lowercased().hasSuffix(".htm")
            if !isHtmlName && ct.lowercased().contains("text/html") {
                let text = resp.decodedText()
                if text.contains("会话") || text.contains("登录") {
                    throw MailSessionExpiredError()
                }
            }

            let safeName = sanitizeFilename(attachment.filename)
            let hashDir = String(BuctCrypto.sha256Hex("\(messageId)|\(attachment.partId)").prefix(12))
            let targetDir = cacheDirectory.appendingPathComponent(hashDir, isDirectory: true)
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let targetURL = targetDir.appendingPathComponent(safeName)
            try resp.body.write(to: targetURL, options: [.atomic])
            return MailDownloadedFile(
                filePath: targetURL.path,
                fileName: safeName,
                mimeType: ct,
                sizeBytes: Int64(resp.body.count)
            )
        }
    }

    // MARK: - Auth & RPC

    private func withSessionRetry<T>(sidCookies: String, _ block: () async throws -> T) async throws -> T {
        try await ensureAuthenticated(sidCookies: sidCookies)
        do {
            return try await block()
        } catch is MailSessionExpiredError {
            sid = ""
            try await authenticateWithSso(sidCookies: sidCookies)
            return try await block()
        }
    }

    private func ensureAuthenticated(sidCookies: String) async throws {
        if !sid.isEmpty && !mailBase.isEmpty {
            return
        }
        try await authenticateWithSso(sidCookies: sidCookies)
    }

    private func authenticateWithSso(sidCookies: String) async throws {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }

        var current = URL(string: Self.ssoLoginURL)!
        for _ in 0..<Self.maxRedirectHops {
            guard isAllowedMailHost(current.host) else {
                throw MailSessionExpiredError("邮箱跳转域名不受信任")
            }
            if let extracted = extractSiriusSession(from: current) {
                mailBase = extracted.base
                mailHost = extracted.host
                sid = extracted.sid
                return
            }

            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            let resp = try await transport.send(req, cookieJar: jar, timeout: 20)

            if let extracted = extractSiriusSession(from: resp.url) {
                mailBase = extracted.base
                mailHost = extracted.host
                sid = extracted.sid
                return
            }

            if resp.isRedirect, let loc = resp.header("Location"),
               let next = URL(string: loc, relativeTo: current)?.absoluteURL {
                current = next
                continue
            }

            let html = resp.decodedText()
            if let next = MailParser.extractJsOrMetaRedirectURL(html: html, baseURL: resp.url) {
                current = next
                continue
            }

            if resp.url.host?.lowercased() == Self.sidPortalHost && (html.contains("login-croypto") || html.contains("UsernamePassword")) {
                throw MailSessionExpiredError("统一身份认证会话已过期，无法免密登录校园邮箱")
            }
            break
        }
        throw MailSessionExpiredError("未能完成校园邮箱 SSO 认证")
    }

    private func fetchAccountInfo() async throws -> MailAccountInfo? {
        let encHost = Self.percentEncode(mailHost)
        let encSid = Self.percentEncode(sid)
        let urlStr = "\(mailBase)/cowork/api/biz/enter/accountInfo?_host=\(encHost)&sid=\(encSid)&needUnitNamePath=false&_appName=\(Self.siriusAppName)&_version=\(Self.siriusVersion)"
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyCommonHeaders(&req)
        let resp = try await transport.send(req, cookieJar: jar, timeout: 15)
        guard resp.statusCode == 200 else { return nil }
        return MailParser.parseAccountInfo(jsonString: resp.decodedText())
    }

    private func postRpc(funcName: String, extraQuery: String = "", body: [String: Any]) async throws -> String {
        let encHost = Self.percentEncode(mailHost)
        let encSid = Self.percentEncode(sid)
        let encFunc = Self.percentEncode(funcName)
        let urlStr = "\(mailBase)/js6/s?_host=\(encHost)&sid=\(encSid)&_appName=\(Self.siriusAppName)&_version=\(Self.siriusVersion)&func=\(encFunc)&p=web\(extraQuery)"
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "MailClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "邮箱请求地址无效"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyCommonHeaders(&req)
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
        if resp.isRedirect || resp.statusCode == 401 || resp.statusCode == 403 {
            throw MailSessionExpiredError("校园邮箱登录已过期（HTTP \(resp.statusCode)）")
        }
        guard resp.statusCode == 200 else {
            throw NSError(domain: "MailClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "邮箱请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp.decodedText()
    }

    private func applyCommonHeaders(_ req: inout URLRequest) {
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("zh", forHTTPHeaderField: "Lingxi-Language")
        if !mailBase.isEmpty {
            req.setValue(mailBase, forHTTPHeaderField: "Origin")
            req.setValue("\(mailBase)/static/sirius-web/", forHTTPHeaderField: "Referer")
        }
    }

    private func extractSiriusSession(from url: URL) -> (base: String, host: String, sid: String)? {
        guard let host = url.host?.lowercased(), host.hasSuffix(".qiye.163.com"),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let sidVal = comps.queryItems?.first(where: { $0.name == "sid" })?.value,
              !sidVal.isEmpty else {
            return nil
        }
        return ("https://\(host)", host, sidVal)
    }

    private func isAllowedMailHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return h == "buct.edu.cn" || h.hasSuffix(".buct.edu.cn") || h == "qiye.163.com" || h.hasSuffix(".qiye.163.com")
    }

    private func sanitizeFilename(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "[\\\\/:*?\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "mail_attachment.bin" : cleaned
    }

    private static func percentEncode(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}
