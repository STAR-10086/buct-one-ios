import BuctModel
import BuctNetwork
import Foundation

public actor PortalCalendarClient {
    private static let portalBase = "https://i.buct.edu.cn"
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let portalParamP = "YXM9MiZ0PTYmZD0xMTYmcD0xJmY9MzAmbT1OJg__"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    private static let mobileUA =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/139.0.0.0 Mobile Safari/537.36"

    private let webVpn: BuctWebVpnManager
    private let jar = MatchingMemoryCookieJar()
    private var authenticated = false

    public init(webVpn: BuctWebVpnManager = .shared) {
        self.webVpn = webVpn
    }

    public func fetchOfficialCalendar(sidCookies: String) async throws -> OfficialCalendarSnapshot {
        if !authenticated {
            try await authenticateWithSso(sidCookies: sidCookies)
        }

        let todayStr = Self.beijingTodayString()
        let jxzURL = URL(string: "\(Self.portalBase)/_web/fusionportal/getJxz.jsp?currentDate=\(todayStr)&_p=\(Self.portalParamP)")!
        let jxzResp = try await fetchAuthenticatedGet(url: jxzURL, sidCookies: sidCookies)
        let baseSnapshot = try PortalCalendarParser.parseJxzResponse(jxzResp.bodyString)

        var holidays: [CalendarHoliday] = []
        if baseSnapshot.beginDate.count == 10 && baseSnapshot.endDate.count == 10 {
            let listURL = URL(
                string: "\(Self.portalBase)/calendar/mgr/api/ids/list.rst?queryType=2&categoryIds=-2&fromDate=\(baseSnapshot.beginDate)T00:00:00.000Z&endDate=\(baseSnapshot.endDate)T00:00:00.000Z&type=0&_p=\(Self.portalParamP)"
            )!
            if let listResp = try? await fetchAuthenticatedGet(url: listURL, sidCookies: sidCookies) {
                holidays = PortalCalendarParser.parseCalendarDays(listResp.bodyString)
            }
        }

        return OfficialCalendarSnapshot(
            currentTermId: baseSnapshot.currentTermId,
            beginDate: baseSnapshot.beginDate,
            endDate: baseSnapshot.endDate,
            currentTeachingWeek: baseSnapshot.currentTeachingWeek,
            terms: baseSnapshot.terms,
            holidays: holidays
        )
    }

    public func fetchBorrowedBooks(page: Int = 1, rows: Int = 50, sidCookies: String) async throws -> PortalLibrarySnapshot {
        if !authenticated {
            try await authenticateWithSso(sidCookies: sidCookies)
        }
        let url = URL(string: "\(Self.portalBase)/_web/fusionportal/getYktOrBook.jsp?page=\(page)&rows=\(rows)&type=book&_p=\(Self.portalParamP)")!
        let resp = try await fetchAuthenticatedGet(url: url, sidCookies: sidCookies)
        return try PortalCalendarParser.parseBorrowedBooks(resp.bodyString)
    }

    public func fetchNewsColumn(
        column: PortalNewsColumn,
        beginIndex: Int = 0,
        pageSize: Int = 15,
        sidCookies: String
    ) async throws -> PortalNewsColumnPage {
        seedSidCookiesIfNeeded(sidCookies: sidCookies)
        let url = URL(
            string: "https://mnews.buct.edu.cn/mobile/getPortalArticleList16ByUser.rst?siteId=100000251&columnId=\(column.rawValue)&pageSize=\(pageSize)&beginIndex=\(beginIndex)&scope=0"
        )!
        let resp = try await fetchMnewsGet(url: url)
        return try PortalCalendarParser.parseNewsArticlesPage(resp.bodyString, columnId: column.rawValue)
    }

    public func fetchAllNewsSnapshot(sidCookies: String) async throws -> PortalNewsSnapshot {
        seedSidCookiesIfNeeded(sidCookies: sidCookies)
        var columns: [String: PortalNewsColumnPage] = [:]
        var firstError: Error?

        for column in PortalNewsColumn.allCases {
            do {
                let page = try await fetchNewsColumn(column: column, beginIndex: 0, pageSize: 15, sidCookies: sidCookies)
                columns[column.rawValue] = page
            } catch let err as BuctWebVpnAuthRequiredError {
                throw err
            } catch {
                if (error as NSError).code == 401 {
                    throw error
                }
                if firstError == nil { firstError = error }
            }
        }

        if columns.isEmpty {
            throw firstError ?? NSError(domain: "PortalCalendarClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "获取校内资讯失败"])
        }
        return PortalNewsSnapshot(columns: columns)
    }

    private func seedSidCookiesIfNeeded(sidCookies: String) {
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }
    }

    private func fetchMnewsGet(url: URL) async throws -> HttpResponseData {
        var current = url
        for _ in 0..<14 {
            let host = current.host?.lowercased() ?? ""
            if (host == "i.buct.edu.cn" || host == "mnews.buct.edu.cn") && current.scheme?.lowercased() == "http" {
                var comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
                comps?.scheme = "https"
                if let upgraded = comps?.url { current = upgraded }
            }

            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            let ua = (host == Self.sidPortalHost || host == "portal.buct.edu.cn") ? Self.mobileUA : Self.desktopUA
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
            req.setValue("\(Self.portalBase)/_s2/students_sy/main.psp", forHTTPHeaderField: "Referer")

            let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 25)
            if resp.isRedirect {
                guard let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    break
                }
                let nextHost = next.host?.lowercased() ?? ""
                guard ["i.buct.edu.cn", "mnews.buct.edu.cn", "portal.buct.edu.cn", Self.sidPortalHost].contains(nextHost) else {
                    throw NSError(domain: "PortalCalendarClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "校内资讯统一认证会话已过期，请重新登录"])
                }
                current = next
                continue
            }

            let body = resp.bodyString
            if [401, 403].contains(resp.statusCode) || host == Self.sidPortalHost ||
                body.contains("login-page-flowkey") || body.contains("统一身份认证") {
                throw NSError(domain: "PortalCalendarClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "校内资讯统一认证会话已过期，请重新登录"])
            }
            return resp
        }
        throw NSError(domain: "PortalCalendarClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "校内资讯统一认证会话已过期，请重新登录"])
    }

    private func fetchAuthenticatedGet(url: URL, sidCookies: String) async throws -> HttpResponseData {
        let resp = try await performPortalGet(url: url)
        let body = resp.bodyString
        if resp.isRedirect || [401, 403].contains(resp.statusCode) ||
            body.contains("login-page-flowkey") || body.contains("统一身份认证") {
            authenticated = false
            try await authenticateWithSso(sidCookies: sidCookies)
            return try await performPortalGet(url: url)
        }
        return resp
    }

    private func performPortalGet(url: URL) async throws -> HttpResponseData {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("\(Self.portalBase)/_s2/students_sy/main.psp", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return try await webVpn.execute(req, cookieJar: jar, timeout: 25)
    }

    private func authenticateWithSso(sidCookies: String) async throws {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }

        var current = URL(string: "\(Self.portalBase)/")!
        for _ in 0..<14 {
            let host = current.host?.lowercased() ?? ""
            if (host == "i.buct.edu.cn" || host == "mnews.buct.edu.cn") && current.scheme?.lowercased() == "http" {
                var comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
                comps?.scheme = "https"
                if let upgraded = comps?.url { current = upgraded }
            }

            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            let ua = (host == Self.sidPortalHost || host == "portal.buct.edu.cn") ? Self.mobileUA : Self.desktopUA
            req.setValue(ua, forHTTPHeaderField: "User-Agent")

            let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 25)
            if resp.isRedirect {
                guard let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    break
                }
                let nextHost = next.host?.lowercased() ?? ""
                guard ["i.buct.edu.cn", "mnews.buct.edu.cn", "portal.buct.edu.cn", Self.sidPortalHost].contains(nextHost) else {
                    break
                }
                current = next
                continue
            }

            let html = resp.bodyString
            if isPortalAuthenticatedHtml(html) {
                authenticated = true
                return
            }
            if html.contains("login-page-flowkey") {
                throw NSError(domain: "PortalCalendarClient", code: 401, userInfo: [NSLocalizedDescriptionKey: "i北化单点登录会话已过期，请重新登录"])
            }
            break
        }
        throw NSError(domain: "PortalCalendarClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法进入 i北化门户"])
    }

    private func isPortalAuthenticatedHtml(_ html: String) -> Bool {
        if html.contains("login-page-flowkey") || html.contains("login-croypto") {
            return false
        }
        return html.contains("fusionportal") ||
            html.contains("students_sy") ||
            html.contains("i北化") ||
            html.contains("_web/portal")
    }

    private static func beijingTodayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
