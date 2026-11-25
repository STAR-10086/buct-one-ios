import BuctModel
import Foundation

public enum PortalCalendarParser {
    public static let parserVersion = 2

    public static func parseJxzResponse(_ jsonString: String) throws -> OfficialCalendarSnapshot {
        guard let data = jsonString.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "PortalCalendarParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "校历响应格式异常"])
        }
        let result = "\(root["result"] ?? "")"
        guard result == "1", let dataObj = root["data"] as? [String: Any] else {
            let reason = (root["reason"] as? String) ?? "获取校历失败"
            throw NSError(domain: "PortalCalendarParser", code: -2, userInfo: [NSLocalizedDescriptionKey: reason])
        }

        let beginDate = String(((dataObj["beginDate"] as? String) ?? "").prefix(10))
        let endDate = String(((dataObj["endDate"] as? String) ?? "").prefix(10))
        let jxz = Int("\(dataObj["jxz"] ?? "0")") ?? 0

        let retStr = (dataObj["retStr"] as? [[String: Any]]) ?? []
        var terms: [OfficialTermDate] = []
        for item in retStr {
            guard let xn = Int("\(item["xn"] ?? "")"),
                  let xq = Int("\(item["xq"] ?? "")") else {
                continue
            }
            let ksrq = String(((item["ksrq"] as? String) ?? "").prefix(10))
            let jsrq = String(((item["jsrq"] as? String) ?? "").prefix(10))
            guard ksrq.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
                continue
            }
            let wid = "\(item["wid"] ?? "")"
            let isCurrent = "\(item["sfdqxq"] ?? "")" == "1"
            terms.append(
                OfficialTermDate(
                    wid: wid,
                    academicYear: xn,
                    semester: xq,
                    termId: "\(xn)-\(xn + 1)-\(xq)",
                    beginDate: ksrq,
                    endDate: jsrq,
                    isCurrent: isCurrent
                )
            )
        }

        let currentTerm = terms.first(where: \.isCurrent)
            ?? terms.first(where: { $0.beginDate == beginDate })
        let currentTermId = currentTerm?.termId ?? AcademicTerm.calendarDefault().id

        return OfficialCalendarSnapshot(
            currentTermId: currentTermId,
            beginDate: beginDate,
            endDate: endDate,
            currentTeachingWeek: jxz,
            terms: terms,
            holidays: []
        )
    }

    public static func parseCalendarDays(_ jsonString: String) -> [CalendarHoliday] {
        guard let data = jsonString.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }

        var byDate: [String: CalendarHoliday] = [:]
        for item in arr {
            let day = String(((item["day"] as? String) ?? "").prefix(10))
            guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
                continue
            }
            let isHoliday = (item["isHoliday"] as? Bool) == true
            let holidayName = ((item["holidayName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard isHoliday || !holidayName.isEmpty else { continue }
            let week = Int("\(item["teachingWeek"] ?? "0")") ?? 0
            let candidate = CalendarHoliday(date: day, name: holidayName, teachingWeek: week)
            if let existing = byDate[day], !existing.name.isEmpty, candidate.name.isEmpty {
                continue
            }
            byDate[day] = candidate
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    public static func parseNewsArticlesPage(_ jsonString: String, columnId: String) throws -> PortalNewsColumnPage {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        let sliced: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            sliced = String(trimmed[start...end])
        } else {
            sliced = trimmed
        }
        guard let data = sliced.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "PortalCalendarParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "校内资讯响应格式异常"])
        }
        let result = "\(root["result"] ?? "")"
        guard result == "1", let dataObj = root["data"] as? [String: Any] else {
            let reason = (root["reason"] as? String) ?? "获取校内资讯失败"
            throw NSError(domain: "PortalCalendarParser", code: -2, userInfo: [NSLocalizedDescriptionKey: reason])
        }

        let rawArticles = (dataObj["articles"] as? [[String: Any]]) ?? []
        var articles: [PortalNewsArticle] = []
        var seen = Set<String>()

        for row in rawArticles {
            let titleRaw = cleanString(row["title"])
            let title = titleRaw.isEmpty ? "校内资讯" : titleRaw
            let rawId = cleanString(row["id"])
            guard !(rawId.isEmpty && titleRaw.isEmpty) else { continue }

            let sourceOrg = cleanString(row["from"]).isEmpty ? cleanString(row["createOrg"]) : cleanString(row["from"])
            let publishTs = Int64(cleanString(row["publishTimestamp"])) ?? 0
            let id = rawId.isEmpty ? "\(columnId)|\(publishTs)|\(title)" : rawId
            guard seen.insert(id).inserted else { continue }

            let summary = cleanString(row["summary"])
            let content = cleanString(row["content"])
            let rawLink = [row["linkUrl"], row["articleUrl"], row["mobileArticleUrl"]]
                .map { cleanString($0) }
                .first { !$0.isEmpty } ?? ""
            let publicUrl = extractPublicArticleUrl(rawLink)

            articles.append(
                PortalNewsArticle(
                    id: id,
                    columnId: columnId,
                    title: title,
                    sourceOrg: sourceOrg,
                    publishTimestampMs: publishTs,
                    summary: summary,
                    content: content,
                    publicUrl: publicUrl,
                    isTop: cleanString(row["isTop"]) == "1",
                    isHot: cleanString(row["isHot"]) == "1",
                    isNewest: cleanString(row["isNewest"]) == "1",
                    visitCount: Int(cleanString(row["visitCount"])) ?? 0
                )
            )
        }

        let total = max(Int(cleanString(dataObj["count"])) ?? 0, articles.count)
        return PortalNewsColumnPage(columnId: columnId, totalCount: total, articles: articles)
    }

    public static func parseBorrowedBooks(_ jsonString: String) throws -> PortalLibrarySnapshot {
        guard let data = jsonString.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NSError(domain: "PortalCalendarParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "图书在借响应格式异常"])
        }
        let result = "\(root["result"] ?? "")"
        guard result == "1", let dataObj = root["data"] as? [String: Any] else {
            let reason = (root["reason"] as? String) ?? "获取在借图书失败"
            throw NSError(domain: "PortalCalendarParser", code: -2, userInfo: [NSLocalizedDescriptionKey: reason])
        }

        let list = (dataObj["list"] as? [[String: Any]]) ?? []
        var books: [PortalBookItem] = []
        for row in list {
            let titleRaw = cleanString(row["tsmc"])
            let barcode = cleanString(row["tstxm"])
            guard !(titleRaw.isEmpty && barcode.isEmpty) else { continue }
            books.append(
                PortalBookItem(
                    title: titleRaw.isEmpty ? "未知书名" : titleRaw,
                    barcode: barcode,
                    borrowDate: cleanString(row["jsrq"]),
                    dueDate: cleanString(row["hsrq"])
                )
            )
        }
        let total = max(Int(cleanString(dataObj["count"])) ?? 0, books.count)
        return PortalLibrarySnapshot(totalCount: total, books: books)
    }

    private static func extractPublicArticleUrl(_ rawLink: String) -> String {
        let trimmed = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "linkUrl=") else { return trimmed }
        let after = trimmed[range.upperBound...]
        let encoded = after.split(separator: "&", maxSplits: 1).first.map(String.init) ?? String(after)
        return encoded.removingPercentEncoding ?? encoded
    }

    private static func cleanString(_ raw: Any?) -> String {
        guard let raw, !(raw is NSNull) else { return "" }
        let s = "\(raw)".trimmingCharacters(in: .whitespacesAndNewlines)
        return s.caseInsensitiveCompare("null") == .orderedSame ? "" : s
    }
}
