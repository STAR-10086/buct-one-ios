import Foundation

/// 线程安全的内存 CookieJar，记录每条 Cookie 的来源 `(setByHost, setByPort)`，
/// 并严格区分 `_zte_cid_`（`.buct.edu.cn` 域）与其它 host-only Cookie（如 `SOURCEID_TGC`、`SESSION`）。
public final class MatchingMemoryCookieJar: @unchecked Sendable {
    private struct StoredCookie {
        let cookie: HTTPCookie
        let setByHost: String
        let setByPort: Int
    }

    private let lock = NSLock()
    private var entries: [StoredCookie] = []

    public init() {}

    public func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    public func saveFromResponse(url: URL, headers: [String: String]) {
        guard let host = url.host?.lowercased() else { return }
        let port = Self.effectivePort(for: url)
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        guard !parsed.isEmpty else { return }

        let now = Date()
        lock.lock()
        defer { lock.unlock() }
        for cookie in parsed {
            entries.removeAll {
                $0.cookie.name == cookie.name &&
                $0.cookie.domain.caseInsensitiveCompare(cookie.domain) == .orderedSame &&
                $0.cookie.path == cookie.path
            }
            if let exp = cookie.expiresDate, exp <= now {
                continue
            }
            entries.append(StoredCookie(cookie: cookie, setByHost: host, setByPort: port))
        }
    }

    public func loadForRequest(url: URL) -> [HTTPCookie] {
        purgeExpired()
        lock.lock()
        defer { lock.unlock() }
        return entries
            .map(\.cookie)
            .filter { Self.matches(cookie: $0, url: url) }
    }

    public func cookieHeaderFor(url: URL, setByHost: String? = nil) -> String {
        purgeExpired()
        let hostFilter = setByHost?.lowercased()
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        var pairs: [String] = []
        for entry in entries {
            if let hostFilter, entry.setByHost != hostFilter {
                continue
            }
            guard Self.matches(cookie: entry.cookie, url: url) else { continue }
            if seen.insert(entry.cookie.name).inserted {
                pairs.append("\(entry.cookie.name)=\(entry.cookie.value)")
            }
        }
        return pairs.joined(separator: "; ")
    }

    public func cookiesSetBy(host: String, port: Int = 443) -> [HTTPCookie] {
        purgeExpired()
        let lowerHost = host.lowercased()
        lock.lock()
        defer { lock.unlock() }
        return entries
            .filter { $0.setByHost == lowerHost && $0.setByPort == port }
            .map(\.cookie)
    }

    public func seed(cookieHeader: String, setByHost: String, port: Int = 443, path: String = "/") {
        let lowerHost = setByHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowerHost.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        for segment in cookieHeader.split(separator: ";") {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let eqIdx = trimmed.firstIndex(of: "="), eqIdx != trimmed.startIndex else { continue }
            let name = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty else { continue }

            let domain = Self.domainFor(cookieName: name, setByHost: lowerHost)
            let cookiePath = name == "_zte_cid_" ? "/" : path
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: cookiePath,
                .originURL: URL(string: "https://\(lowerHost)/")!
            ]
            guard let cookie = HTTPCookie(properties: props) else { continue }
            entries.removeAll {
                $0.cookie.name == name &&
                $0.cookie.domain.caseInsensitiveCompare(domain) == .orderedSame &&
                $0.cookie.path == cookiePath
            }
            entries.append(StoredCookie(cookie: cookie, setByHost: lowerHost, setByPort: port))
        }
    }

    private func purgeExpired() {
        let now = Date()
        lock.lock()
        entries.removeAll { entry in
            if let exp = entry.cookie.expiresDate {
                return exp <= now
            }
            return false
        }
        lock.unlock()
    }

    private static func domainFor(cookieName: String, setByHost: String) -> String {
        if cookieName == "_zte_cid_" {
            return ".buct.edu.cn"
        }
        return setByHost
    }

    private static func effectivePort(for url: URL) -> Int {
        if let port = url.port { return port }
        return url.scheme?.lowercased() == "http" ? 80 : 443
    }

    private static func matches(cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let cookieDomain = cookie.domain.lowercased()
        let domainMatch: Bool
        if cookieDomain.hasPrefix(".") {
            let bare = String(cookieDomain.dropFirst())
            domainMatch = host == bare || host.hasSuffix(cookieDomain)
        } else {
            domainMatch = host == cookieDomain
        }
        guard domainMatch else { return false }

        if cookie.isSecure && url.scheme?.lowercased() != "https" {
            return false
        }

        let reqPath = url.path.isEmpty ? "/" : url.path
        let cPath = cookie.path.isEmpty ? "/" : cookie.path
        if reqPath == cPath || cPath == "/" {
            return true
        }
        if reqPath.hasPrefix(cPath) {
            return cPath.hasSuffix("/") || reqPath.dropFirst(cPath.count).first == "/"
        }
        return false
    }
}
