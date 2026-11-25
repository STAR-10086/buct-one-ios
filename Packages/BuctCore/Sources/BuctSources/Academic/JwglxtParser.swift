import BuctModel
import BuctNetwork
import Foundation
import SwiftSoup

public struct JwglxtSessionExpiredError: Error, LocalizedError, Sendable {
    public let statusCode: Int
    public let message: String

    public init(statusCode: Int = 901, message: String = "教务系统登录已过期，请重新登录") {
        self.statusCode = statusCode
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct JwglxtOverallIndexMetadata: Sendable, Equatable {
    public let summary: OverallGradeSummary
    public let xhId: String
    public let cjlrxn: String
    public let cjlrxq: String
    public let nodeIds: [String]
    public let nodes: [CurriculumNode]
}

public enum JwglxtParser {
    public static let parserVersion = 2

    public static func isSessionExpired(statusCode: Int, url: URL?, body: String) -> Bool {
        if [401, 403, 901].contains(statusCode) { return true }
        if let urlStr = url?.absoluteString.lowercased(),
           urlStr.contains("login") || urlStr.contains("slogin") || urlStr.contains("cas/") || urlStr.contains("oauth") {
            return true
        }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if trimmed.contains("notLogin") || trimmed.contains("sessionExpired") || trimmed.contains("未登录") {
                return true
            }
            if let obj = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? [String: Any] {
                let code = stringValue(obj["code"])
                let status = stringValue(obj["status"])
                if ["901", "401", "403"].contains(code) || ["901", "401", "403"].contains(status) {
                    return true
                }
            }
            return false
        }
        let lower = trimmed.lowercased()
        if lower.contains("id=\"pwd\"") || (lower.contains("name=\"mm\"") && lower.contains("name=\"yhm\"")) ||
            trimmed.contains("用户登录") || lower.contains("slogin.html") || trimmed.contains("notlogin") {
            return true
        }
        return false
    }

    public static func parseStudentProfile(html: String, fallbackId: String = "") -> (name: String, studentId: String)? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let nameCandidates = [
            try? doc.select("input[name=xm]").first()?.attr("value"),
            try? doc.select("h4.media-heading").first()?.text().replacingOccurrences(of: "学生", with: ""),
            try? doc.select("span[name=xm], div[name=xm], .user-name, .student-name, #xhxm").first()?.text()
                .replacingOccurrences(of: "同学", with: "")
                .replacingOccurrences(of: "学生", with: "")
        ]
        let name = nameCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""

        let idCandidates = [
            try? doc.select("input[name=xh]").first()?.attr("value"),
            try? doc.select("span[name=xh], div[name=xh], .student-id, #xh, .user-id").first()?.text(),
            try? doc.select("#sessionUserKey").first()?.attr("value")
        ]
        let sid = idCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? fallbackId

        guard !name.isEmpty || !sid.isEmpty else { return nil }
        return (name.isEmpty ? sid : name, sid)
    }

    public static func parseSchedule(jsonString: String) throws -> [ScheduleCourse] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            throw NSError(domain: "JwglxtParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "课表响应格式异常"])
        }

        let list: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            list = arr
        } else if let dict = root as? [String: Any] {
            if let success = dict["success"] as? Bool, !success {
                throw NSError(domain: "JwglxtParser", code: -2, userInfo: [NSLocalizedDescriptionKey: stringValue(dict["msg"], default: "获取课表失败")])
            }
            if let kbList = dict["kbList"] as? [[String: Any]] {
                list = kbList
            } else if let dataDict = dict["data"] as? [String: Any], let kbList = dataDict["kbList"] as? [[String: Any]] {
                list = kbList
            } else if let dataArr = dict["data"] as? [[String: Any]] {
                list = dataArr
            } else {
                list = []
            }
        } else {
            list = []
        }

        var courses: [ScheduleCourse] = []
        var seenIds = Set<String>()
        var colorMap: [String: Int] = [:]

        for item in list {
            let name = firstNonEmpty(item, keys: ["kcmc", "KCMC"]) ?? "未知课程"
            let teacher = firstNonEmpty(item, keys: ["xm", "XM"]) ?? ""
            let campus = firstNonEmpty(item, keys: ["xqmc", "cdxqmc"]) ?? ""
            let building = firstNonEmpty(item, keys: ["cdlmc", "jxlmc"]) ?? ""
            let room = firstNonEmpty(item, keys: ["cdmc", "CDMC"]) ?? ""
            let location: String
            if !campus.isEmpty && !room.isEmpty {
                location = "\(campus) \(room)"
            } else if !building.isEmpty && !room.isEmpty {
                location = "\(building) \(room)"
            } else if !room.isEmpty {
                location = room
            } else {
                location = firstNonEmpty(item, keys: ["jxcdmc", "JXCDMC"]) ?? ""
            }

            let day = Int(firstNonEmpty(item, keys: ["xqj", "XQJ"]) ?? "") ?? 1
            guard (1...7).contains(day) else { continue }

            let weeksText = firstNonEmpty(item, keys: ["zcd", "ZCD"]) ?? "1-16周"
            let weeks = ScheduleWeeks.parse(weeksText)

            let jcsRaw = (firstNonEmpty(item, keys: ["jcs", "JCS", "jcor", "JCOR"]) ?? "1-2")
                .replacingOccurrences(of: ",", with: "-")
            let jcsParts = jcsRaw.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            let startPeriod = max(1, jcsParts.first ?? 1)
            let endPeriod = min(12, max(startPeriod, jcsParts.last ?? startPeriod))

            let sourceId = firstNonEmpty(item, keys: ["schedule_source_id", "kcb_id", "kb_id", "jxb_id", "jx0404id", "kch_id"]) ?? ""
            let canonicalWeeks = weeks.map(String.init).joined(separator: ",")
            let rawIdentity: String
            if !sourceId.isEmpty {
                rawIdentity = [sourceId, "\(day)", "\(startPeriod)", "\(endPeriod)", canonicalWeeks].joined(separator: "\u{001f}")
            } else {
                rawIdentity = [name, teacher, location, "\(day)", "\(startPeriod)", "\(endPeriod)", canonicalWeeks].joined(separator: "\u{001f}")
            }
            let stableId = String(BuctCrypto.sha256Hex(rawIdentity.precomposedStringWithCompatibilityMapping).prefix(32))
            guard seenIds.insert(stableId).inserted else { continue }

            let colorIdx: Int
            if let existing = colorMap[name] {
                colorIdx = existing
            } else {
                colorIdx = abs(name.hashValue) % 12
                colorMap[name] = colorIdx
            }

            courses.append(
                ScheduleCourse(
                    id: stableId,
                    sourceId: sourceId,
                    name: name,
                    teacher: teacher,
                    location: location,
                    dayOfWeek: day,
                    startPeriod: startPeriod,
                    endPeriod: endPeriod,
                    weeksText: weeksText,
                    weeks: weeks.isEmpty ? Array(1...16) : weeks,
                    isCustom: false,
                    colorIndex: colorIdx
                )
            )
        }
        return courses
    }

    public static func parseGradesJson(_ jsonString: String) -> [GradeItem] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let rows: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            rows = arr
        } else if let dict = root as? [String: Any], let items = dict["items"] as? [[String: Any]] {
            rows = items
        } else {
            rows = []
        }

        var grouped: [String: [String: Any]] = [:]
        var orderedKeys: [String] = []
        var componentDetailsByKey: [String: [String]] = [:]

        for row in rows {
            let name = firstNonEmpty(row, keys: ["kcmc", "KCMC"]) ?? ""
            guard !name.isEmpty else { continue }
            let jxbId = firstNonEmpty(row, keys: ["jxb_id", "JXB_ID", "kch_id", "KCH_ID", "kch", "KCH"]) ?? ""
            let groupKey = "\(name)|\(jxbId)"
            if grouped[groupKey] == nil {
                grouped[groupKey] = row
                orderedKeys.append(groupKey)
            }
            if let compName = firstNonEmpty(row, keys: ["xmblmc", "xmlInc"]),
               let compScore = firstNonEmpty(row, keys: ["xmcj", "xmoJ"]),
               compName != "总评", compScore != "null" {
                let ratio = firstNonEmpty(row, keys: ["xmbl"])
                let text = ratio.map { "\(compName)(\($0)): \(compScore)" } ?? "\(compName): \(compScore)"
                componentDetailsByKey[groupKey, default: []].append(text)
            }
        }

        var items: [GradeItem] = []
        for key in orderedKeys {
            guard let row = grouped[key] else { continue }
            let name = firstNonEmpty(row, keys: ["kcmc", "KCMC"]) ?? ""
            let score = firstNonEmpty(row, keys: ["MAXCJ", "maxcj", "cj", "CJ"]) ?? "--"
            let credits = Double(firstNonEmpty(row, keys: ["xf", "XF"]) ?? "0") ?? 0
            let jd = firstNonEmpty(row, keys: ["jd", "JD"]).flatMap(Double.init)
            let courseType = firstNonEmpty(row, keys: ["kcxzmc", "KCXZMC", "kclbmc", "KCLBMC"]) ?? ""
            let year = firstNonEmpty(row, keys: ["xnm", "XNM"]) ?? ""
            let term = firstNonEmpty(row, keys: ["xqm", "XQM"]) ?? ""
            let college = firstNonEmpty(row, keys: ["kkbmmc", "KKBMMC"]) ?? ""
            let courseCode = firstNonEmpty(row, keys: ["kch", "KCH", "KCH_ID", "kch_id"]) ?? ""
            let teachingClass = firstNonEmpty(row, keys: ["jxbmc", "JXBMC"]) ?? ""
            let jxbId = firstNonEmpty(row, keys: ["jxb_id", "JXB_ID", "job_id", "JOB_ID"]) ?? ""

            var examNature = firstNonEmpty(row, keys: ["ksxz", "KSXZ"]) ?? ""
            if examNature.isEmpty {
                let cxcj = firstNonEmpty(row, keys: ["CXCJ", "cxcj"]) ?? ""
                let bkcj = firstNonEmpty(row, keys: ["BKCJ", "bkcj"]) ?? ""
                if !cxcj.isEmpty && cxcj == score {
                    examNature = "重修"
                } else if !bkcj.isEmpty && bkcj == score {
                    examNature = "补考"
                } else if score != "--" && !score.isEmpty {
                    examNature = "正常考试"
                }
            }

            var detailParts = componentDetailsByKey[key] ?? []
            if detailParts.isEmpty {
                let inlineFields: [(String, String, String)] = [
                    ("平时", "pscj", "pscjbl"),
                    ("期中", "qzcj", "qzcjbl"),
                    ("期末", "qmcj", "qmcjbl"),
                    ("实验", "sycj", "sycjbl"),
                    ("实践", "sjcj", "sjcjbl")
                ]
                for (label, scoreKey, ratioKey) in inlineFields {
                    if let s = firstNonEmpty(row, keys: [scoreKey, scoreKey.uppercased()]) {
                        if let r = firstNonEmpty(row, keys: [ratioKey, ratioKey.uppercased()]) {
                            detailParts.append("\(label)(\(r)): \(s)")
                        } else {
                            detailParts.append("\(label): \(s)")
                        }
                    }
                }
            }

            items.append(
                GradeItem(
                    id: "\(year)-\(term)-\(courseCode)-\(name)-\(jxbId)",
                    courseCode: courseCode,
                    courseName: name,
                    score: score,
                    credits: credits,
                    serverGpa: jd,
                    courseType: courseType,
                    year: year,
                    term: term,
                    college: college,
                    teachingClass: teachingClass,
                    jxbId: jxbId,
                    examNature: examNature,
                    detail: detailParts.joined(separator: " | ")
                )
            )
        }
        return items
    }

    public static func parseGradeComponentDetail(jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = dict["items"] as? [[String: Any]] else {
            return ""
        }
        var parts: [String] = []
        for item in items {
            let name = firstNonEmpty(item, keys: ["xmlInc", "xmblmc"]) ?? ""
            let score = firstNonEmpty(item, keys: ["xmoJ", "xmcj"]) ?? ""
            guard !name.isEmpty, name != "总评", !score.isEmpty, score != "null" else { continue }
            parts.append("\(name): \(score)")
        }
        return parts.joined(separator: " | ")
    }

    public static func parseOverallIndexHtml(_ html: String) -> JwglxtOverallIndexMetadata {
        let gpaVal = firstRegexCapture(html, pattern: #"\(GPA\)[：:]\s*<font[^>]*>([\d.]+)</font>"#).flatMap(Double.init)
            ?? firstRegexCapture(html, pattern: #"<font[^>]*style=[^>]*color[^>]*>\s*(\d+\.\d{1,2})\s*</font>"#).flatMap(Double.init)
        let creditsVal = firstRegexCapture(html, pattern: #"(?:已修|获得|总)\s*学分[：:]\s*([\d.]+)"#).flatMap(Double.init)
        let countVal = firstRegexCapture(html, pattern: #"(?:课程|门数)[：:]\s*(\d+)"#).flatMap(Int.init)

        let doc = try? SwiftSoup.parse(html)
        let xhId = (try? doc?.select("input[name=xh_id]").first()?.attr("value")) ?? ""
        let cjlrxn = (try? doc?.select("input[name=cjlrxn]").first()?.attr("value")) ?? ""
        let cjlrxq = (try? doc?.select("input[name=cjlrxq]").first()?.attr("value")) ?? ""

        var nodeIds: [String] = []
        var seenIds = Set<String>()
        if let regex = try? NSRegularExpression(pattern: #"xfyqjd_id=["']?([A-Fa-f0-9]{20,})["']?"#) {
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for m in regex.matches(in: html, range: nsRange) {
                if let r = Range(m.range(at: 1), in: html) {
                    let val = String(html[r])
                    if seenIds.insert(val).inserted { nodeIds.append(val) }
                }
            }
        }
        if let doc, let elements = try? doc.select("input[name=xfyqjd_id], select[name=xfyqjd_id] option") {
            for el in elements {
                let val = (try? el.attr("value")) ?? ""
                if val.count > 20 && seenIds.insert(val).inserted {
                    nodeIds.append(val)
                }
            }
        }

        var nodes: [CurriculumNode] = []
        var seenNodeIds = Set<String>()
        let nodePattern = #"fxfyqjd_id='([^']*)'[^>]*>[\s\S]{0,240}?xfyqjd_id='([A-Fa-f0-9]+)'\s+jdkcsx='([^']*)'\s+leaf='([^']*)'\s+sfmjd='([^']*)'\s*><p class='title1'\s+id='p[A-Fa-f0-9]+'\s+yxxf='([^']*)'\s+yqzdxf='([^']*)'\s+sftg='([^']*)'[^>]*>"\s*\+\s*\r?\n\s*"([^"&]+)"#
        if let regex = try? NSRegularExpression(pattern: nodePattern) {
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            for m in regex.matches(in: html, range: nsRange) where m.numberOfRanges >= 10 {
                func cap(_ i: Int) -> String {
                    Range(m.range(at: i), in: html).map { String(html[$0]) } ?? ""
                }
                let id = cap(2).trimmingCharacters(in: .whitespacesAndNewlines)
                let parentId = cap(1).trimmingCharacters(in: .whitespacesAndNewlines)
                let name = cap(9).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !name.isEmpty, seenNodeIds.insert(id).inserted else { continue }
                let node = CurriculumNode(
                    id: id,
                    parentId: parentId,
                    name: name,
                    isLeaf: cap(5) == "1",
                    earnedCredits: Double(cap(6)) ?? 0,
                    requiredCredits: Double(cap(7)) ?? 0,
                    passed: cap(8) == "1",
                    courses: []
                )
                nodes.append(node)
                if seenIds.insert(node.id).inserted {
                    nodeIds.append(node.id)
                }
            }
        }

        return JwglxtOverallIndexMetadata(
            summary: OverallGradeSummary(officialGpa: gpaVal, officialCredits: creditsVal, officialCourseCount: countVal),
            xhId: xhId,
            cjlrxn: cjlrxn,
            cjlrxq: cjlrxq,
            nodeIds: nodeIds,
            nodes: nodes
        )
    }

    public static func parseCurriculumCoursesJson(_ jsonString: String) -> [CurriculumCourse] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let rows: [[String: Any]]
        if let arr = root as? [[String: Any]] {
            rows = arr
        } else if let dict = root as? [String: Any], let items = dict["items"] as? [[String: Any]] {
            rows = items
        } else {
            rows = []
        }

        var seen = Set<String>()
        var result: [CurriculumCourse] = []
        for row in rows {
            guard let name = firstNonEmpty(row, keys: ["KCMC", "kcmc"]) else { continue }
            let code = firstNonEmpty(row, keys: ["KCH", "kch", "KCH_ID", "kch_id"]) ?? ""
            let key = "\(code)|\(name)"
            guard seen.insert(key).inserted else { continue }
            let credits = Double(firstNonEmpty(row, keys: ["XF", "xf"]) ?? "0") ?? 0
            let status = firstNonEmpty(row, keys: ["XDZT", "xdzt"]) ?? "3"
            let grade = firstNonEmpty(row, keys: ["MAXCJ", "CJ", "cj"]) ?? ""
            let sugYear = firstNonEmpty(row, keys: ["JYXDXNMC", "XNMC"]) ?? ""
            let sugTerm = firstNonEmpty(row, keys: ["JYXDXQMC", "XQMMC"]) ?? ""
            let cat = firstNonEmpty(row, keys: ["KCXZMC", "KCLBMC"]) ?? ""
            result.append(
                CurriculumCourse(
                    id: code.isEmpty ? name : key,
                    courseCode: code,
                    courseName: name,
                    credits: credits,
                    studyStatus: status,
                    grade: grade,
                    suggestedYear: sugYear,
                    suggestedTerm: sugTerm,
                    category: cat
                )
            )
        }
        return result
    }

    public static func parseExamChannelA(jsonString: String, wantXnmc: String, wantXq: String) -> [ExamItem] {
        guard let data = jsonString.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        let array = (dict["items"] as? [[String: Any]])
            ?? (dict["dwList"] as? [[String: Any]])
            ?? (dict["list"] as? [[String: Any]])
            ?? (dict["rows"] as? [[String: Any]])
            ?? (dict["data"] as? [[String: Any]])
            ?? []

        return array.enumerated().compactMap { idx, row in
            let rowXnmc = firstNonEmpty(row, keys: ["xnmc", "XNMC"]) ?? ""
            let rowXq = firstNonEmpty(row, keys: ["xq", "XQ"]) ?? ""
            if !rowXnmc.isEmpty && (rowXnmc != wantXnmc || rowXq != wantXq) {
                return nil
            }
            guard let courseName = firstNonEmpty(row, keys: ["kcmc", "KCMC"]) else { return nil }
            let examTime = firstNonEmpty(row, keys: ["kssj", "KSSJ"]) ?? ""
            return ExamItem(
                id: "exa-\(idx)-\(courseName)-\(examTime)",
                courseName: courseName,
                examTime: examTime
            )
        }
    }

    public static func parseExamChannelB(jsonString: String) -> [ExamItem] {
        guard let data = jsonString.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = dict["items"] as? [[String: Any]] else {
            return []
        }
        return items.enumerated().compactMap { idx, row in
            guard let courseName = firstNonEmpty(row, keys: ["kcmc", "KCMC"]) else { return nil }
            let examTime = firstNonEmpty(row, keys: ["kssj", "KSSJ"]) ?? ""
            let location = firstNonEmpty(row, keys: ["cdmc", "CDMC"]) ?? ""
            let seat = firstNonEmpty(row, keys: ["zwh", "ZWH"]) ?? ""
            let examName = firstNonEmpty(row, keys: ["ksmc", "KSMC"]) ?? ""
            let teacher = firstNonEmpty(row, keys: ["jsxx", "JSXX"]) ?? ""
            return ExamItem(
                id: "exb-\(idx)-\(courseName)-\(examTime)",
                courseName: courseName,
                examTime: examTime,
                location: location,
                seatNumber: seat,
                examName: examName,
                teacher: teacher
            )
        }
    }

    public static func mergeExams(channelA: [ExamItem], channelB: [ExamItem]) -> [ExamItem] {
        var remainingB = channelB
        var merged: [ExamItem] = []

        for a in channelA {
            if let exactIdx = remainingB.firstIndex(where: { $0.courseName == a.courseName && $0.examTime == a.examTime }) {
                let b = remainingB.remove(at: exactIdx)
                merged.append(combineExam(a, b))
            } else {
                let aCount = channelA.filter { $0.courseName == a.courseName }.count
                let bMatches = remainingB.indices.filter { remainingB[$0].courseName == a.courseName }
                if aCount == 1 && bMatches.count == 1, let bIdx = bMatches.first {
                    let b = remainingB.remove(at: bIdx)
                    merged.append(combineExam(a, b))
                } else {
                    merged.append(a)
                }
            }
        }
        merged.append(contentsOf: remainingB)

        var seen = Set<String>()
        let deduped = merged.filter { item in
            let key = "\(item.courseName)|\(item.examTime)|\(item.location)|\(item.examName)"
            return seen.insert(key).inserted
        }
        return deduped.sorted { lhs, rhs in
            if lhs.examTime.isEmpty != rhs.examTime.isEmpty {
                return !lhs.examTime.isEmpty
            }
            return lhs.examTime < rhs.examTime
        }
    }

    private static func combineExam(_ a: ExamItem, _ b: ExamItem) -> ExamItem {
        ExamItem(
            id: b.id.isEmpty ? a.id : b.id,
            courseName: a.courseName,
            examTime: b.examTime.isEmpty ? a.examTime : b.examTime,
            location: b.location.isEmpty ? a.location : b.location,
            seatNumber: b.seatNumber.isEmpty ? a.seatNumber : b.seatNumber,
            examName: b.examName.isEmpty ? a.examName : b.examName,
            teacher: b.teacher.isEmpty ? a.teacher : b.teacher
        )
    }

    public static func parseEmptyClassrooms(jsonString: String) -> [EmptyClassroom] {
        guard let data = jsonString.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = dict["items"] as? [[String: Any]] else {
            return []
        }

        var results: [EmptyClassroom] = []
        var seen = Set<String>()

        for row in items {
            if firstNonEmpty(row, keys: ["sfybyy", "SFYBYY"]) == "1" { continue }
            guard let name = firstNonEmpty(row, keys: ["cdmc", "CDMC"]) else { continue }
            let code = firstNonEmpty(row, keys: ["cdbh", "CDBH"]) ?? ""
            if name.range(of: #"^北\d.*"#, options: .regularExpression) != nil ||
                code.range(of: #"^北\d.*"#, options: .regularExpression) != nil {
                continue
            }

            let id = firstNonEmpty(row, keys: ["cd_id", "CD_ID"]) ?? "\(code)|\(name)"
            guard seen.insert(id).inserted else { continue }

            let campus = firstNonEmpty(row, keys: ["xqmc", "XQMC"]) ?? ""
            let building = firstNonEmpty(row, keys: ["jxlmc", "JXLMC"]) ?? ""
            let floor = firstNonEmpty(row, keys: ["lch", "LCH"]) ?? ""
            let type = firstNonEmpty(row, keys: ["cdlbmc", "CDLBMC"]) ?? ""
            let seats = Int(firstNonEmpty(row, keys: ["zws", "ZWS"]) ?? "") ?? 0
            let examSeats = Int(firstNonEmpty(row, keys: ["kszws1", "KSZWS1"]) ?? "") ?? 0

            results.append(
                EmptyClassroom(
                    id: id,
                    code: code,
                    name: name,
                    campus: campus,
                    building: building,
                    floor: floor,
                    type: type,
                    seats: seats,
                    examSeats: examSeats
                )
            )
        }

        return results.sorted { a, b in
            let ca = campusRank(a.campus)
            let cb = campusRank(b.campus)
            if ca != cb { return ca < cb }
            let ba = buildingRank(a.building)
            let bb = buildingRank(b.building)
            if ba != bb { return ba < bb }
            if a.building != b.building { return a.building < b.building }
            return a.code < b.code
        }
    }

    private static func campusRank(_ campus: String) -> Int {
        if campus.contains("北区") { return 0 }
        if campus.contains("东区") { return 1 }
        if campus.contains("西区") { return 2 }
        return 3
    }

    private static func buildingRank(_ building: String) -> Int {
        if building.contains("第一教学楼") || building.contains("一教") || building.contains("教一") { return 0 }
        if building.contains("第二教学楼") || building.contains("二教") || building.contains("教二") { return 1 }
        return 2
    }

    private static func firstNonEmpty(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let val = dict[key] {
                let s = stringValue(val).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty && s != "null" {
                    return s
                }
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?, default fallback: String = "") -> String {
        guard let value, !(value is NSNull) else { return fallback }
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return String(describing: value)
    }

    private static func firstRegexCapture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
}
