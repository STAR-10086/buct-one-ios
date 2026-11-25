import BuctModel
import BuctNetwork
import Foundation

public actor TyglClient {
    private static let baseURL = "https://tygl.buct.edu.cn"
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    private let transport: BuctHttpTransport
    private let jar = MatchingMemoryCookieJar()

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func fetchSnapshot(sidCookies: String) async throws -> TyglSnapshot {
        try await ensureAuthenticated(sidCookies: sidCookies)

        let mainHtHtml = try await getAuthedPage(path: "/main.php?module=stu&title=stu_ht_score")
        let firstParsed = TyglParser.parseFitnessPage(html: mainHtHtml)
        var profile = firstParsed.profile ?? TyglStudentProfile()
        var records: [TyglFitnessRecord] = []
        if let r = firstParsed.record {
            records.append(r)
        }

        let yearTabs = TyglParser.extractYearTabs(from: mainHtHtml)
        for year in yearTabs where !records.contains(where: { $0.year == year }) {
            let enc = year.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? year
            if let html = try? await getAuthedPage(path: "/main.php?module=stu&title=stu_ht_score&year=\(enc)") {
                let parsed = TyglParser.parseFitnessPage(html: html, fallbackYear: year)
                if profile.name.isEmpty, let p = parsed.profile { profile = p }
                if let r = parsed.record { records.append(r) }
            }
        }

        let sunHtml = (try? await getAuthedPage(path: "/main.php?module=stu&title=stu_sun_score")) ?? ""
        let sun = TyglParser.parseSunScorePage(html: sunHtml)

        let peHtml = (try? await getAuthedPage(path: "/main.php?module=stu&title=stu_pe_score")) ?? ""
        let peCourses = TyglParser.parsePeCourses(html: peHtml)

        let examHtml = (try? await getAuthedPage(path: "/main.php?module=stu&title=stu_exam")) ?? ""
        let examInfo = TyglParser.parseExamPage(html: examHtml)

        return TyglSnapshot(
            profile: profile,
            fitnessRecords: records,
            runPlan: sun.runPlan,
            exerciseColumns: sun.columns,
            exerciseTerms: sun.terms,
            peCourses: peCourses,
            examInfo: examInfo
        )
    }

    // MARK: - Auth

    private func ensureAuthenticated(sidCookies: String) async throws {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }

        var current = URL(string: "\(Self.baseURL)/")!
        for _ in 0..<14 {
            // 保留 service=http://tygl.buct.edu.cn/ 参数不变，仅将直接访问 tygl.buct.edu.cn 的 hop 升级为 HTTPS
            if current.host?.lowercased() == "tygl.buct.edu.cn" && current.scheme?.lowercased() == "http" {
                var comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
                comps?.scheme = "https"
                if let upgraded = comps?.url { current = upgraded }
            }

            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            let resp = try await transport.send(req, cookieJar: jar, timeout: 20)

            if resp.isRedirect, let loc = resp.header("Location"),
               let next = URL(string: loc, relativeTo: current)?.absoluteURL {
                current = next
                continue
            }

            if current.host?.lowercased() == "tygl.buct.edu.cn" {
                let text = resp.decodedText(preferGBKFallback: true)
                if TyglParser.isAuthenticatedPage(text) {
                    return
                }
            }
            break
        }
        throw TyglAuthExpiredError("未能完成体测系统 phpCAS 认证，请重新登录统一身份认证")
    }

    private func getAuthedPage(path: String) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Self.baseURL)\(path)")!)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("\(Self.baseURL)/main.php", forHTTPHeaderField: "Referer")
        let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
        guard resp.statusCode == 200 else {
            throw TyglAuthExpiredError("体测系统响应异常（HTTP \(resp.statusCode)）")
        }
        let text = resp.decodedText(preferGBKFallback: true)
        guard TyglParser.isAuthenticatedPage(text) else {
            throw TyglAuthExpiredError()
        }
        return text
    }
}
