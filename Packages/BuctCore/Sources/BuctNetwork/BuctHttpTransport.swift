import Foundation

public struct HttpResponseData: Sendable {
    public let url: URL
    public let statusCode: Int
    public let headers: [String: String]
    public let setCookieHeaders: [String]
    public let body: Data
    public let viaWebVpn: Bool

    public var isRedirect: Bool { (300...399).contains(statusCode) }
    public var isSuccessful: Bool { (200...299).contains(statusCode) }

    public var bodyString: String {
        String(data: body, encoding: .utf8)
            ?? String(data: body, encoding: .isoLatin1)
            ?? ""
    }

    public func decodedText(preferGBKFallback: Bool = false) -> String {
        guard !body.isEmpty else { return "" }
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        let declaredCharset: String? = {
            if let ct = header("Content-Type"),
               let cs = Self.extractCharset(from: ct) {
                return cs
            }
            let head = Data(body.prefix(2048))
            if let latin = String(data: head, encoding: .isoLatin1),
               let cs = Self.extractCharset(from: latin) {
                return cs
            }
            return nil
        }()

        if let charset = declaredCharset?.lowercased() {
            if charset.contains("gb") {
                return String(data: body, encoding: gbkEncoding)
                    ?? String(data: body, encoding: .utf8)
                    ?? String(data: body, encoding: .isoLatin1)
                    ?? ""
            }
            if charset.contains("utf-8") || charset.contains("utf8") {
                return String(data: body, encoding: .utf8)
                    ?? String(data: body, encoding: gbkEncoding)
                    ?? String(data: body, encoding: .isoLatin1)
                    ?? ""
            }
        }

        if let utf8 = String(data: body, encoding: .utf8) {
            return utf8
        }
        if preferGBKFallback, let gbk = String(data: body, encoding: gbkEncoding) {
            return gbk
        }
        return String(data: body, encoding: .isoLatin1) ?? ""
    }

    private static func extractCharset(from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"charset\s*=\s*['"]?([a-zA-Z0-9_\-]+)"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public init(
        url: URL,
        statusCode: Int,
        headers: [String: String],
        setCookieHeaders: [String],
        body: Data,
        viaWebVpn: Bool = false
    ) {
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.setCookieHeaders = setCookieHeaders
        self.body = body
        self.viaWebVpn = viaWebVpn
    }
}

private final class NoRedirectTlsDelegate: NSObject, URLSessionTaskDelegate, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        BuctTlsDelegate.shared.urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // 禁止隐式自动重定向，交由业务/WebVPN 层逐跳校验域名与票据
        completionHandler(nil)
    }
}

/// 统一无重定向 HTTP 传输层：
/// - 强制 BuctTlsDelegate 校方双链证书校验
/// - 禁用系统自带 HTTPCookieStorage，避免跨账号/跨模式污染
public final class BuctHttpTransport: @unchecked Sendable {
    public static let shared = BuctHttpTransport()

    private let delegate = NoRedirectTlsDelegate()
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    public func send(
        _ request: URLRequest,
        cookieJar: MatchingMemoryCookieJar? = nil,
        overrideTicketCookie: String? = nil,
        timeout: TimeInterval = 20
    ) async throws -> HttpResponseData {
        var req = request
        req.timeoutInterval = timeout

        if let url = req.url {
            var cookieParts: [String] = []
            if let existing = req.value(forHTTPHeaderField: "Cookie"), !existing.isEmpty {
                cookieParts.append(existing)
            }
            if let cookieJar {
                let jarCookies = cookieJar.cookieHeaderFor(url: url)
                if !jarCookies.isEmpty {
                    cookieParts.append(jarCookies)
                }
            }
            if !cookieParts.isEmpty {
                let merged = mergeCookieStrings(cookieParts)
                req.setValue(merged, forHTTPHeaderField: "Cookie")
            }
            if let ticket = overrideTicketCookie, !ticket.isEmpty {
                req.setValue(
                    Self.mergeVpnTicket(existingHeader: req.value(forHTTPHeaderField: "Cookie"), ticket: ticket),
                    forHTTPHeaderField: "Cookie"
                )
            }
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        var normalizedHeaders: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                normalizedHeaders[ks] = vs
            }
        }

        if let url = req.url, let cookieJar {
            cookieJar.saveFromResponse(url: url, headers: normalizedHeaders)
        }

        let setCookies = Self.extractSetCookieList(from: normalizedHeaders)
        return HttpResponseData(
            url: http.url ?? req.url ?? URL(string: "https://sidportal.buct.edu.cn")!,
            statusCode: http.statusCode,
            headers: normalizedHeaders,
            setCookieHeaders: setCookies,
            body: data,
            viaWebVpn: false
        )
    }

    public static func mergeVpnTicket(existingHeader: String?, ticket: String) -> String {
        let cookieName = BuctWebVpnCodec.vpnCookieName
        var parts = ["\(cookieName)=\(ticket)"]
        if let existingHeader, !existingHeader.isEmpty {
            for seg in existingHeader.split(separator: ";") {
                let trimmed = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let name = trimmed.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                if name.caseInsensitiveCompare(cookieName) != .orderedSame {
                    parts.append(trimmed)
                }
            }
        }
        return parts.joined(separator: "; ")
    }

    public static func extractCookieValue(from headers: [String: String], name targetName: String) -> String {
        for (key, value) in headers where key.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            let candidates = splitCombinedSetCookieHeader(value)
            var latest = ""
            for raw in candidates {
                let pair = raw.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                let kv = pair.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    let name = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let val = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.caseInsensitiveCompare(targetName) == .orderedSame,
                       !val.isEmpty,
                       val.caseInsensitiveCompare("deleteMe") != .orderedSame {
                        latest = val
                    }
                }
            }
            if !latest.isEmpty { return latest }
        }
        return ""
    }

    private func mergeCookieStrings(_ headers: [String]) -> String {
        var map: [String: String] = [:]
        var order: [String] = []
        for h in headers {
            for seg in h.split(separator: ";") {
                let trimmed = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let eq = trimmed.firstIndex(of: "=") else { continue }
                let name = String(trimmed[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !val.isEmpty else { continue }
                if map[name] == nil { order.append(name) }
                map[name] = val
            }
        }
        return order.compactMap { k in map[k].map { "\(k)=\($0)" } }.joined(separator: "; ")
    }

    private static func extractSetCookieList(from headers: [String: String]) -> [String] {
        for (k, v) in headers where k.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            return splitCombinedSetCookieHeader(v)
        }
        return []
    }

    private static func splitCombinedSetCookieHeader(_ header: String) -> [String] {
        // HTTPURLResponse.allHeaderFields 将多条 Set-Cookie 以 ", " 拼接；
        // 但 Expires=Wed, 25 Nov... 内也含 ", "，故仅在后跟 "name=" 时切分。
        var results: [String] = []
        var current = ""
        let parts = header.components(separatedBy: ", ")
        for part in parts {
            if current.isEmpty {
                current = part
            } else if part.range(of: #"^[A-Za-z0-9_\-\.]+="#, options: .regularExpression) != nil {
                results.append(current)
                current = part
            } else {
                current += ", " + part
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }
}
