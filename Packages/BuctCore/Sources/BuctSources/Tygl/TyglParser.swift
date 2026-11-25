import BuctModel
import Foundation
import SwiftSoup

public struct TyglAuthExpiredError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String = "体测与体育系统登录已过期") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum TyglParser {
    public static let parserVersion = 1

    public static func isAuthenticatedPage(_ html: String) -> Bool {
        let lower = html.lowercased()
        if lower.contains("login-page-flowkey") || lower.contains("login-croypto") || lower.contains("accessdenied") || lower.contains("login.php") {
            return false
        }
        return html.contains("mainContent") || html.contains("searchtermresults") || html.contains("stu_ht_score") || html.contains("学生登陆成功") || html.contains("测试年度")
    }

    public static func extractYearTabs(from html: String) -> [String] {
        guard let doc = try? SwiftSoup.parse(html),
              let links = try? doc.select("table.table_t a[href*=stu_ht_score]").array() else {
            return []
        }
        var years: [String] = []
        var seen = Set<String>()
        for a in links {
            let href = (try? a.attr("href")) ?? ""
            if let range = href.range(of: "year=") {
                let raw = String(href[range.upperBound...]).split(separator: "&").first.map(String.init) ?? ""
                let decoded = raw.removingPercentEncoding ?? raw
                if !decoded.isEmpty && seen.insert(decoded).inserted {
                    years.append(decoded)
                }
            }
        }
        return Array(years.prefix(6))
    }

    public static func parseFitnessPage(html: String, fallbackYear: String = "") -> (profile: TyglStudentProfile?, record: TyglFitnessRecord?) {
        guard let doc = try? SwiftSoup.parse(html),
              let tables = try? doc.select("table.table_bg").array() else {
            return (nil, nil)
        }

        var kv: [String: String] = [:]
        var items: [TyglFitnessItem] = []
        var bonusScore = ""
        var bonusReason = ""
        var prescriptions: [String] = []

        for table in tables {
            let tableText = (try? table.text()) ?? ""
            if tableText.contains("运动处方") {
                if let rows = try? table.select("tr").array() {
                    for row in rows {
                        let line = (try? row.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !line.isEmpty && !line.contains("运动处方") {
                            prescriptions.append(line)
                        }
                    }
                }
                continue
            }

            guard let rows = try? table.select("tr").array() else { continue }
            for row in rows {
                let cells = ((try? row.select("th, td").array()) ?? []).map {
                    ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if cells.count == 8 {
                    // 双四元组：[项目, 成绩, 得分, 等级, 项目2, 成绩2, 得分2, 等级2]
                    parseQuartet(Array(cells[0..<4]), items: &items, bonusScore: &bonusScore, bonusReason: &bonusReason)
                    parseQuartet(Array(cells[4..<8]), items: &items, bonusScore: &bonusScore, bonusReason: &bonusReason)
                } else if cells.count >= 2 && cells.count % 2 == 0 {
                    var i = 0
                    while i + 1 < cells.count {
                        let k = cells[i].replacingOccurrences(of: "：", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
                        let v = cells[i + 1]
                        if !k.isEmpty && !v.isEmpty {
                            kv[k] = v
                        }
                        i += 2
                    }
                }
            }
        }

        let profile: TyglStudentProfile?
        if let name = kv["姓名"], !name.isEmpty {
            profile = TyglStudentProfile(
                name: name,
                studentId: kv["学号"] ?? "",
                gender: kv["性别"] ?? "",
                grade: kv["年级"] ?? "",
                className: kv["行政班"] ?? "",
                college: kv["学院"] ?? "",
                testRequired: kv["是否测试"] ?? "",
                specialNote: kv["特殊情况"] ?? ""
            )
        } else {
            profile = nil
        }

        let year = (kv["测试年度"] ?? "").isEmpty ? fallbackYear : (kv["测试年度"] ?? "")
        let record: TyglFitnessRecord?
        if !year.isEmpty || !items.isEmpty {
            record = TyglFitnessRecord(
                year: year.isEmpty ? "当前年度" : year,
                updatedAt: kv["最后更新"] ?? "",
                totalScore: kv["成绩"] ?? kv["总分"] ?? "",
                level: kv["等级"] ?? "",
                heightCm: kv["身高"] ?? "",
                weightKg: kv["体重"] ?? "",
                bonusScore: bonusScore,
                bonusReason: bonusReason,
                items: items,
                prescriptions: prescriptions
            )
        } else {
            record = nil
        }

        return (profile, record)
    }

    public static func parseSunScorePage(html: String) -> (runPlan: TyglRunPlan?, columns: [String], terms: [TyglExerciseTerm]) {
        guard let doc = try? SwiftSoup.parse(html) else { return (nil, [], []) }

        var runPlan: TyglRunPlan?
        if let planTable = try? doc.select("#runPlanContent table").first() {
            let text = (try? planTable.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                runPlan = TyglRunPlan(term: "本学期阳光长跑", summary: text)
            }
        }

        var columns: [String] = []
        var terms: [TyglExerciseTerm] = []

        if let tables = try? doc.select("table.table_bg").array() {
            for table in tables {
                guard let rows = try? table.select("tr").array(), rows.count >= 2 else { continue }
                let headers = ((try? rows[0].select("th, td").array()) ?? []).map {
                    cleanHeader(((try? $0.text()) ?? ""))
                }
                guard headers.contains("学年") else { continue }
                let dynamicCols = headers.filter { $0 != "学年" && $0 != "学期" && !$0.isEmpty }
                if columns.isEmpty { columns = dynamicCols }

                for row in rows.dropFirst() {
                    let cells = ((try? row.select("td").array()) ?? []).map {
                        ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    guard cells.count >= 2 else { continue }
                    let year = cells[0]
                    let term = cells[1]
                    guard !year.isEmpty else { continue }
                    var values: [String: String] = [:]
                    for (idx, col) in headers.enumerated() where idx >= 2 && idx < cells.count {
                        let cleanedVal = cells[idx].replacingOccurrences(of: "(查看明细)", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        values[col] = cleanedVal
                    }
                    terms.append(TyglExerciseTerm(year: year, term: term, values: values))
                }
            }
        }
        return (runPlan, columns, terms)
    }

    public static func parsePeCourses(html: String) -> [TyglPeCourseScore] {
        guard let doc = try? SwiftSoup.parse(html),
              let rows = try? doc.select("table#searchtermresults tr").array(),
              rows.count >= 2 else {
            return []
        }
        var results: [TyglPeCourseScore] = []
        for row in rows.dropFirst() {
            let tds = (try? row.select("td").array()) ?? []
            if tds.count == 1, let cs = Int((try? tds[0].attr("colspan")) ?? ""), cs >= 4 {
                continue
            }
            guard tds.count >= 5 else { continue }
            let cells = tds.map { ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            let year = cells[0]
            let term = cells[1]
            let name = cells[2]
            let teacher = cells.count > 3 ? cells[3] : ""
            let score = cells.count > 4 ? cells[4] : ""
            let note = cells.count > 5 ? cells[5] : ""
            if !name.isEmpty {
                results.append(TyglPeCourseScore(year: year, term: term, courseName: name, teacher: teacher, score: score, note: note))
            }
        }
        return results
    }

    public static func parseExamPage(html: String) -> TyglExamInfo? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        var kv: [String: String] = [:]
        if let tables = try? doc.select("table.table_bg").array() {
            for table in tables {
                for row in (try? table.select("tr").array()) ?? [] {
                    let cells = ((try? row.select("th, td").array()) ?? []).map {
                        ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if cells.count >= 2 && cells.count % 2 == 0 {
                        var i = 0
                        while i + 1 < cells.count {
                            let k = cells[i].replacingOccurrences(of: "：", with: "").replacingOccurrences(of: ":", with: "")
                            kv[k] = cells[i + 1]
                            i += 2
                        }
                    }
                }
            }
        }
        let schedule = (try? doc.select("table#paperContent").text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !kv.isEmpty || !schedule.isEmpty else { return nil }
        return TyglExamInfo(
            currentTerm: kv["当前学期"] ?? "",
            peClass: kv["体育班"] ?? "",
            remainingAttempts: kv["剩余答题次数"] ?? "",
            highestScore: kv["最高考试成绩"] ?? "",
            notice: kv["通知公告"] ?? "",
            scheduleText: schedule
        )
    }

    // MARK: - Helpers

    private static func parseQuartet(
        _ q: [String],
        items: inout [TyglFitnessItem],
        bonusScore: inout String,
        bonusReason: inout String
    ) {
        guard q.count == 4 else { return }
        let name = q[0]
        let val = q[1]
        let score = q[2]
        let grade = q[3]
        guard !name.isEmpty, name != "项目", !val.contains("无需测试") else { return }
        if name.contains("加分") {
            bonusScore = val
            bonusReason = grade.isEmpty ? score : grade
            return
        }
        if !val.isEmpty || !score.isEmpty {
            items.append(TyglFitnessItem(name: name, rawValue: val, score: score, grade: grade))
        }
    }

    private static func cleanHeader(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
