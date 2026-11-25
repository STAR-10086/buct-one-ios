import BuctModel
import BuctNetwork
import Foundation
import SwiftSoup

public struct GmisSessionExpiredError: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String = "研究生系统会话已过期，请重新登录") {
        self.message = message
    }
    public var errorDescription: String? { message }
}

public enum GmisParser {
    private static let southsoftAesKey = Data("southsoft12345!#".utf8)

    public static func decodePayload(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }
        if let cipher = Data(base64Encoded: trimmed, options: .ignoreUnknownCharacters),
           let plain = try? BuctCrypto.aesECBDecrypt(ciphertext: cipher, key: southsoftAesKey),
           let decoded = String(data: plain, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           decoded.hasPrefix("{") || decoded.hasPrefix("[") {
            return decoded
        }
        return trimmed
    }

    public static func extractPublicKeyPEM(fromLoginHtml html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let cand1 = (try? doc.select("#pubkey").first()?.attr("value")) ?? ""
        if !cand1.isEmpty { return cand1 }
        let cand2 = (try? doc.select("input[name=pubkey]").first()?.attr("value")) ?? ""
        return cand2.isEmpty ? nil : cand2
    }

    public static func parseStudentCardInfo(rawPayload: String, fallbackId: String) -> (name: String, studentId: String)? {
        let jsonStr = decodePayload(rawPayload)
        guard let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let rows: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            rows = arr
        } else if let dict = root as? [String: Any] {
            rows = (dict["data"] as? [[String: Any]])
                ?? (dict["rows"] as? [[String: Any]])
                ?? (dict["list"] as? [[String: Any]])
                ?? []
        } else {
            rows = []
        }
        guard let first = rows.first else { return nil }
        let name = (first["xm"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let xh = (first["xh"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? fallbackId
        guard !name.isEmpty || !xh.isEmpty else { return nil }
        return (name.isEmpty ? xh : name, xh)
    }

    public static func parseTerms(rawPayload: String) -> [AcademicTerm] {
        let jsonStr = decodePayload(rawPayload)
        guard let data = jsonStr.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let rows: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            rows = arr
        } else if let dict = root as? [String: Any] {
            rows = (dict["data"] as? [[String: Any]])
                ?? (dict["rows"] as? [[String: Any]])
                ?? (dict["list"] as? [[String: Any]])
                ?? []
        } else {
            rows = []
        }

        var selectedTerms: [AcademicTerm] = []
        var otherTerms: [AcademicTerm] = []

        for row in rows {
            let termcode = (row["termcode"] as? String) ?? (row["termcode"] as? NSNumber)?.stringValue ?? ""
            let termname = (row["termname"] as? String) ?? ""
            guard !termcode.isEmpty else { continue }

            var year = Calendar.current.component(.year, from: Date())
            if let regex = try? NSRegularExpression(pattern: #"(\d{4})\s*-\s*(\d{4})"#),
               let m = regex.firstMatch(in: termname, range: NSRange(termname.startIndex..<termname.endIndex, in: termname)),
               let r = Range(m.range(at: 1), in: termname),
               let parsedYear = Int(termname[r]) {
                year = parsedYear
            }
            let sem: Int
            if termname.contains("秋") {
                sem = 1
            } else if termname.contains("春") {
                sem = 2
            } else {
                sem = 3
            }
            let term = AcademicTerm(year: year, semester: sem, serverCode: termcode)
            let isSelected = (row["selected"] as? Bool) == true || "\(row["selected"] ?? "")" == "true"
            if isSelected {
                selectedTerms.append(term)
            } else {
                otherTerms.append(term)
            }
        }
        return selectedTerms + otherTerms
    }

    public static func parseSchedule(rawPayload: String) -> [ScheduleCourse] {
        let jsonStr = decodePayload(rawPayload)
        guard let data = jsonStr.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        let rows = (dict["rows"] as? [[String: Any]]) ?? (dict["data"] as? [[String: Any]]) ?? []
        var rawEntries: [ScheduleCourse] = []
        var colorMap: [String: Int] = [:]

        for row in rows {
            let mc = (row["mc"] as? String) ?? ""
            guard let periodMatch = mc.range(of: #"\d+"#, options: .regularExpression),
                  let period = Int(mc[periodMatch]), (1...12).contains(period) else {
                continue
            }

            for day in 1...7 {
                guard let cell = row["z\(day)"] as? String else { continue }
                let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { continue }

                let lines = parseCellLines(trimmed)
                for line in lines {
                    let parsed = parseCourseLine(line)
                    let weeks = ScheduleWeeks.parse(parsed.weeksText)
                    let colorIdx: Int
                    if let existing = colorMap[parsed.name] {
                        colorIdx = existing
                    } else {
                        colorIdx = abs(parsed.name.hashValue) % 12
                        colorMap[parsed.name] = colorIdx
                    }
                    rawEntries.append(
                        ScheduleCourse(
                            id: "\(day)-\(period)-\(parsed.name)-\(rawEntries.count)",
                            name: parsed.name,
                            teacher: parsed.teacher,
                            location: parsed.location,
                            dayOfWeek: day,
                            startPeriod: period,
                            endPeriod: period,
                            weeksText: parsed.weeksText,
                            weeks: weeks.isEmpty ? Array(1...18) : weeks,
                            isCustom: false,
                            colorIndex: colorIdx
                        )
                    )
                }
            }
        }
        return mergeAdjacentPeriods(rawEntries)
    }

    public static func parseGrades(rawPayload: String, currentTerm: AcademicTerm) -> OverallAcademicBundle {
        let jsonStr = decodePayload(rawPayload)
        guard let data = jsonStr.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return OverallAcademicBundle(grades: [])
        }

        let lists: [(String, [[String: Any]])] = [
            ("学位课", (dict["xwklist"] as? [[String: Any]]) ?? []),
            ("非学位课", (dict["fxwklist"] as? [[String: Any]]) ?? []),
            ("环节", (dict["hjcjlist"] as? [[String: Any]]) ?? [])
        ]

        var items: [GradeItem] = []
        for (typeLabel, rows) in lists {
            for (idx, row) in rows.enumerated() {
                let name = ((row["kcmc"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let score = ((row["cj"] as? String) ?? "\(row["cj"] ?? "--")").trimmingCharacters(in: .whitespacesAndNewlines)
                let numericScore = ((row["cjfs"] as? String) ?? "\(row["cjfs"] ?? "")").trimmingCharacters(in: .whitespacesAndNewlines)
                let credits = Double("\(row["kcxf"] ?? "0")") ?? 0
                let code = ((row["kcbh"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let teacher = ((row["rkjs"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                var detailParts: [String] = []
                if !numericScore.isEmpty && numericScore != "null" && numericScore != score {
                    detailParts.append("百分制: \(numericScore)")
                }
                if !teacher.isEmpty && teacher != "null" {
                    detailParts.append("任课教师: \(teacher)")
                }

                let point = BuctGpaScale.gradePointFromScore(score, numericFallback: numericScore)
                items.append(
                    GradeItem(
                        id: "gmis-\(typeLabel)-\(code)-\(idx)",
                        courseCode: code,
                        courseName: name,
                        score: score,
                        credits: credits,
                        serverGpa: point,
                        courseType: typeLabel,
                        year: currentTerm.xnm,
                        term: currentTerm.xqm,
                        examNature: "正常考试",
                        detail: detailParts.joined(separator: " | ")
                    )
                )
            }
        }

        let xftjObj: [String: Any]?
        if let obj = dict["xftj"] as? [String: Any] {
            xftjObj = obj
        } else if let arr = dict["xftj"] as? [[String: Any]] {
            xftjObj = arr.first
        } else {
            xftjObj = nil
        }

        let officialGpa = xftjObj.flatMap { Double("\($0["zfgpa"] ?? "")") }
        let officialCredits = xftjObj.flatMap { Double("\($0["yxzxf"] ?? "")") } ?? Double("\(dict["hjzxf"] ?? "")")

        return OverallAcademicBundle(
            grades: items,
            summary: OverallGradeSummary(
                officialGpa: officialGpa,
                officialCredits: officialCredits,
                officialCourseCount: items.count
            ),
            curriculumNodes: []
        )
    }

    private static func parseCellLines(_ html: String) -> [String] {
        let brNormalized = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        let stripped = brNormalized
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        return stripped
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.lowercased() != "null" }
    }

    private static func parseCourseLine(_ line: String) -> (name: String, weeksText: String, teacher: String, location: String) {
        let fullPattern = #"^(.+?)\s*\[([^\]]+)\]\s*(.*?)\s*\[([^\]]+)\]\s*$"#
        if let regex = try? NSRegularExpression(pattern: fullPattern),
           let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           m.numberOfRanges >= 5 {
            func g(_ i: Int) -> String {
                Range(m.range(at: i), in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            }
            return (g(1), g(2), g(3), g(4))
        }
        let partialPattern = #"^(.+?)\s*\[([^\]]+)\]\s*(.*)$"#
        if let regex = try? NSRegularExpression(pattern: partialPattern),
           let m = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           m.numberOfRanges >= 4 {
            func g(_ i: Int) -> String {
                Range(m.range(at: i), in: line).map { String(line[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            }
            return (g(1), g(2), g(3), "")
        }
        return (line, "1-20周", "", "")
    }

    private static func mergeAdjacentPeriods(_ entries: [ScheduleCourse]) -> [ScheduleCourse] {
        let sorted = entries.sorted {
            if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
            return $0.startPeriod < $1.startPeriod
        }
        var merged: [ScheduleCourse] = []
        for item in sorted {
            if let last = merged.last,
               last.dayOfWeek == item.dayOfWeek,
               last.name == item.name,
               last.teacher == item.teacher,
               last.location == item.location,
               last.weeksText == item.weeksText,
               item.startPeriod <= last.endPeriod + 1 {
                merged[merged.count - 1].endPeriod = max(last.endPeriod, item.endPeriod)
            } else {
                merged.append(item)
            }
        }
        return merged
    }
}
