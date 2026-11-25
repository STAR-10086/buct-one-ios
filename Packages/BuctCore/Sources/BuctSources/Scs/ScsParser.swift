import BuctModel
import Foundation

public struct ScsAuthExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "第二课堂登录状态已过期") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum ScsParser {
    public static let parserVersion = 2

    public static func parseEnvelope(_ jsonString: String) throws -> Any? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScsAuthExpiredError("第二课堂响应格式异常")
        }
        let code = intValue(root["code"]) ?? 200
        let msg = strValue(root["message"]).isEmpty ? strValue(root["msg"]) : strValue(root["message"])
        if code == 401 || code == 403 || msg.localizedCaseInsensitiveContains("token") || msg.contains("未登录") || msg.contains("过期") {
            throw ScsAuthExpiredError(msg.isEmpty ? "第二课堂令牌已过期" : msg)
        }
        if code != 200 && code != 0 {
            throw NSError(domain: "ScsParser", code: code, userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "第二课堂接口错误（\(code)）" : msg])
        }
        return root["data"]
    }

    public static func parseUserInfo(_ jsonString: String) -> (name: String, studentId: String) {
        guard let dict = (try? parseEnvelope(jsonString)) as? [String: Any] else { return ("", "") }
        return (strValue(dict["name"]), strValue(dict["gh"]))
    }

    public static func parseDefaultWindow(_ jsonString: String) -> ScsEvalWindow? {
        guard let dict = (try? parseEnvelope(jsonString)) as? [String: Any] else { return nil }
        return ScsEvalWindow(
            yearId: intValue(dict["yearId"]) ?? 0,
            termId: intValue(dict["termId"]) ?? 0,
            yearName: strValue(dict["yearName"]),
            termName: strValue(dict["termName"]),
            isOpen: boolValue(dict["open"]),
            selfStartTime: strValue(dict["selfStartTime"]),
            selfEndTime: strValue(dict["selfEndTime"])
        )
    }

    public static func parseDimensions(_ jsonString: String) -> [ScsDimensionDef] {
        guard let arr = (try? parseEnvelope(jsonString)) as? [[String: Any]] else { return defaultDimensions }
        let parsed = arr.compactMap { obj -> ScsDimensionDef? in
            if boolValue(obj["deleted"]) { return nil }
            guard let id = intValue(obj["id"]) else { return nil }
            let name = nonEmpty(strValue(obj["description"]), fallback: defaultDimensionName(for: id))
            let total = doubleValue(obj["totalScore"]) ?? defaultDimensionMax(for: id)
            return ScsDimensionDef(
                id: id,
                name: name,
                totalScore: total,
                basicScore: doubleValue(obj["basicScore"]) ?? 0,
                extScore: doubleValue(obj["extScore"]) ?? 0
            )
        }
        return parsed.isEmpty ? defaultDimensions : parsed.sorted { $0.id < $1.id }
    }

    public static func parseAllTermScores(_ jsonString: String, dimensions: [ScsDimensionDef]) throws -> [ScsTermScore] {
        guard let years = try parseEnvelope(jsonString) as? [[String: Any]] else { return [] }
        let dimMap = Dictionary(uniqueKeysWithValues: dimensions.map { ($0.id, $0) })
        var results: [ScsTermScore] = []

        for yearObj in years {
            let yearId = intValue(yearObj["year"]) ?? intValue(yearObj["yearId"]) ?? 0
            let yearName = firstNonEmpty(yearObj, keys: ["mc", "yearName"])
            let termList = (yearObj["terms"] as? [[String: Any]]) ?? []
            for t in termList {
                let termId = intValue(t["id"]) ?? intValue(t["termId"]) ?? 0
                let termYearId = intValue(t["yearId"]) ?? yearId
                let termName = firstNonEmpty(t, keys: ["mc", "termName"])
                let isFullYear = (termId == 0 || termName == "全年")
                let scoreObj = (t["studentScore"] as? [String: Any]) ?? t
                let moral = doubleValue(scoreObj["moral"]) ?? 0
                let academic = doubleValue(scoreObj["academic"]) ?? 0
                let physical = doubleValue(scoreObj["physical"]) ?? 0
                let aesthetics = doubleValue(scoreObj["aesthetics"]) ?? 0
                let labor = doubleValue(scoreObj["labor"]) ?? 0
                let total = doubleValue(t["totalScore"]) ?? doubleValue(scoreObj["totalScore"]) ?? (moral + academic + physical + aesthetics + labor)

                let rawDetails = (t["details"] as? [[String: Any]]) ?? []
                let details = rawDetails.enumerated().compactMap { idx, d -> ScsCategoryDetail? in
                    let typeId = intValue(d["typeId"]) ?? intValue(d["id"]) ?? (idx + 1)
                    let name = nonEmpty(firstNonEmpty(d, keys: ["desc", "typeName"]), fallback: dimMap[typeId]?.name ?? defaultDimensionName(for: typeId))
                    let maxScore = doubleValue(d["typeTotalScore"]) ?? dimMap[typeId]?.totalScore ?? defaultDimensionMax(for: typeId)
                    var items: [ScsEvalItem] = []
                    for b in (d["basic"] as? [[String: Any]]) ?? [] {
                        if boolValue(b["deleted"]) { continue }
                        items.append(parseEvalItem(b, isBasic: true))
                    }
                    for e in (d["ext"] as? [[String: Any]]) ?? [] {
                        if boolValue(e["deleted"]) { continue }
                        items.append(parseEvalItem(e, isBasic: false))
                    }
                    let catScore = doubleValue(d["studentTypeScore"]) ?? doubleValue(d["totalScore"]) ?? doubleValue(d["score"]) ?? items.reduce(0) { $0 + $1.score }
                    return ScsCategoryDetail(typeId: typeId, typeName: name, score: catScore, maxScore: maxScore, items: items)
                }.sorted { $0.typeId < $1.typeId }

                results.append(
                    ScsTermScore(
                        yearId: termYearId,
                        termId: termId,
                        yearName: yearName,
                        termName: termName.isEmpty ? (isFullYear ? "全年" : "学期\(termId)") : termName,
                        isFullYear: isFullYear,
                        totalScore: total,
                        moral: moral,
                        academic: academic,
                        physical: physical,
                        aesthetics: aesthetics,
                        labor: labor,
                        details: details
                    )
                )
            }
        }

        return results.sorted { a, b in
            if a.yearName != b.yearName { return a.yearName > b.yearName }
            if a.isFullYear != b.isFullYear { return a.isFullYear }
            return a.termId < b.termId
        }
    }

    public static func parseHistoryProfile(_ jsonString: String) -> (college: String, className: String, grade: String) {
        guard let raw = try? parseEnvelope(jsonString) else { return ("", "", "") }
        let list: [[String: Any]]
        if let arr = raw as? [[String: Any]] {
            list = arr
        } else if let dict = raw as? [String: Any], let records = dict["records"] as? [[String: Any]] {
            list = records
        } else {
            return ("", "", "")
        }
        guard let first = list.first else { return ("", "", "") }
        return (strValue(first["courtName"]), strValue(first["className"]), strValue(first["gradeName"]))
    }

    public static func parseActivities(_ jsonString: String) -> [ScsActivityItem] {
        guard let raw = try? parseEnvelope(jsonString) else { return [] }
        let records: [[String: Any]]
        if let dict = raw as? [String: Any], let arr = dict["records"] as? [[String: Any]] {
            records = arr
        } else if let arr = raw as? [[String: Any]] {
            records = arr
        } else {
            return []
        }

        return records.enumerated().compactMap { idx, obj in
            let title = firstNonEmpty(obj, keys: ["activityName", "title", "name"])
            guard !title.isEmpty else { return nil }
            let id = nonEmpty(firstNonEmpty(obj, keys: ["id", "activityId"]), fallback: "act-\(idx)")
            let category = firstNonEmpty(obj, keys: ["typeName", "categoryName", "plateName"])
            let start = firstNonEmpty(obj, keys: ["startTime", "activityStartTime", "holdTime"])
            let loc = firstNonEmpty(obj, keys: ["address", "location", "place"])
            let score = firstNonEmpty(obj, keys: ["score", "credit", "awardScore"])
            let status = firstNonEmpty(obj, keys: ["statusName", "stateName", "status"])
            return ScsActivityItem(
                id: id,
                title: title,
                categoryName: category,
                startTime: start,
                location: loc,
                scoreText: score.isEmpty ? "" : "+\(score)",
                status: status
            )
        }
    }

    // MARK: - Helpers

    private static let defaultDimensions: [ScsDimensionDef] = [
        ScsDimensionDef(id: 1, name: "德育", totalScore: 180),
        ScsDimensionDef(id: 2, name: "智育", totalScore: 120),
        ScsDimensionDef(id: 3, name: "体育", totalScore: 100),
        ScsDimensionDef(id: 4, name: "美育", totalScore: 100),
        ScsDimensionDef(id: 5, name: "劳育", totalScore: 100)
    ]

    private static func defaultDimensionName(for id: Int) -> String {
        switch id {
        case 1: return "德育"
        case 2: return "智育"
        case 3: return "体育"
        case 4: return "美育"
        case 5: return "劳育"
        default: return "其他"
        }
    }

    private static func defaultDimensionMax(for id: Int) -> Double {
        switch id {
        case 1: return 180
        case 2: return 120
        default: return 100
        }
    }

    private static func parseEvalItem(_ obj: [String: Any], isBasic: Bool) -> ScsEvalItem {
        let id = nonEmpty(firstNonEmpty(obj, keys: ["id", "itemId"]), fallback: UUID().uuidString)
        let title = firstNonEmpty(obj, keys: ["shortDesc", "description", "itemName", "name", "title"])
        return ScsEvalItem(
            id: id,
            title: title.isEmpty ? "评价项目" : title,
            isBasic: boolValue(obj["basic"]) || isBasic,
            score: doubleValue(obj["score"]) ?? doubleValue(obj["finalScore"]) ?? 0,
            maxScore: doubleValue(obj["maxScore"]) ?? doubleValue(obj["totalScore"]) ?? 0,
            laborHours: doubleValue(obj["laborHours"]) ?? doubleValue(obj["hours"]) ?? 0,
            comment: firstNonEmpty(obj, keys: ["teacherComments", "comment", "remark"])
        )
    }

    private static func firstNonEmpty(_ dict: [String: Any], keys: [String]) -> String {
        for k in keys {
            let v = strValue(dict[k])
            if !v.isEmpty { return v }
        }
        return ""
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    private static func strValue(_ raw: Any?) -> String {
        if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.intValue != 0 }
        if let s = raw as? String { return s.lowercased() == "true" || s == "1" }
        return false
    }
}
