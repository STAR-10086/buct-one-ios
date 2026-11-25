import BuctModel
import BuctNetwork
import Foundation

public actor TheolClient {
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let meolBase = "https://course.buct.edu.cn"
    private static let meolSsoService = "https://course.buct.edu.cn/meol/homepage/common/sso_login.jsp"
    private static let meolWelcomeHome = "https://course.buct.edu.cn/meol/welcomepage/student/index.jsp"
    private static let meolLegacyHomePath = "/meol/homepage/student/index.jsp"
    private static let meolReminderUrl = "https://course.buct.edu.cn/meol/welcomepage/student/interaction_reminder_v8.jsp"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    private static let mobileUA =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/139.0.0.0 Mobile Safari/537.36"
    private static let courseContextTTL: TimeInterval = 120
    private static let maxDownloadBytes: Int64 = 200 * 1024 * 1024

    private let transport: BuctHttpTransport
    private let jar = MatchingMemoryCookieJar()
    private var lastCourseContext: (lid: String, at: Date)?

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func seedCookies(sidCookies: String, meolCookies: String) {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }
        let cleanMeol = meolCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanMeol.isEmpty {
            jar.seed(cookieHeader: cleanMeol, setByHost: "course.buct.edu.cn", path: "/meol")
        }
        lastCourseContext = nil
    }

    public func exportMeolCookies() -> String {
        jar.cookieHeaderFor(url: URL(string: Self.meolWelcomeHome)!)
    }

    /// 预热北化在线会话与课程上下文，并导出可注入 `WKWebView` 的 Cookie 列表，
    /// 使应用内打开作业提交页、测验页与原网页时无需再次登录。
    public func prepareWebSessionCookies(
        sidCookies: String,
        meolCookies: String,
        courseLid: String? = nil,
        touchHomework: Bool = false
    ) async throws -> [TheolWebSessionCookie] {
        seedCookies(sidCookies: sidCookies, meolCookies: meolCookies)
        _ = try await ensureSessionAndGetReminderHtml()
        if let lid = courseLid, !lid.isEmpty {
            try await enterCourseContext(courseLid: lid, force: true, touchHomework: touchHomework)
        }
        var cookies: [HTTPCookie] = []
        cookies.append(contentsOf: jar.loadForRequest(url: URL(string: Self.meolWelcomeHome)!))
        cookies.append(contentsOf: jar.loadForRequest(url: URL(string: "https://\(Self.sidPortalHost)/")!))
        var seen = Set<String>()
        var result: [TheolWebSessionCookie] = []
        for cookie in cookies {
            let key = "\(cookie.name)|\(cookie.domain.lowercased())|\(cookie.path)"
            guard seen.insert(key).inserted else { continue }
            result.append(
                TheolWebSessionCookie(
                    name: cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    isSecure: cookie.isSecure
                )
            )
        }
        return result
    }

    public func fetchPhase1Snapshot(sidCookies: String, meolCookies: String) async throws -> TheolSnapshot {
        seedCookies(sidCookies: sidCookies, meolCookies: meolCookies)
        let reminderHtml = try await ensureSessionAndGetReminderHtml()
        let pending = TheolParser.parsePendingCourses(reminderHtml)

        var homeworks: [TheolHomeworkItem] = []
        var seenHw = Set<String>()
        var failedCount = 0

        for course in pending.homeworks {
            do {
                let items = try await walkHomeworkPages(
                    startURL: course.url,
                    lid: course.lid,
                    courseName: course.courseName,
                    maxPages: 40,
                    followOnlyHomeworkAndPaging: false
                )
                for item in items where seenHw.insert(item.id).inserted {
                    homeworks.append(item)
                }
            } catch let err as TheolAuthExpiredError {
                throw err
            } catch {
                failedCount += 1
            }
        }

        var tests: [TheolTestItem] = []
        var seenTest = Set<String>()
        for course in pending.tests {
            do {
                let items = try await fetchCourseTests(lid: course.lid, courseName: course.courseName)
                for item in items where seenTest.insert(item.id).inserted {
                    tests.append(item)
                }
            } catch let err as TheolAuthExpiredError {
                throw err
            } catch {
                failedCount += 1
            }
        }

        let catalog = (try? await fetchFullLessonCatalog()) ?? pending.homeworks
        return TheolSnapshot(
            homeworks: TheolSorting.sortHomeworks(homeworks),
            tests: TheolSorting.sortTests(tests),
            failedCourseCount: failedCount,
            courses: catalog
        )
    }

    public func fetchFullLessonCatalog() async throws -> [TheolCourseInfo] {
        if let resp = try? await getMeolText(url: URL(string: "\(Self.meolBase)/meol/lesson/blen.student.lesson.list.jsp")!) {
            let list = TheolParser.parseCatalogCourses(resp.text)
            if !list.isEmpty { return list }
        }
        if let active = try? await getMeolText(url: URL(string: "\(Self.meolBase)/meol/welcomepage/student/course_list.jsp")!) {
            let list = TheolParser.parseCatalogCourses(active.text)
            if !list.isEmpty { return list }
        }
        return []
    }

    public func fetchSingleCourseHomeworksFast(lid: String, courseName: String) async throws -> [TheolHomeworkItem] {
        let courseHome = "\(Self.meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
        let resp = try await getMeolText(url: URL(string: courseHome)!)
        var candidates = TheolParser.extractHomeworkColumnUrls(resp.text, baseURL: resp.url)
        if !candidates.contains(TheolParser.meolHomeworkFallback) {
            candidates.append(TheolParser.meolHomeworkFallback)
        }

        var items: [TheolHomeworkItem] = []
        var seen = Set<String>()
        for start in candidates {
            let crawled = try await walkHomeworkPages(
                startURL: start,
                lid: lid,
                courseName: courseName,
                maxPages: 8,
                followOnlyHomeworkAndPaging: true
            )
            for hw in crawled where seen.insert(hw.id).inserted {
                items.append(hw)
            }
        }
        return items
    }

    public func fetchCourseTests(lid: String, courseName: String) async throws -> [TheolTestItem] {
        let listURL = TheolParser.buildTestListUrl(lid: lid)
        let resp = try await getMeolText(
            url: URL(string: listURL)!,
            referer: "\(Self.meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
        )
        return TheolParser.parseTestList(resp.text, lid: lid, courseName: courseName, listURL: listURL)
    }

    public func fetchHomeworkDetail(item: TheolHomeworkItem) async throws -> TheolHomeworkDetail {
        try await enterCourseContext(courseLid: item.lid, touchHomework: true)
        let target = item.detailHref.isEmpty
            ? "\(Self.meolBase)/meol/common/hw/student/hwtask.view.jsp?hwtid=\(item.hwtid)"
            : item.detailHref
        let resp = try await getMeolText(
            url: URL(string: target)!,
            referer: TheolParser.meolHomeworkFallback
        )
        return TheolParser.parseHomeworkDetail(resp.text, fallback: item, baseURL: resp.url)
    }

    public func fetchTestDetail(item: TheolTestItem) async throws -> TheolTestDetail {
        guard !item.testId.isEmpty, item.testId.allSatisfy(\.isNumber) else {
            return TheolTestDetail(
                testId: item.testId,
                title: item.title,
                description: "",
                startTime: item.startTime,
                endTime: item.endTime,
                duration: item.duration,
                totalScore: "",
                questionCount: "",
                fetchedAt: Int64(Date().timeIntervalSince1970 * 1000)
            )
        }
        try await enterCourseContext(courseLid: item.lid, touchHomework: false)
        let url = URL(string: "\(Self.meolBase)/meol/common/question/test/student/view.jsp?testId=\(item.testId)")!
        let resp = try await getMeolText(url: url, referer: TheolParser.buildTestListUrl(lid: item.lid))
        return TheolParser.parseTestDetail(resp.text, fallback: item)
    }

    public func fetchCourseUnits(lid: String) async throws -> [TheolCourseUnit] {
        let home = URL(string: "\(Self.meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)")!
        let resp = try await getMeolText(url: home)
        lastCourseContext = (lid, Date())
        return TheolParser.parseCourseUnits(resp.text, baseURL: resp.url)
    }

    public func fetchCourseResources(lid: String, courseName: String, folderUrl: String? = nil) async throws -> TheolResourcePage {
        try await enterCourseContext(courseLid: lid, touchHomework: false)
        let courseHome = "\(Self.meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
        let targetUrl = folderUrl ?? "\(Self.meolBase)/meol/common/script/listview.jsp?groupid=4&lid=\(lid)&folderid=0"
        let resp = try await fetchResourcePageWithUnwrap(url: URL(string: targetUrl)!, referer: courseHome)
        let items = TheolParser.parseResourceList(resp.text, lid: lid, baseURL: resp.url)
        return TheolResourcePage(
            lid: lid,
            courseName: courseName,
            currentUrl: resp.url.absoluteString,
            folderTitle: folderUrl == nil ? "课程资源" : "子目录",
            items: items
        )
    }

    public func fetchUnitResources(lid: String, courseName: String, unit: TheolCourseUnit) async throws -> TheolResourcePage {
        try await enterCourseContext(courseLid: lid, touchHomework: false)
        let courseHome = "\(Self.meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
        let resp = try await fetchResourcePageWithUnwrap(url: URL(string: unit.url)!, referer: courseHome)
        let items = TheolParser.parseResourceList(resp.text, lid: lid, baseURL: resp.url)
        return TheolResourcePage(
            lid: lid,
            courseName: courseName,
            currentUrl: resp.url.absoluteString,
            folderTitle: unit.title,
            items: items
        )
    }

    public func downloadFile(
        urlString: String,
        courseLid: String,
        referer: String,
        cacheDirectory: URL
    ) async throws -> TheolDownloadedFile {
        guard let initialURL = URL(string: urlString),
              let host = initialURL.host?.lowercased(),
              host.hasSuffix(".buct.edu.cn") || host == "buct.edu.cn" else {
            throw NSError(domain: "TheolClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "不支持的下载链接域名"])
        }

        let effectiveReferer = referer.isEmpty
            ? "\(Self.meolBase)/meol/common/script/listview.jsp?groupid=4&lid=\(courseLid)&folderid=0"
            : referer

        if effectiveReferer.contains("download_preview.jsp"), let refURL = URL(string: effectiveReferer) {
            try? await enterCourseContext(courseLid: courseLid, force: false, touchHomework: false)
            _ = try? await getMeolText(url: refURL, referer: Self.meolWelcomeHome)
        }

        return try await executeDownload(
            url: initialURL,
            referer: effectiveReferer,
            cacheDirectory: cacheDirectory,
            allowHtmlDirectRetry: true
        )
    }

    private func executeDownload(
        url: URL,
        referer: String,
        cacheDirectory: URL,
        allowHtmlDirectRetry: Bool
    ) async throws -> TheolDownloadedFile {
        var current = url
        var resp: HttpResponseData?

        for _ in 0..<6 {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            req.setValue(referer, forHTTPHeaderField: "Referer")
            let r = try await transport.send(req, cookieJar: jar, timeout: 90)
            if r.isRedirect {
                guard let loc = r.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    break
                }
                let nextHost = next.host?.lowercased() ?? ""
                if nextHost == Self.sidPortalHost || nextHost == "portal.buct.edu.cn" {
                    throw TheolAuthExpiredError()
                }
                current = next
                continue
            }
            resp = r
            break
        }

        guard let finalResp = resp else {
            throw NSError(domain: "TheolClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "下载重定向异常"])
        }
        if [401, 403].contains(finalResp.statusCode) {
            throw TheolAuthExpiredError()
        }
        guard finalResp.isSuccessful else {
            throw NSError(domain: "TheolClient", code: finalResp.statusCode, userInfo: [NSLocalizedDescriptionKey: "下载失败（HTTP \(finalResp.statusCode)）"])
        }
        if Int64(finalResp.body.count) > Self.maxDownloadBytes {
            throw NSError(domain: "TheolClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "附件超过 200MB 限制"])
        }

        let cd = finalResp.header("Content-Disposition")
        let ct = (finalResp.header("Content-Type") ?? "").lowercased()
        let looksHtml = ct.contains("text/html") || (cd == nil && looksLikeHtmlData(finalResp.body))

        if looksHtml {
            let text = finalResp.decodedText(preferGBKFallback: true)
            if TheolParser.isPermissionDeniedOrExpired(text) {
                throw TheolAuthExpiredError()
            }
            if allowHtmlDirectRetry,
               let directStr = TheolParser.extractDirectDownloadUrl(text, baseURL: finalResp.url),
               let directURL = URL(string: directStr) {
                return try await executeDownload(
                    url: directURL,
                    referer: finalResp.url.absoluteString,
                    cacheDirectory: cacheDirectory,
                    allowHtmlDirectRetry: false
                )
            }
            return TheolDownloadedFile(
                filePath: "",
                fileName: TheolParser.recoverHeaderFilename(contentDisposition: cd, fallbackURL: url),
                mimeType: "text/html",
                sizeBytes: Int64(finalResp.body.count),
                isHtmlPage: true
            )
        }

        let fileName = sanitizeFilename(TheolParser.recoverHeaderFilename(contentDisposition: cd, fallbackURL: url))
        let hashDir = String(BuctCrypto.sha256Hex(url.absoluteString).prefix(12))
        let targetDir = cacheDirectory.appendingPathComponent(hashDir, isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let targetFile = targetDir.appendingPathComponent(fileName)
        try finalResp.body.write(to: targetFile, options: [.atomic])

        return TheolDownloadedFile(
            filePath: targetFile.path,
            fileName: fileName,
            mimeType: ct.isEmpty ? "application/octet-stream" : ct,
            sizeBytes: Int64(finalResp.body.count),
            isHtmlPage: false
        )
    }

    private func ensureSessionAndGetReminderHtml() async throws -> String {
        if let html = try? await probeReminderHtml() {
            return html
        }
        try await exchangeSsoTicket()
        if let html = try? await probeReminderHtml() {
            return html
        }
        throw TheolAuthExpiredError()
    }

    private func probeReminderHtml() async throws -> String {
        var req = URLRequest(url: URL(string: Self.meolReminderUrl)!)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.meolWelcomeHome, forHTTPHeaderField: "Referer")
        let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
        guard resp.statusCode == 200,
              resp.url.host?.lowercased() == "course.buct.edu.cn" else {
            throw TheolAuthExpiredError()
        }
        let text = resp.decodedText(preferGBKFallback: true)
        if TheolParser.isPermissionDeniedOrExpired(text) {
            throw TheolAuthExpiredError()
        }
        return text
    }

    private func exchangeSsoTicket() async throws {
        var current = URL(string: Self.meolSsoService)!
        for _ in 0..<10 {
            if current.host?.lowercased() == "course.buct.edu.cn" {
                if current.scheme?.lowercased() == "http" {
                    var comps = URLComponents(url: current, resolvingAgainstBaseURL: false)
                    comps?.scheme = "https"
                    if let upgraded = comps?.url { current = upgraded }
                }
                if current.path == Self.meolLegacyHomePath {
                    current = URL(string: Self.meolWelcomeHome)!
                }
            }

            let host = current.host?.lowercased() ?? ""
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            let ua = (host == Self.sidPortalHost || host == "portal.buct.edu.cn") ? Self.mobileUA : Self.desktopUA
            req.setValue(ua, forHTTPHeaderField: "User-Agent")

            let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
            if resp.isRedirect {
                guard resp.statusCode != 307 && resp.statusCode != 308,
                      let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    break
                }
                let nextHost = next.host?.lowercased() ?? ""
                guard ["course.buct.edu.cn", Self.sidPortalHost, "portal.buct.edu.cn"].contains(nextHost) else {
                    break
                }
                current = next
                continue
            }

            if host == "course.buct.edu.cn" && current.path.hasPrefix("/meol/") && !current.path.contains("login") {
                let text = resp.decodedText(preferGBKFallback: true)
                if !TheolParser.isPermissionDeniedOrExpired(text) {
                    return
                }
            }
            break
        }
        throw TheolAuthExpiredError()
    }

    private func enterCourseContext(courseLid: String, force: Bool = false, touchHomework: Bool) async throws {
        guard !courseLid.isEmpty else { return }
        if !force, let last = lastCourseContext, last.lid == courseLid, Date().timeIntervalSince(last.at) < Self.courseContextTTL {
            return
        }
        let homeURL = URL(string: "\(Self.meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(courseLid)")!
        _ = try await getMeolText(url: homeURL, referer: Self.meolWelcomeHome)
        if touchHomework {
            _ = try? await getMeolText(url: URL(string: TheolParser.meolHomeworkFallback)!, referer: homeURL.absoluteString)
        }
        lastCourseContext = (courseLid, Date())
    }

    private func walkHomeworkPages(
        startURL: String,
        lid: String,
        courseName: String,
        maxPages: Int,
        followOnlyHomeworkAndPaging: Bool
    ) async throws -> [TheolHomeworkItem] {
        var queue = [startURL]
        var visited = Set<String>()
        var seenTableFingerprints = Set<String>()
        var allItems: [TheolHomeworkItem] = []
        var seenHwIds = Set<String>()
        var pageCount = 0

        while !queue.isEmpty && pageCount < maxPages {
            let currentStr = queue.removeFirst()
            guard let url = URL(string: currentStr),
                  isAllowedHomeworkURL(url),
                  visited.insert(currentStr).inserted else {
                continue
            }
            pageCount += 1

            let resp = try await getMeolText(url: url, referer: Self.meolWelcomeHome)
            let parsed = TheolParser.parseHomeworkPage(resp.text, lid: lid, courseName: courseName, baseURL: resp.url)
            for item in parsed.items where seenHwIds.insert(item.id).inserted {
                allItems.append(item)
            }

            if !parsed.tableFingerprint.isEmpty && !seenTableFingerprints.insert(parsed.tableFingerprint).inserted {
                continue
            }

            if let nextPage = parsed.nextPageURL, !visited.contains(nextPage) {
                queue.append(nextPage)
            }

            if !followOnlyHomeworkAndPaging,
               let redirectTarget = TheolParser.extractResourceRedirectUrl(resp.text, baseURL: resp.url),
               !visited.contains(redirectTarget) {
                queue.append(redirectTarget)
            }
        }
        return allItems
    }

    private func fetchResourcePageWithUnwrap(url: URL, referer: String) async throws -> (url: URL, text: String) {
        var current = url
        var lastResp = try await getMeolText(url: current, referer: referer)
        for _ in 0..<3 {
            let parsed = TheolParser.parseResourceList(lastResp.text, lid: "", baseURL: lastResp.url)
            if !parsed.isEmpty {
                return lastResp
            }
            guard let nextStr = TheolParser.extractResourceRedirectUrl(lastResp.text, baseURL: lastResp.url),
                  let nextURL = URL(string: nextStr),
                  nextURL != current else {
                break
            }
            current = nextURL
            lastResp = try await getMeolText(url: current, referer: lastResp.url.absoluteString)
        }
        return lastResp
    }

    private func getMeolText(url: URL, referer: String = meolWelcomeHome) async throws -> (url: URL, text: String) {
        var current = url
        for _ in 0..<6 {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            req.setValue(referer, forHTTPHeaderField: "Referer")
            let resp = try await transport.send(req, cookieJar: jar, timeout: 25)
            if resp.isRedirect {
                guard let loc = resp.header("Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL else {
                    break
                }
                let nextHost = next.host?.lowercased() ?? ""
                if nextHost == Self.sidPortalHost || nextHost == "portal.buct.edu.cn" {
                    throw TheolAuthExpiredError()
                }
                if nextHost == "course.buct.edu.cn" {
                    current = next
                    continue
                }
                throw TheolAuthExpiredError()
            }
            if [401, 403].contains(resp.statusCode) {
                throw TheolAuthExpiredError()
            }
            let text = resp.decodedText(preferGBKFallback: true)
            if TheolParser.isPermissionDeniedOrExpired(text) {
                throw TheolAuthExpiredError()
            }
            return (resp.url, text)
        }
        throw TheolAuthExpiredError()
    }

    private func isAllowedHomeworkURL(_ url: URL) -> Bool {
        guard url.host?.lowercased() == "course.buct.edu.cn" else { return false }
        let allowedPaths: Set<String> = [
            "/meol/jpk/course/layout/newpage/index.jsp",
            "/meol/jpk/course/course_column_preview_transfer.jsp",
            "/meol/buildless/colUrlStuView.do",
            "/meol/common/hw/student/hwtask.jsp",
            "/meol/common/hw/student/hwtask_blended.jsp"
        ]
        return allowedPaths.contains(url.path)
    }

    private func looksLikeHtmlData(_ data: Data) -> Bool {
        let head = String(data: Data(data.prefix(2048)), encoding: .isoLatin1)?.lowercased() ?? ""
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html") || trimmed.contains("<script")
    }

    private func sanitizeFilename(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: #"[/\\:*?"<>|]"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "attachment.bin" : cleaned
    }
}
