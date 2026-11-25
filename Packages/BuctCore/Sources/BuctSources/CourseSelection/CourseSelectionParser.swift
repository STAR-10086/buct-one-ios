import BuctModel
import Foundation
import SwiftSoup

public struct CourseSelectionAuthExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "教务选课会话已过期，请重新登录") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum CourseSelectionParser {
    public static let parserVersion = 1

    public static func isSessionExpired(statusCode: Int, url: URL?, body: String) -> Bool {
        if statusCode == 401 || statusCode == 403 || statusCode == 901 { return true }
        if let u = url?.absoluteString.lowercased(),
           u.contains("slogin") || u.contains("login_") || u.contains("cas/") || u.contains("sidportal.buct.edu.cn") {
            return true
        }
        let lower = body.lowercased()
        if lower.contains("notlogin") || lower.contains("sessionexpired") || body.contains("未登录") {
            return true
        }
        if lower.contains("id=\"pwd\"") || (lower.contains("name=\"mm\"") && lower.contains("name=\"yhm\"")) {
            return true
        }
        return false
    }

    public static func parseHiddenInputs(html: String) -> [String: String] {
        guard let doc = try? SwiftSoup.parse(html),
              let inputs = try? doc.select("input[type=hidden]").array() else {
            return [:]
        }
        var map: [String: String] = [:]
        for input in inputs {
            let name = ((try? input.attr("name")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let val = ((try? input.attr("value")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            map[name] = val
        }
        return map
    }

    public static func parseTabParams(html: String, hiddenInputs: [String: String]) -> [CourseSelectionTabParam] {
        let pattern = #"queryCourse\s*\(\s*this\s*,\s*['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]\s*,\s*['"]([^'"]*)['"]\s*\)"#
        var tabs: [CourseSelectionTabParam] = []
        var seen = Set<String>()

        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(html.startIndex..., in: html)
            for match in regex.matches(in: html, range: nsRange) {
                guard let r1 = Range(match.range(at: 1), in: html),
                      let r2 = Range(match.range(at: 2), in: html),
                      let r3 = Range(match.range(at: 3), in: html),
                      let r4 = Range(match.range(at: 4), in: html) else { continue }
                let kklxdm = String(html[r1]).trimmingCharacters(in: .whitespaces)
                let xkkzId = String(html[r2]).trimmingCharacters(in: .whitespaces)
                let njdmId = String(html[r3]).trimmingCharacters(in: .whitespaces)
                let zyhId = String(html[r4]).trimmingCharacters(in: .whitespaces)
                guard !xkkzId.isEmpty else { continue }
                let key = "\(kklxdm)::\(xkkzId)"
                if seen.insert(key).inserted {
                    tabs.append(CourseSelectionTabParam(kklxdm: kklxdm, xkkzId: xkkzId, njdmId: njdmId, zyhId: zyhId))
                }
            }
        }

        if tabs.isEmpty {
            let kklxdm = firstNonEmpty(hiddenInputs, keys: ["firstKklxdm", "kklxdm"], fallback: "10")
            let xkkzId = firstNonEmpty(hiddenInputs, keys: ["firstXkkzId", "firstXkkzXh", "xkkz_id", "xkkz_xh"], fallback: "")
            let njdmId = hiddenInputs["njdm_id"] ?? ""
            let zyhId = hiddenInputs["zyh_id"] ?? ""
            if !xkkzId.isEmpty {
                tabs.append(CourseSelectionTabParam(kklxdm: kklxdm, xkkzId: xkkzId, njdmId: njdmId, zyhId: zyhId))
            }
        }
        return tabs
    }

    public static func extractNotOpenNotice(html: String) -> String {
        guard let doc = try? SwiftSoup.parse(html) else { return "当前不在选课开放时间内" }
        for sel in [".alert", ".nodata", ".error_text", "h4", "p"] {
            if let text = try? doc.select(sel).first()?.text().trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty, text.count >= 4 {
                return text
            }
        }
        return "当前不在选课开放时间内"
    }

    public static func parseCourseList(
        jsonString: String,
        tab: CourseSelectionTabParam? = nil,
        baseParams: [String: String] = [:],
        markSelected: Bool = false
    ) -> [CourseSelectionCourse] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let rows: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            rows = arr
        } else if let dict = root as? [String: Any] {
            if let tmp = dict["tmpList"] as? [[String: Any]] {
                rows = tmp
            } else if let courses = dict["courses"] as? [[String: Any]] {
                rows = courses
            } else {
                rows = []
            }
        } else {
            rows = []
        }

        return rows.compactMap { row -> CourseSelectionCourse? in
            let name = strValue(row["kcmc"])
            let courseId = nonEmpty(strValue(row["kch_id"]), fallback: strValue(row["kch"]))
            guard !name.isEmpty || !courseId.isEmpty else { return nil }
            let classId = strValue(row["jxb_id"])
            let doJxbId = strValue(row["do_jxb_id"])
            let teacher = parseTeacherName(jsxm: strValue(row["jsxm"]), jsxx: strValue(row["jsxx"]))
            let jxbmc = strValue(row["jxbmc"])
            let timeText = cleanHtmlBreaks(strValue(row["sksj"]))
            let location = cleanHtmlBreaks(strValue(row["jxdd"]))
            let credits = nonEmpty(strValue(row["xf"]), fallback: strValue(row["jxbxf"]))
            let capacity = intValue(row["jxbrl"]) ?? intValue(row["jxbrs"]) ?? 0
            let enrolled = intValue(row["yxzrs"]) ?? 0
            let isSelected = markSelected || strValue(row["sfxkbj"]) == "1"

            return CourseSelectionCourse(
                courseId: courseId,
                classId: classId,
                doJxbId: doJxbId,
                name: name.isEmpty ? courseId : name,
                teacher: teacher,
                teachingClassName: jxbmc,
                timeText: timeText,
                location: location,
                credits: credits,
                capacity: capacity,
                enrolled: enrolled,
                isSelected: isSelected,
                kklxdm: nonEmpty(strValue(row["kklxdm"]), fallback: tab?.kklxdm ?? "10"),
                xkkzId: nonEmpty(strValue(row["xkkz_id"]), fallback: nonEmpty(strValue(row["xkkz_xh"]), fallback: tab?.xkkzId ?? "")),
                rwlx: nonEmpty(strValue(row["rwlx"]), fallback: baseParams["rwlx"] ?? "1"),
                xklc: nonEmpty(strValue(row["xklc"]), fallback: baseParams["xklc"] ?? "2"),
                njdmId: nonEmpty(strValue(row["njdm_id"]), fallback: tab?.njdmId ?? baseParams["njdm_id"] ?? ""),
                zyhId: nonEmpty(strValue(row["zyh_id"]), fallback: tab?.zyhId ?? baseParams["zyh_id"] ?? ""),
                xkxnm: nonEmpty(strValue(row["xkxnm"]), fallback: baseParams["xkxnm"] ?? ""),
                xkxqm: nonEmpty(strValue(row["xkxqm"]), fallback: baseParams["xkxqm"] ?? ""),
                rlkz: nonEmpty(strValue(row["rlkz"]), fallback: baseParams["rlkz"] ?? "0"),
                rlzlkz: nonEmpty(strValue(row["rlzlkz"]), fallback: baseParams["rlzlkz"] ?? "0"),
                sxbj: nonEmpty(strValue(row["sxbj"]), fallback: "0"),
                xxkbj: nonEmpty(strValue(row["xxkbj"]), fallback: "0"),
                cxbj: nonEmpty(strValue(row["cxbj"]), fallback: baseParams["cxbj"] ?? "0"),
                jcxxId: strValue(row["jcxx_id"])
            )
        }
    }

    public static func parseSelectResult(jsonString: String) -> CourseSelectionActionResult {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CourseSelectionActionResult(success: false, message: "选课响应格式异常")
        }
        let flag = strValue(obj["flag"])
        let msg = nonEmpty(strValue(obj["msg"]), fallback: strValue(obj["message"]))
        if flag == "1" {
            return CourseSelectionActionResult(success: true, message: msg.isEmpty ? "选课成功" : msg)
        }
        return CourseSelectionActionResult(success: false, message: msg.isEmpty ? "选课未成功" : msg)
    }

    public static func parseDropResult(rawText: String) -> CourseSelectionActionResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "1" || trimmed == "\"1\"" {
            return CourseSelectionActionResult(success: true, message: "退课成功")
        }
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let flag = strValue(obj["flag"])
            let msg = nonEmpty(strValue(obj["msg"]), fallback: strValue(obj["message"]))
            if flag == "1" {
                return CourseSelectionActionResult(success: true, message: msg.isEmpty ? "退课成功" : msg)
            }
            return CourseSelectionActionResult(success: false, message: msg.isEmpty ? "退课失败" : msg)
        }
        return CourseSelectionActionResult(success: false, message: trimmed.isEmpty ? "退课失败" : trimmed)
    }

    // MARK: - Helpers

    public static func parseTeacherName(jsxm: String, jsxx: String) -> String {
        if !jsxm.isEmpty { return jsxm }
        guard !jsxx.isEmpty else { return "" }
        let names = jsxx.split(separator: ";").compactMap { seg -> String? in
            let parts = seg.split(separator: "/")
            if parts.count >= 2 { return String(parts[1]).trimmingCharacters(in: .whitespaces) }
            let trimmed = String(seg).trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        return names.joined(separator: "、")
    }

    private static func cleanHtmlBreaks(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<br\s*/?>"#, with: "；", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstNonEmpty(_ dict: [String: String], keys: [String], fallback: String) -> String {
        for k in keys {
            if let v = dict[k], !v.isEmpty { return v }
        }
        return fallback
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
}
