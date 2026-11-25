import BuctModel
import Foundation

public struct SjcxAuthExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "实践教学登录状态已过期") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum SjcxParser {
    public static let parserVersion = 2

    public static func extractTokenFromLocation(_ location: String) -> String? {
        guard let range = location.range(of: "token=") else { return nil }
        let tail = String(location[range.upperBound...])
        let token = tail.split(whereSeparator: { $0 == "&" || $0 == "#" }).first.map(String.init) ?? ""
        return token.isEmpty ? nil : token
    }

    public static func parseEnvelope(_ jsonString: String) throws -> Any? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SjcxAuthExpiredError("实践教学响应格式异常")
        }
        let code = intValue(root["code"]) ?? 200
        let msg = strValue(root["msg"]).isEmpty ? strValue(root["message"]) : strValue(root["msg"])
        if code == 401 || code == 403 || msg.contains("登录状态已过期") || msg.contains("未登录") {
            throw SjcxAuthExpiredError(msg.isEmpty ? "实践教学会话已过期" : msg)
        }
        if code != 200 && code != 0 {
            throw NSError(domain: "SjcxParser", code: code, userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "实践教学接口错误（\(code)）" : msg])
        }
        return root["data"]
    }

    public static func parseCasLoginData(_ jsonString: String) throws -> (rsaKey: String, yearterm: String) {
        guard let dict = try parseEnvelope(jsonString) as? [String: Any] else {
            throw SjcxAuthExpiredError("未能获取实践教学签名公钥")
        }
        let random = strValue(dict["random"])
        guard !random.isEmpty else {
            throw SjcxAuthExpiredError("实践教学签名公钥为空")
        }
        return (random, strValue(dict["yearterm"]))
    }

    public static func parseReports(_ jsonString: String) -> [SjcxReportItem] {
        guard let list = extractDataList(jsonString) else { return [] }
        var byKey: [String: SjcxReportItem] = [:]
        var order: [String] = []

        for courseObj in list {
            let courseName = firstNonEmpty(courseObj, keys: ["course_name", "courseName", "kcmc"])
            let exps = (courseObj["course_exp"] as? [[String: Any]]) ?? [courseObj]
            for exp in exps {
                let expName = firstNonEmpty(exp, keys: ["exp_name", "expName", "report_name", "name"])
                guard !expName.isEmpty || !courseName.isEmpty else { continue }
                let reportId = firstNonEmpty(exp, keys: ["report_id", "reportId", "id"])
                let groupId = firstNonEmpty(exp, keys: ["group_id", "groupId"])
                let docName = firstNonEmpty(exp, keys: ["doc_name", "docName", "file_name"])
                let templateId = firstNonEmpty(exp, keys: ["template_id", "exp_report_id"])
                let templateName = firstNonEmpty(exp, keys: ["template_name", "exp_report_name"])
                let state = intValue(exp["state"]) ?? (docName.isEmpty ? 0 : 1)
                let stateText = firstNonEmpty(exp, keys: ["state_name", "stateName"]).isEmpty
                    ? defaultReportState(state: state, hasDoc: !docName.isEmpty)
                    : firstNonEmpty(exp, keys: ["state_name", "stateName"])
                let scoreText = firstNonEmpty(exp, keys: ["score", "final_score"])
                let opinion = firstNonEmpty(exp, keys: ["opinion", "comment", "remark"])
                let submitTime = firstNonEmpty(exp, keys: ["submit_time", "update_time", "create_time"])

                let key = "\(courseName)|\(expName)|\(reportId)"
                let item = SjcxReportItem(
                    id: key,
                    reportId: reportId,
                    groupId: groupId,
                    courseName: courseName.isEmpty ? "实验课程" : courseName,
                    expName: expName.isEmpty ? courseName : expName,
                    docName: docName,
                    templateId: templateId,
                    templateName: templateName,
                    state: state,
                    stateText: stateText,
                    scoreText: scoreText,
                    opinion: opinion,
                    submitTime: submitTime
                )
                if let existing = byKey[key] {
                    if shouldReplace(existing: existing, candidate: item) {
                        byKey[key] = item
                    }
                } else {
                    order.append(key)
                    byKey[key] = item
                }
            }
        }
        return order.compactMap { byKey[$0] }
    }

    public static func parseSchedules(_ jsonString: String) -> [SjcxScheduleItem] {
        guard let list = extractDataList(jsonString) else { return [] }
        return list.enumerated().compactMap { idx, obj in
            let course = firstNonEmpty(obj, keys: ["course_name", "courseName"])
            let exp = firstNonEmpty(obj, keys: ["exp_name", "expName"])
            guard !course.isEmpty || !exp.isEmpty else { return nil }
            let week = intValue(obj["week"]) ?? intValue(obj["zc"]) ?? 1
            let day = intValue(obj["week_day"]) ?? intValue(obj["weekDay"]) ?? intValue(obj["xqj"]) ?? 1
            let jc = firstNonEmpty(obj, keys: ["jc", "jc_text", "section"])
            let room = firstNonEmpty(obj, keys: ["room_name", "roomName", "lab_name"])
            let teacher = firstNonEmpty(obj, keys: ["teacher_name", "teacherName", "tea_name"])
            return SjcxScheduleItem(
                id: "sch-\(idx)-\(week)-\(day)-\(exp)",
                courseName: course,
                expName: exp,
                week: week,
                weekDay: day,
                jcText: jc,
                roomName: room,
                teacherName: teacher
            )
        }.sorted { a, b in
            if a.week != b.week { return a.week < b.week }
            if a.weekDay != b.weekDay { return a.weekDay < b.weekDay }
            return a.jcText < b.jcText
        }
    }

    public static func parseScores(_ jsonString: String) -> [SjcxScoreItem] {
        guard let list = extractDataList(jsonString) else { return [] }
        var items: [SjcxScoreItem] = []
        for courseObj in list {
            let course = firstNonEmpty(courseObj, keys: ["course_name", "courseName"])
            let exps = (courseObj["course_exp"] as? [[String: Any]]) ?? [courseObj]
            for (idx, exp) in exps.enumerated() {
                let expName = firstNonEmpty(exp, keys: ["exp_name", "expName"])
                let score = firstNonEmpty(exp, keys: ["score", "total_score"])
                guard !expName.isEmpty || !score.isEmpty else { continue }
                let details = (1...5).compactMap { n -> String? in
                    let val = strValue(exp["score\(n)"])
                    return val.isEmpty ? nil : "分项\(n): \(val)"
                }
                items.append(
                    SjcxScoreItem(
                        id: "sc-\(course)-\(expName)-\(idx)",
                        courseName: course,
                        expName: expName,
                        scoreText: score.isEmpty ? "--" : score,
                        detailScores: details
                    )
                )
            }
        }
        return items
    }

    public static func parseLectures(_ jsonString: String, isRegistered: Bool) -> [SjcxLectureItem] {
        guard let list = extractDataList(jsonString) else { return [] }
        return list.enumerated().compactMap { idx, obj in
            let title = firstNonEmpty(obj, keys: ["project_name", "projectName", "title", "name"])
            guard !title.isEmpty else { return nil }
            let ptId = firstNonEmpty(obj, keys: ["project_time_id", "projectTimeId", "id"])
            let regId = firstNonEmpty(obj, keys: ["cre_project_stu_id", "creProjectStuId", "id"])
            let speaker = firstNonEmpty(obj, keys: ["speaker", "teacher_name", "host"])
            let location = firstNonEmpty(obj, keys: ["address", "place", "location"])
            let startTime = firstNonEmpty(obj, keys: ["start_time", "hold_time", "time"])
            let credit = doubleValue(obj["credit"]) ?? doubleValue(obj["score"]) ?? 0
            let enrolled = strValue(obj["enroll_num"])
            let maxCap = strValue(obj["max_num"])
            let capText = (!enrolled.isEmpty && !maxCap.isEmpty) ? "\(enrolled)/\(maxCap)" : ""
            let statusText = firstNonEmpty(obj, keys: ["state_name", "status_name", "sign_state_name"])
            let hasExp = !firstNonEmpty(obj, keys: ["experience", "summary"]).isEmpty

            return SjcxLectureItem(
                id: nonEmpty(ptId.isEmpty ? regId : ptId, fallback: "lec-\(idx)"),
                projectTimeId: ptId,
                registrationId: regId,
                title: title,
                speaker: speaker,
                location: location,
                startTime: startTime,
                credit: credit,
                capacityText: capText,
                statusText: statusText,
                isRegistered: isRegistered,
                hasExperience: hasExp
            )
        }
    }

    public static func parseCredits(_ jsonString: String) -> (total: Double, records: [SjcxCreditRecord]) {
        guard let data = try? parseEnvelope(jsonString) as? [String: Any] else { return (0, []) }
        let reportedTotal = doubleValue(data["totalCredit"]) ?? doubleValue(data["total_credit"]) ?? 0
        let rawList = (data["list"] as? [[String: Any]]) ?? []
        let records: [SjcxCreditRecord] = rawList.enumerated().compactMap { idx, obj in
            let title = firstNonEmpty(obj, keys: ["project_name", "title", "name"])
            guard !title.isEmpty else { return nil }
            let cat = firstNonEmpty(obj, keys: ["type_name", "category", "project_type"])
            let credit = doubleValue(obj["credit"]) ?? doubleValue(obj["score"]) ?? 0
            let time = firstNonEmpty(obj, keys: ["create_time", "grant_time", "time"])
            return SjcxCreditRecord(id: "cr-\(idx)-\(title)", title: title, category: cat, credit: credit, grantedAt: time)
        }
        let sum = records.reduce(0.0) { $0 + $1.credit }
        return (reportedTotal > 0 ? reportedTotal : sum, records)
    }

    public static func parseNoSignCount(_ jsonString: String) -> Int {
        guard let data = try? parseEnvelope(jsonString) as? [String: Any] else { return 0 }
        return intValue(data["no_sign_num"]) ?? intValue(data["noSignNum"]) ?? 0
    }

    // MARK: - Helpers

    private static func extractDataList(_ jsonString: String) -> [[String: Any]]? {
        guard let data = try? parseEnvelope(jsonString) else { return nil }
        if let dict = data as? [String: Any], let list = dict["list"] as? [[String: Any]] {
            return list
        }
        if let arr = data as? [[String: Any]] {
            return arr
        }
        return nil
    }

    private static func shouldReplace(existing: SjcxReportItem, candidate: SjcxReportItem) -> Bool {
        if candidate.isSubmitted != existing.isSubmitted { return candidate.isSubmitted }
        if !candidate.docName.isEmpty && existing.docName.isEmpty { return true }
        return candidate.state > existing.state
    }

    private static func defaultReportState(state: Int, hasDoc: Bool) -> String {
        if state >= 2 { return "已批阅" }
        if state == 1 || hasDoc { return "已提交" }
        return "待提交"
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
}
