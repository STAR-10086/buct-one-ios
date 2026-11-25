import BuctModel
import BuctNetwork
import Foundation

public actor ScsClient {
    private static let eapiBase = "https://eapi.buct.edu.cn"
    private static let fallbackCasURL = "https://sidportal.buct.edu.cn/login?service=https%3A%2F%2Fscs.buct.edu.cn%2FcommonLogin"
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    private let webVpn: BuctWebVpnManager
    private let jar = MatchingMemoryCookieJar()
    private var jwtToken: String = ""

    public init(webVpn: BuctWebVpnManager = .shared) {
        self.webVpn = webVpn
    }

    public func clearSession() {
        jar.clear()
        jwtToken = ""
    }

    public func fetchSnapshot(sidCookies: String, fallbackStudentId: String) async throws -> ScsSnapshot {
        try await withAuthRetry(sidCookies: sidCookies) {
            let userText = (try? await getApi(path: "/sysAccount/getLoginUserInfo")) ?? ""
            let user = ScsParser.parseUserInfo(userText)
            let resolvedId = user.studentId.isEmpty ? fallbackStudentId : user.studentId

            let windowText = (try? await getApi(path: "/scSelfEvalTerm/getDefaultYearAndTerm")) ?? ""
            let window = ScsParser.parseDefaultWindow(windowText)

            let dimText = (try? await getApi(path: "/scStudentEvaluationType/getEvaluationType")) ?? ""
            let dims = ScsParser.parseDimensions(dimText)

            let scoresText = try await getApi(path: "/tStudent/getLoginStudentAllScore")
            let terms = try ScsParser.parseAllTermScores(scoresText, dimensions: dims)

            let histText = (try? await postApi(path: "/scStudentScore/listStudentHistoryScore?xh=\(resolvedId)", body: [:])) ?? ""
            let hist = ScsParser.parseHistoryProfile(histText)

            let actText = (try? await postApi(path: "/scActivity/listByCondition?currentPage=1&pageSize=30", body: [:])) ?? ""
            let activities = ScsParser.parseActivities(actText)

            return ScsSnapshot(
                studentName: user.name,
                studentId: resolvedId,
                collegeName: hist.college,
                className: hist.className,
                gradeName: hist.grade,
                currentWindow: window,
                dimensions: dims,
                terms: terms,
                activities: activities
            )
        }
    }

    // MARK: - Auth & HTTP

    private func withAuthRetry<T>(sidCookies: String, _ block: () async throws -> T) async throws -> T {
        if jwtToken.isEmpty {
            try await authenticate(sidCookies: sidCookies)
        }
        do {
            return try await block()
        } catch is ScsAuthExpiredError {
            jwtToken = ""
            try await authenticate(sidCookies: sidCookies)
            return try await block()
        }
    }

    private func authenticate(sidCookies: String) async throws {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }

        var startURL = URL(string: Self.fallbackCasURL)!
        if let opText = try? await getRaw(url: URL(string: "\(Self.eapiBase)/cas/opLogin")!),
           let opData = try? ScsParser.parseEnvelope(opText) as? String,
           let parsed = URL(string: opData),
           parsed.scheme?.hasPrefix("http") == true {
            startURL = parsed
        }

        var current = startURL
        var ticket = ""
        for _ in 0..<12 {
            if let comps = URLComponents(url: current, resolvingAgainstBaseURL: false),
               let t = comps.queryItems?.first(where: { $0.name == "ticket" })?.value,
               !t.isEmpty {
                ticket = t
                break
            }
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
            if resp.isRedirect, let loc = resp.header("Location"),
               let next = URL(string: loc, relativeTo: current)?.absoluteURL {
                current = next
                continue
            }
            break
        }

        guard !ticket.isEmpty else {
            throw ScsAuthExpiredError("未能获取第二课堂 CAS 票据，请重新登录统一身份认证")
        }

        let loginText = try await getRaw(url: URL(string: "\(Self.eapiBase)/sys/casLogin?ticket=\(ticket)")!)
        guard let token = try ScsParser.parseEnvelope(loginText) as? String, !token.isEmpty else {
            throw ScsAuthExpiredError("第二课堂令牌换取失败")
        }
        jwtToken = token
    }

    private func getRaw(url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
        guard resp.statusCode == 200 else {
            throw ScsAuthExpiredError("第二课堂认证请求失败（HTTP \(resp.statusCode)）")
        }
        return resp.decodedText()
    }

    private func getApi(path: String) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Self.eapiBase)\(path)")!)
        req.httpMethod = "GET"
        applyHeaders(&req)
        let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
        if resp.statusCode == 401 || resp.statusCode == 403 {
            throw ScsAuthExpiredError()
        }
        guard resp.statusCode == 200 else {
            throw NSError(domain: "ScsClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "第二课堂请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp.decodedText()
    }

    private func postApi(path: String, body: [String: Any]) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Self.eapiBase)\(path)")!)
        req.httpMethod = "POST"
        applyHeaders(&req)
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
        if resp.statusCode == 401 || resp.statusCode == 403 {
            throw ScsAuthExpiredError()
        }
        guard resp.statusCode == 200 else {
            throw NSError(domain: "ScsClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "第二课堂请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp.decodedText()
    }

    private func applyHeaders(_ req: inout URLRequest) {
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(jwtToken, forHTTPHeaderField: "App-Token")
        req.setValue("yfdop", forHTTPHeaderField: "App-source")
        req.setValue("1.0.0", forHTTPHeaderField: "App-Version")
        req.setValue("buct-one-ios", forHTTPHeaderField: "Device-Id")
    }
}
