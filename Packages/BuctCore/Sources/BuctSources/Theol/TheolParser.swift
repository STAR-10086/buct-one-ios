import BuctModel
import BuctNetwork
import Foundation
import SwiftSoup

public struct TheolAuthExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "北化在线登录会话已过期，请重新登录") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum TheolParser {
    public static let parserVersion = 7
    public static let meolBase = "https://course.buct.edu.cn"
    public static let meolHomeworkFallback = "https://course.buct.edu.cn/meol/common/hw/student/hwtask.jsp?tagbug=client&strStyle=new03"

    public static func isPermissionDeniedOrExpired(_ html: String) -> Bool {
        let lower = html.lowercased()
        if lower.contains("permission denied") || lower.contains("type=\"password\"") {
            return true
        }
        return html.contains("登录时间超时") ||
            html.contains("请重新登录") ||
            html.contains("用户身份错误") ||
            html.contains("您尚未登录") ||
            html.contains("只有注册用户才可以提交错误报告") ||
            html.contains("login-page-flowkey")
    }

    public static func parsePendingCourses(_ html: String) -> (homeworks: [TheolCourseInfo], tests: [TheolCourseInfo]) {
        guard let doc = try? SwiftSoup.parse(html, meolBase),
              let links = try? doc.select("a[onclick]") else {
            return ([], [])
        }
        var hwCourses: [TheolCourseInfo] = []
        var testCourses: [TheolCourseInfo] = []
        var seenHw = Set<String>()
        var seenTest = Set<String>()

        for link in links {
            let onclick = (try? link.attr("onclick")) ?? ""
            let text = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !(text.contains("门课程") && text.contains("待提交")) else { continue }
            guard let lid = extractLid(fromOnclick: onclick), !lid.isEmpty else { continue }

            if onclick.contains("&t=hw") {
                if seenHw.insert(lid).inserted {
                    hwCourses.append(
                        TheolCourseInfo(
                            lid: lid,
                            courseName: text,
                            type: "homework",
                            url: "\(meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
                        )
                    )
                }
            } else if onclick.contains("&t=test") {
                if lid == "24199" || lid == "27215" { continue }
                if seenTest.insert(lid).inserted {
                    testCourses.append(
                        TheolCourseInfo(
                            lid: lid,
                            courseName: text,
                            type: "test",
                            url: buildTestListUrl(lid: lid)
                        )
                    )
                }
            }
        }
        return (hwCourses, testCourses)
    }

    public static func parseCatalogCourses(_ html: String) -> [TheolCourseInfo] {
        guard let doc = try? SwiftSoup.parse(html, meolBase) else { return [] }
        var result: [TheolCourseInfo] = []
        var seen = Set<String>()

        if let links = try? doc.select("a[href]") {
            for a in links {
                let abs = (try? a.absUrl("href")) ?? ""
                guard let url = URL(string: abs) else { continue }
                let path = url.path.lowercased()
                let isCoursePath = path == "/meol/jpk/course/layout/newpage/index.jsp" ||
                    path.hasSuffix("/lesson/init_course.jsp") ||
                    path.hasSuffix("/homepage/course/course_index.jsp")
                guard isCoursePath else { continue }

                let lid = queryParam("courseId", in: url) ?? queryParam("lid", in: url) ?? ""
                guard !lid.isEmpty, lid.allSatisfy(\.isNumber), seen.insert(lid).inserted else { continue }
                let name = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                result.append(
                    TheolCourseInfo(
                        lid: lid,
                        courseName: name,
                        type: "course",
                        url: "\(meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
                    )
                )
            }
        }

        if let onclickLinks = try? doc.select("a[onclick]") {
            for a in onclickLinks {
                let onclick = (try? a.attr("onclick")) ?? ""
                guard onclick.contains("courseId=") || onclick.contains("lid=") else { continue }
                guard let lid = regexFirstCapture(onclick, pattern: #"(?:courseId|lid)\s*=\s*(\d+)"#),
                      seen.insert(lid).inserted else { continue }
                let name = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                result.append(
                    TheolCourseInfo(
                        lid: lid,
                        courseName: name,
                        type: "course",
                        url: "\(meolBase)/meol/jpk/course/layout/newpage/index.jsp?courseId=\(lid)"
                    )
                )
            }
        }
        return result
    }

    public static func extractHomeworkColumnUrls(_ html: String, baseURL: URL) -> [String] {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString),
              let links = try? doc.select("a[href]") else {
            return []
        }
        var urls: [String] = []
        var seen = Set<String>()
        for a in links {
            let text = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let href = (try? a.absUrl("href")) ?? ""
            guard !href.isEmpty else { continue }
            if (text.contains("作业") && !text.contains("测试")) || href.lowercased().contains("hwtask") {
                if seen.insert(href).inserted {
                    urls.append(href)
                    if urls.count >= 3 { break }
                }
            }
        }
        return urls
    }

    public static func parseHomeworkPage(
        _ html: String,
        lid: String,
        courseName: String,
        baseURL: URL,
        nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> (items: [TheolHomeworkItem], tableFingerprint: String, dataRowCount: Int, nextPageURL: String?) {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString),
              let tables = try? doc.select("table.valuelist") else {
            return ([], "", 0, nil)
        }

        var items: [TheolHomeworkItem] = []
        var seenHwtid = Set<String>()
        var dataRowCount = 0

        for table in tables {
            let rows = (try? table.select("tr")) ?? Elements()
            let isVertical = rows.contains { tr in
                let ths = (try? tr.select("> th")) ?? Elements()
                let tds = (try? tr.select("> td")) ?? Elements()
                let thText = ((try? ths.first()?.text()) ?? "")
                return ths.size() == 1 && tds.size() == 1 && thText.contains("标题")
            }

            if isVertical {
                var title = ""
                var hwtid = ""
                var detailHref = ""
                var deadline = ""
                var score = ""
                var publisher = ""
                var submitHref = ""
                var resultHref = ""
                var isGroup = false

                for tr in rows {
                    let th = ((try? tr.select("> th").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let td = try? tr.select("> td").first() else { continue }
                    if th.contains("标题") {
                        title = ((try? td.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if let a = try? td.select("a[href]").first() {
                            detailHref = (try? a.absUrl("href")) ?? ""
                            if let url = URL(string: detailHref), let id = queryParam("hwtid", in: url) {
                                hwtid = id
                            }
                        }
                        isGroup = ((try? td.select("img[title=分组作业]").isEmpty()) == false)
                    } else if th.contains("截止") {
                        deadline = ((try? td.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if th.contains("评分") || th.contains("分数") {
                        score = ((try? td.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if th.contains("发布人") {
                        publisher = ((try? td.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if th.contains("提交作业") {
                        if let a = try? td.select("a[href]").first(), !isDisabledLink(a) {
                            submitHref = (try? a.absUrl("href")) ?? ""
                        }
                    } else if th.contains("查看结果") {
                        if let a = try? td.select("a[href]").first(), !isDisabledLink(a) {
                            resultHref = (try? a.absUrl("href")) ?? ""
                        }
                    }
                }
                if !title.isEmpty && !hwtid.isEmpty && seenHwtid.insert(hwtid).inserted {
                    dataRowCount += 1
                    items.append(
                        finalizeHomework(
                            hwtid: hwtid,
                            lid: lid,
                            courseName: courseName,
                            title: title,
                            deadline: deadline,
                            score: score,
                            publisher: publisher,
                            isGroup: isGroup,
                            detailHref: detailHref.isEmpty ? "\(meolBase)/meol/common/hw/student/hwtask.view.jsp?hwtid=\(hwtid)" : detailHref,
                            submitHref: submitHref,
                            resultHref: resultHref,
                            nowMillis: nowMillis
                        )
                    )
                }
            } else {
                for tr in rows {
                    let tds = (try? tr.select("> td")) ?? Elements()
                    guard tds.size() >= 4 else { continue }
                    guard let link = try? tds.get(0).select("a[href]").first() else { continue }
                    let detailHref = (try? link.absUrl("href")) ?? ""
                    guard let url = URL(string: detailHref),
                          let hwtid = queryParam("hwtid", in: url),
                          !hwtid.isEmpty, hwtid.allSatisfy(\.isNumber) else {
                        continue
                    }
                    let title = ((try? link.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, seenHwtid.insert(hwtid).inserted else { continue }
                    dataRowCount += 1

                    let deadline = ((try? tds.get(1).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let score = ((try? tds.get(2).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let publisher = ((try? tds.get(3).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let isGroup = ((try? tr.select("img[title=分组作业]").isEmpty()) == false)
                    var submitHref = ""
                    if let enter = try? tr.select("a.enter[href]").first(), !isDisabledLink(enter) {
                        submitHref = (try? enter.absUrl("href")) ?? ""
                    }
                    var resultHref = ""
                    if let view = try? tr.select("a.view[href]").first(), !isDisabledLink(view) {
                        resultHref = (try? view.absUrl("href")) ?? ""
                    }

                    items.append(
                        finalizeHomework(
                            hwtid: hwtid,
                            lid: lid,
                            courseName: courseName,
                            title: title,
                            deadline: deadline,
                            score: score,
                            publisher: publisher,
                            isGroup: isGroup,
                            detailHref: detailHref,
                            submitHref: submitHref,
                            resultHref: resultHref,
                            nowMillis: nowMillis
                        )
                    )
                }
            }
        }

        let tableHtml = (try? tables.first()?.html()) ?? ""
        let baseWithoutPaging = removingPagingPage(from: baseURL)
        let fingerprint = BuctCrypto.sha256Hex("\(baseWithoutPaging)\u{0000}\(tableHtml)")

        var nextPageURL: String?
        if let per = Int(queryParam("pagingNumberPer", in: baseURL) ?? ""), dataRowCount >= per {
            let current = Int(queryParam("pagingPage", in: baseURL) ?? "1") ?? 1
            nextPageURL = settingQueryParam(name: "pagingPage", value: "\(current + 1)", in: baseURL)
        }

        return (items, fingerprint, dataRowCount, nextPageURL)
    }

    private static func finalizeHomework(
        hwtid: String,
        lid: String,
        courseName: String,
        title: String,
        deadline: String,
        score: String,
        publisher: String,
        isGroup: Bool,
        detailHref: String,
        submitHref: String,
        resultHref: String,
        nowMillis: Int64
    ) -> TheolHomeworkItem {
        let deadlineMillis = parseDeadlineMillis(deadline)
        let completed = !resultHref.isEmpty ||
            (!score.isEmpty && !["暂无分数", "未评分", "暂无成绩"].contains(score))
        let isUnlimited = deadline.isEmpty || ["不限", "无限制", "无截止时间"].contains(deadline)
        let isOpen = isUnlimited || (deadlineMillis.map { $0 > nowMillis } ?? false)
        let canSubmit = !submitHref.isEmpty && !completed && isOpen

        let status: String
        if completed {
            status = "已完成"
        } else if !isUnlimited && deadlineMillis == nil {
            status = "截止时间未知"
        } else if !isOpen {
            status = "已截止"
        } else if canSubmit {
            status = "未提交"
        } else {
            status = "不可提交"
        }

        return TheolHomeworkItem(
            hwtid: hwtid,
            lid: lid,
            courseName: courseName,
            title: title,
            deadline: deadline,
            deadlineMillis: deadlineMillis,
            score: score,
            publisher: publisher,
            canSubmit: canSubmit,
            hasResult: completed,
            isGroup: isGroup,
            status: status,
            detailHref: detailHref,
            submitHref: submitHref,
            resultHref: resultHref
        )
    }

    public static func parseHomeworkDetail(
        _ html: String,
        fallback: TheolHomeworkItem,
        baseURL: URL
    ) -> TheolHomeworkDetail {
        let doc = (try? SwiftSoup.parse(html, baseURL.absoluteString)) ?? Document(baseURL.absoluteString)
        var title = fallback.title
        var deadline = fallback.deadline
        var score = fallback.score
        var publisher = fallback.publisher

        if let rows = try? doc.select("table.infotable tr, table.valuelist tr") {
            for tr in rows {
                let th = ((try? tr.select("> th").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let td = ((try? tr.select("> td").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !th.isEmpty, !td.isEmpty else { continue }
                if th.contains("标题") { title = td }
                else if th.contains("截止") { deadline = td }
                else if th.contains("评分") || th.contains("分数") { score = td }
                else if th.contains("发布人") { publisher = td }
            }
        }
        if title.isEmpty, let heading = try? doc.select("h1, h2, h3, .title").first()?.text() {
            let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { title = trimmed }
        }

        var contentText = ""
        var attachments: [TheolHomeworkAttachment] = []
        var seenURLs = Set<String>()

        if let hiddenInputs = try? doc.select("input[type=hidden]") {
            for input in hiddenInputs {
                let name = ((try? input.attr("name")) ?? "").lowercased()
                guard name.contains("content") else { continue }
                let rawVal = (try? input.attr("value")) ?? ""
                let unescaped = (try? Entities.unescape(rawVal)) ?? rawVal
                if let frag = try? SwiftSoup.parseBodyFragment(unescaped, baseURL.absoluteString) {
                    if let bodyLinks = try? frag.select("a[href]") {
                        for a in bodyLinks {
                            let abs = (try? a.absUrl("href")) ?? ""
                            let linkText = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                            if !abs.isEmpty, seenURLs.insert(abs).inserted {
                                attachments.append(TheolHomeworkAttachment(name: linkText.isEmpty ? "附件" : linkText, url: abs))
                            }
                        }
                    }
                    let extracted = ((try? frag.body()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extracted.isEmpty {
                        contentText = extracted
                        break
                    }
                }
            }
        }

        if contentText.isEmpty,
           let fallbackBody = try? doc.select("div.content, div.description, div#body, td.text, table.infotable td.text").first()?.text() {
            contentText = fallbackBody.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let allLinks = try? doc.select("a[href]") {
            for a in allLinks {
                let abs = (try? a.absUrl("href")) ?? ""
                let lower = abs.lowercased()
                if lower.contains("download") || lower.contains("attach") || lower.contains("common/script/") ||
                    lower.contains("upload") || lower.contains("file=") || lower.contains("preview") {
                    if seenURLs.insert(abs).inserted {
                        let name = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        attachments.append(TheolHomeworkAttachment(name: name.isEmpty ? "附件" : name, url: abs))
                    }
                }
            }
        }

        return TheolHomeworkDetail(
            hwtid: fallback.hwtid,
            title: title,
            deadline: deadline,
            score: score,
            publisher: publisher,
            contentText: contentText,
            attachments: attachments
        )
    }

    public static func parseTestList(_ html: String, lid: String, courseName: String, listURL: String) -> [TheolTestItem] {
        guard let doc = try? SwiftSoup.parse(html, meolBase) else { return [] }
        let table = (try? doc.select("table.valuelist").first())
            ?? (try? doc.select("table[border=0][cellspacing=0][cellpadding=0]").first())
        guard let rows = try? table?.select("tr"), rows.size() > 1 else { return [] }

        var result: [TheolTestItem] = []
        for idx in 1..<rows.size() {
            let tds = (try? rows.get(idx).select("> td")) ?? Elements()
            guard tds.size() >= 8 else { continue }
            let title = ((try? tds.get(0).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let startTime = ((try? tds.get(1).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let endTime = ((try? tds.get(2).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let attempts = ((try? tds.get(3).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = ((try? tds.get(4).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let startOnclick = (try? tds.get(5).select("a[onclick]").first()?.attr("onclick")) ?? ""
            let onclickTestId = regexFirstCapture(startOnclick, pattern: #"gotostart\('(\d+)'"#) ?? ""
            let canStart = !onclickTestId.isEmpty

            var resultHref = ""
            if let resA = try? tds.get(7).select("a[href]").first(), !isDisabledLink(resA) {
                resultHref = (try? resA.absUrl("href")) ?? ""
            }
            let hasResult = !resultHref.isEmpty
            let resultTestId = URL(string: resultHref).flatMap { queryParam("testId", in: $0) } ?? ""
            let testId = !onclickTestId.isEmpty ? onclickTestId : (!resultTestId.isEmpty ? resultTestId : "\(lid)_\(idx)")

            let status = hasResult ? "已完成" : (canStart ? "可进行" : "未开始")
            result.append(
                TheolTestItem(
                    testId: testId,
                    lid: lid,
                    courseName: courseName,
                    title: title,
                    startTime: startTime,
                    endTime: endTime,
                    endTimeMillis: parseDeadlineMillis(endTime),
                    duration: duration,
                    allowedAttempts: attempts,
                    canStart: canStart,
                    hasResult: hasResult,
                    status: status,
                    testUrl: listURL,
                    resultHref: resultHref
                )
            )
        }
        return result
    }

    public static func parseTestDetail(_ html: String, fallback: TheolTestItem) -> TheolTestDetail {
        let doc = (try? SwiftSoup.parse(html, meolBase)) ?? Document(meolBase)
        let title = ((try? doc.select("h1, h2, h3, .title").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = ((try? doc.select("div.content, div.description, div#body").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var startTime = fallback.startTime
        var endTime = fallback.endTime
        var duration = fallback.duration
        var totalScore = ""
        var questionCount = ""

        if let rows = try? doc.select("table.info tr, table.infotable tr, table.valuelist tr") {
            for tr in rows {
                let th = ((try? tr.select("> th").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let td = ((try? tr.select("> td").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !th.isEmpty, !td.isEmpty else { continue }
                if th.contains("开始时间") { startTime = td }
                else if th.contains("结束时间") { endTime = td }
                else if th.contains("持续时间") || th.contains("考试时长") { duration = td }
                else if th.contains("总分") { totalScore = td }
                else if th.contains("题目数") || th.contains("问题数") { questionCount = td }
            }
        }

        return TheolTestDetail(
            testId: fallback.testId,
            title: title.isEmpty ? fallback.title : title,
            description: desc,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            totalScore: totalScore,
            questionCount: questionCount
        )
    }

    public static func parseCourseUnits(_ html: String, baseURL: URL) -> [TheolCourseUnit] {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return [] }
        var links = (try? doc.select("#menu ul#ul_advance li a[href]")) ?? Elements()
        if links.isEmpty(), let onclickLinks = try? doc.select("a[onclick]") {
            for a in onclickLinks {
                let text = (try? a.text()) ?? ""
                guard text.contains("单元学习") else { continue }
                let onclick = (try? a.attr("onclick")) ?? ""
                if let parentId = regexFirstCapture(onclick, pattern: #"menuUrl\s*\(\s*['"]1['"]\s*,\s*['"](\d+)['"]"#) {
                    if let fallbackLinks = try? doc.select("#menu ul.ul_\(parentId) li a[href]") {
                        links = fallbackLinks
                        break
                    }
                }
            }
        }

        var units: [TheolCourseUnit] = []
        var seen = Set<String>()
        for a in links {
            let title = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let href = (try? a.absUrl("href")) ?? ""
            guard !title.isEmpty, !href.isEmpty, let url = URL(string: href) else { continue }
            let columnId = queryParam("columnId", in: url) ?? href
            guard seen.insert(columnId).inserted else { continue }
            units.append(TheolCourseUnit(columnId: columnId, title: title, url: href))
        }
        return units
    }

    public static func parseResourceList(_ html: String, lid: String, baseURL: URL) -> [TheolResourceItem] {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return [] }
        let hasValueList = ((try? doc.select("table.valuelist").isEmpty()) == false)
        let rows = hasValueList
            ? ((try? doc.select("table.valuelist tr")) ?? Elements())
            : ((try? doc.select("table.infotable tr, table tr")) ?? Elements())

        let navIgnore: Set<String> = ["返回", "上一级", "返回上一级目录", "上一页", "下一页", "首页", "尾页", "下载", "预览", "排序", "刷新", "全部", "查询"]
        var items: [TheolResourceItem] = []
        var seenURLs = Set<String>()

        for tr in rows {
            guard let links = try? tr.select("a[href]"), !links.isEmpty() else { continue }
            let rowText = ((try? tr.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            var explicitDownloadURL = ""
            for a in links {
                let abs = (try? a.absUrl("href")) ?? ""
                let lower = abs.lowercased()
                if lower.contains("download.jsp") || lower.contains("download_file") || lower.contains("file_download") {
                    explicitDownloadURL = abs
                    break
                }
            }

            var primaryLink: Element?
            for a in links {
                let text = ((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && !navIgnore.contains(text) && !text.hasPrefix("返回上一级") {
                    primaryLink = a
                    break
                }
            }
            guard let chosen = primaryLink else { continue }
            let name = ((try? chosen.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var rawURL = (try? chosen.absUrl("href")) ?? ""
            guard !name.isEmpty, !rawURL.isEmpty else { continue }

            let lowerURL = rawURL.lowercased()
            let lowerName = name.lowercased()
            let knownExts = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "zip", "rar", "7z", "txt", "md", "csv", "mp4", "mp3", "png", "jpg", "jpeg"]
            let hasKnownExt = knownExts.contains { lowerName.hasSuffix(".\($0)") }
            let isFile = lowerURL.contains("download_preview.jsp") || lowerURL.contains("download.jsp") ||
                lowerURL.contains("download_file") || lowerURL.contains("file_download") ||
                lowerURL.contains("fileid=") || lowerURL.contains("resid=") || hasKnownExt

            let hasFolderHint = lowerURL.contains("folderid=") || lowerURL.contains("dirid=") ||
                lowerURL.contains("parentid=") || lowerURL.contains("listview.jsp") ||
                lowerURL.contains("resourcelist") || lowerURL.contains("lessondoc") ||
                ((try? tr.select("img[src*=folder], img[src*=dir], .folder").isEmpty()) == false)
            let isFolder = !isFile && hasFolderHint
            guard isFile || isFolder else { continue }

            var previewURL = ""
            if isFile {
                if !explicitDownloadURL.isEmpty {
                    previewURL = rawURL
                    rawURL = explicitDownloadURL
                } else if let parsed = URL(string: rawURL),
                          parsed.path.lowercased().hasSuffix("/preview/download_preview.jsp"),
                          (queryParam("fileid", in: parsed) != nil || queryParam("resid", in: parsed) != nil) {
                    previewURL = rawURL
                    rawURL = rawURL.replacingOccurrences(of: "/preview/download_preview.jsp", with: "/download.jsp")
                }
            }

            guard seenURLs.insert(rawURL).inserted else { continue }
            let sizeText = regexFirstCapture(rowText, pattern: #"(\d+(?:\.\d+)?\s*(?:B|KB|MB|GB|字节))"#) ?? ""
            let updatedAt = regexFirstCapture(rowText, pattern: #"(\d{4}[-/]\d{1,2}[-/]\d{1,2}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)"#) ?? ""
            let ext = hasKnownExt ? String(lowerName.split(separator: ".").last ?? "") : ""

            items.append(
                TheolResourceItem(
                    name: name,
                    isFolder: isFolder,
                    url: rawURL,
                    sizeText: sizeText,
                    updatedAt: updatedAt,
                    fileExt: ext,
                    previewUrl: previewURL
                )
            )
        }

        if !hasValueList && items.isEmpty {
            let previewLinks = (try? doc.select("#dowload-preview a[href], a.lv-download[href]")) ?? Elements()
            for a in previewLinks {
                var href = (try? a.absUrl("href")) ?? ""
                guard !href.isEmpty else { continue }
                if !href.contains("lid=") && !lid.isEmpty {
                    href += (href.contains("?") ? "&" : "?") + "lid=\(lid)"
                }
                guard seenURLs.insert(href).inserted else { continue }
                let h2 = ((try? doc.select("h2, h1").first()?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedName = h2.replacingOccurrences(of: "文件名:", with: "")
                    .replacingOccurrences(of: "文件名：", with: "")
                    .split(separator: "(").first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                let size = regexFirstCapture(h2, pattern: #"\(([^)]+)\)"#) ?? ""
                let displayName = cleanedName.isEmpty ? (((try? a.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) : cleanedName
                let ext = String(displayName.lowercased().split(separator: ".").last ?? "")
                items.append(
                    TheolResourceItem(
                        name: displayName.isEmpty ? "课程资料" : displayName,
                        isFolder: false,
                        url: href,
                        sizeText: size,
                        updatedAt: "",
                        fileExt: ext,
                        previewUrl: baseURL.absoluteString
                    )
                )
            }
        }

        return items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    public static func extractResourceRedirectUrl(_ html: String, baseURL: URL) -> String? {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return nil }
        if let frames = try? doc.select("iframe[src], frame[src]") {
            var fallback: String?
            for frame in frames {
                let src = (try? frame.absUrl("src")) ?? ""
                let lower = src.lowercased()
                guard !src.isEmpty, URL(string: src)?.host?.lowercased() == "course.buct.edu.cn" else { continue }
                if lower.contains("left.jsp") || lower.contains("leftframe") { continue }
                if lower.contains("listview.jsp") || lower.contains("resourcelist") || lower.contains("mainframe") {
                    return src
                }
                if fallback == nil { fallback = src }
            }
            if let fallback { return fallback }
        }
        if let meta = try? doc.select("meta[http-equiv=refresh]").first()?.attr("content"),
           let rawTarget = regexFirstCapture(meta, pattern: #"(?i)url\s*=\s*(.+)"#),
           let resolved = URL(string: rawTarget.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")), relativeTo: baseURL)?.absoluteString,
           URL(string: resolved)?.host?.lowercased() == "course.buct.edu.cn" {
            return resolved
        }
        if let jsTarget = regexFirstCapture(html, pattern: #"(?:window\.)?location(?:\.href)?\s*=\s*['"]([^'"]+)['"]"#)
            ?? regexFirstCapture(html, pattern: #"(?:window\.)?location\.replace\s*\(\s*['"]([^'"]+)['"]"#),
           let resolved = URL(string: jsTarget, relativeTo: baseURL)?.absoluteString,
           URL(string: resolved)?.host?.lowercased() == "course.buct.edu.cn" {
            return resolved
        }
        return nil
    }

    public static func extractDirectDownloadUrl(_ html: String, baseURL: URL) -> String? {
        guard let doc = try? SwiftSoup.parse(html, baseURL.absoluteString) else { return nil }
        let selectors = ["a.lv-download[href]", "a[href]", "iframe[src]", "frame[src]"]
        for sel in selectors {
            if let els = try? doc.select(sel) {
                let attr = sel.contains("[src]") ? "src" : "href"
                for el in els {
                    let abs = (try? el.absUrl(attr)) ?? ""
                    let lower = abs.lowercased()
                    if (lower.contains("download.jsp") || lower.contains("download_file") || lower.contains("file_download") || lower.contains("attach")) &&
                        !lower.contains("download_preview.jsp") {
                        return abs
                    }
                }
            }
        }
        return nil
    }

    public static func recoverHeaderFilename(contentDisposition: String?, fallbackURL: URL) -> String {
        if let cd = contentDisposition {
            if let extMatch = regexFirstCapture(cd, pattern: #"filename\*\s*=\s*(?:[A-Za-z0-9_\-]+''|[^']*')([^;\r\n]+)"#),
               let decoded = extMatch.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")).removingPercentEncoding,
               !decoded.isEmpty {
                return decoded
            }
            if let rawName = regexFirstCapture(cd, pattern: #"filename\s*=\s*"([^"]+)""#)
                ?? regexFirstCapture(cd, pattern: #"filename\s*=\s*([^;\r\n]+)"#) {
                let cleaned = rawName.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                if cleaned.contains("%"), let unescaped = cleaned.removingPercentEncoding, !unescaped.isEmpty {
                    return unescaped
                }
                if let latinData = cleaned.data(using: .isoLatin1) {
                    if let utf8 = String(data: latinData, encoding: .utf8), !utf8.isEmpty { return utf8 }
                    let gbkEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
                    if let gbk = String(data: latinData, encoding: gbkEnc), !gbk.isEmpty { return gbk }
                }
                if !cleaned.isEmpty { return cleaned }
            }
        }
        let last = fallbackURL.lastPathComponent
        return last.isEmpty ? "attachment.bin" : last
    }

    public static func buildTestListUrl(lid: String) -> String {
        "\(meolBase)/meol/common/question/test/student/list.jsp?sortColumn=createTime&status=1&tagbug=client&sortDirection=-1&strStyle=new03&cateId=\(lid)&pagingPage=1&pagingNumberPer=30"
    }

    public static func parseDeadlineMillis(_ raw: String) -> Int64? {
        let collapsed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !collapsed.isEmpty else { return nil }
        let formats = [
            "yyyy年M月d日 HH:mm:ss",
            "yyyy年M月d日 HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm"
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        for pattern in formats {
            fmt.dateFormat = pattern
            if let date = fmt.date(from: collapsed) {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
        }
        return nil
    }

    private static func isDisabledLink(_ element: Element) -> Bool {
        if element.hasAttr("disabled") { return true }
        if ((try? element.attr("aria-disabled")) ?? "").lowercased() == "true" { return true }
        let cls = ((try? element.attr("class")) ?? "").lowercased()
        return cls.contains("disabled")
    }

    private static func extractLid(fromOnclick onclick: String) -> String? {
        guard let range = onclick.range(of: "lid=") else { return nil }
        let tail = onclick[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private static func queryParam(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private static func removingPagingPage(from url: URL) -> String {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        comps.queryItems = comps.queryItems?.filter { $0.name != "pagingPage" }
        return comps.url?.absoluteString ?? url.absoluteString
    }

    private static func settingQueryParam(name: String, value: String, in url: URL) -> String? {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == name }
        items.append(URLQueryItem(name: name, value: value))
        comps.queryItems = items
        return comps.url?.absoluteString
    }

    private static func regexFirstCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = regex.firstMatch(in: text, range: nsRange), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}
