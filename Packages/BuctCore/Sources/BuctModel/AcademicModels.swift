import Foundation

public enum AcademicSystemType: String, Codable, Sendable, CaseIterable {
    case undergradJwglxt = "buct"
    case graduateGmis = "buct_yjs"
    case demo = "demo"

    public var displayName: String {
        switch self {
        case .undergradJwglxt: return "本科生教务 (jwglxt)"
        case .graduateGmis: return "研究生教务 (GMIS)"
        case .demo: return "演示模式"
        }
    }

    public var shortBadge: String {
        switch self {
        case .undergradJwglxt: return "本科"
        case .graduateGmis: return "研究生"
        case .demo: return "演示"
        }
    }
}

public struct UserAccountProfile: Codable, Sendable, Equatable {
    public let studentId: String
    public let studentName: String
    public let systemType: AcademicSystemType

    public var isDemoMode: Bool { systemType == .demo }

    public var accountKey: String {
        "\(systemType.rawValue)::\(studentId)"
    }

    public var maskedStudentId: String {
        guard studentId.count >= 6 else { return studentId }
        return "\(studentId.prefix(4))****\(studentId.suffix(2))"
    }

    public init(studentId: String, studentName: String, systemType: AcademicSystemType) {
        self.studentId = studentId
        self.studentName = studentName
        self.systemType = systemType
    }
}

public struct AcademicTerm: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let year: Int
    public let semester: Int
    public let serverCode: String?

    public init(year: Int, semester: Int, serverCode: String? = nil) {
        self.year = year
        self.semester = semester
        self.id = "\(year)-\(year + 1)-\(semester)"
        self.serverCode = serverCode
    }

    public init?(termId: String, serverCode: String? = nil) {
        let parts = termId.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let s = Int(parts[2]),
              (1...3).contains(s) else {
            return nil
        }
        self.init(year: y, semester: s, serverCode: serverCode)
    }

    public var xnm: String { "\(year)" }

    public var xqm: String {
        switch semester {
        case 1: return "3"
        case 2: return "12"
        default: return "16"
        }
    }

    public var xqString: String { "\(semester)" }
    public var xnmcString: String { "\(year)-\(year + 1)" }

    public var displayName: String {
        let semLabel: String
        switch semester {
        case 1: semLabel = "第一学期"
        case 2: semLabel = "第二学期"
        default: semLabel = "小学期"
        }
        return "\(year)-\(year + 1) \(semLabel)"
    }

    public var shortLabel: String {
        let semLabel = semester == 1 ? "秋" : (semester == 2 ? "春" : "夏")
        return "\(year % 100)-\((year + 1) % 100) \(semLabel)"
    }

    public static func calendarDefault(now: Date = Date()) -> AcademicTerm {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        let comps = cal.dateComponents([.year, .month], from: now)
        let calYear = comps.year ?? 2026
        let month = comps.month ?? 9
        if month >= 8 {
            return AcademicTerm(year: calYear, semester: 1)
        } else if month < 2 {
            return AcademicTerm(year: calYear - 1, semester: 1)
        } else {
            return AcademicTerm(year: calYear - 1, semester: 2)
        }
    }

    public static func undergradPickerTerms(now: Date = Date()) -> [AcademicTerm] {
        let current = calendarDefault(now: now)
        var terms: [AcademicTerm] = []
        for y in stride(from: current.year + 1, through: current.year - 4, by: -1) {
            for s in 1...3 {
                terms.append(AcademicTerm(year: y, semester: s))
            }
        }
        return terms
    }
}

public struct BuctPeriodSlot: Sendable, Equatable {
    public let period: Int
    public let start: String
    public let end: String
}

public enum BuctTimeSlots {
    public static let periods: [BuctPeriodSlot] = [
        BuctPeriodSlot(period: 1, start: "08:00", end: "08:45"),
        BuctPeriodSlot(period: 2, start: "08:50", end: "09:35"),
        BuctPeriodSlot(period: 3, start: "09:45", end: "10:30"),
        BuctPeriodSlot(period: 4, start: "10:40", end: "11:25"),
        BuctPeriodSlot(period: 5, start: "11:30", end: "12:15"),
        BuctPeriodSlot(period: 6, start: "13:30", end: "14:15"),
        BuctPeriodSlot(period: 7, start: "14:20", end: "15:05"),
        BuctPeriodSlot(period: 8, start: "15:15", end: "16:00"),
        BuctPeriodSlot(period: 9, start: "16:05", end: "16:50"),
        BuctPeriodSlot(period: 10, start: "18:00", end: "18:45"),
        BuctPeriodSlot(period: 11, start: "18:50", end: "19:35"),
        BuctPeriodSlot(period: 12, start: "19:40", end: "20:25")
    ]

    public static func timeRangeText(startPeriod: Int, endPeriod: Int) -> String {
        let s = periods.first(where: { $0.period == startPeriod })?.start ?? "--:--"
        let e = periods.first(where: { $0.period == endPeriod })?.end ?? "--:--"
        return "\(s)-\(e)"
    }
}

public enum ScheduleWeeks {
    public static let maxWeek = 25

    public static func parse(_ raw: String) -> [Int] {
        let normalized = raw.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard !normalized.isEmpty else { return [] }

        let segments = normalized.split(whereSeparator: { $0 == "," || $0 == "、" || $0 == ";" || $0 == "，" })
        var result = Set<Int>()

        for rawSeg in segments {
            let seg = String(rawSeg)
            let isOdd = seg.contains("单")
            let isEven = seg.contains("双")
            if isOdd && isEven { continue }

            let cleaned = seg
                .replacingOccurrences(of: "[第周单双()（）]", with: "", options: .regularExpression)
                .replacingOccurrences(of: "[~—–至]", with: "-", options: .regularExpression)
            let bounds = cleaned.split(separator: "-")
            if bounds.count == 1, let single = Int(bounds[0]), (1...maxWeek).contains(single) {
                if (!isOdd && !isEven) || (isOdd && single % 2 == 1) || (isEven && single % 2 == 0) {
                    result.insert(single)
                }
            } else if bounds.count == 2,
                      let startRaw = Int(bounds[0]),
                      let endRaw = Int(bounds[1]) {
                let lo = max(1, min(startRaw, endRaw))
                let hi = min(maxWeek, max(startRaw, endRaw))
                if lo <= hi {
                    for w in lo...hi {
                        if (!isOdd && !isEven) || (isOdd && w % 2 == 1) || (isEven && w % 2 == 0) {
                            result.insert(w)
                        }
                    }
                }
            }
        }
        return result.sorted()
    }
}

public enum ScheduleDates {
    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private static var beijingCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return cal
    }

    public static func parseUTCDate(_ yyyyMMdd: String) -> Date? {
        let prefix = String(yyyyMMdd.prefix(10))
        let parts = prefix.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]) else {
            return nil
        }
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return utcCalendar.date(from: comps)
    }

    public static func formatUTCDate(_ date: Date) -> String {
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }

    public static func normalizeFirstWeekMonday(_ yyyyMMdd: String) -> String? {
        guard let date = parseUTCDate(yyyyMMdd) else { return nil }
        let weekday = utcCalendar.component(.weekday, from: date) // 1=Sun, 2=Mon..7=Sat
        let offsetFromMonday = (weekday + 5) % 7
        guard let monday = utcCalendar.date(byAdding: .day, value: -offsetFromMonday, to: date) else {
            return nil
        }
        return formatUTCDate(monday)
    }

    public static func defaultSemesterStartMonday(for term: AcademicTerm) -> String {
        let baseDateStr: String
        switch term.semester {
        case 1:
            baseDateStr = String(format: "%04d-09-01", term.year)
        case 2:
            baseDateStr = String(format: "%04d-03-01", term.year + 1)
        default:
            baseDateStr = String(format: "%04d-07-01", term.year + 1)
        }
        return normalizeFirstWeekMonday(baseDateStr) ?? baseDateStr
    }

    public static func weekAt(firstWeekMonday: String, now: Date = Date()) -> Int? {
        guard let mondayDate = parseUTCDate(firstWeekMonday) else { return nil }
        let bjComps = beijingCalendar.dateComponents([.year, .month, .day], from: now)
        guard let todayUTC = utcCalendar.date(from: bjComps) else { return nil }
        let days = Int(todayUTC.timeIntervalSince(mondayDate) / 86_400)
        guard days >= 0 else { return nil }
        let week = days / 7 + 1
        return (1...ScheduleWeeks.maxWeek).contains(week) ? week : nil
    }

    public static func todayDayOfWeek(now: Date = Date()) -> Int {
        let weekday = beijingCalendar.component(.weekday, from: now)
        return ((weekday + 5) % 7) + 1
    }

    public static func dateFor(firstWeekMonday: String, week: Int, dayOfWeek: Int) -> Date? {
        guard let monday = parseUTCDate(firstWeekMonday) else { return nil }
        let delta = (week - 1) * 7 + (dayOfWeek - 1)
        return utcCalendar.date(byAdding: .day, value: delta, to: monday)
    }

    public static func examWeekDayLabel(examTime: String, firstWeekMonday: String) -> String? {
        let prefix = String(examTime.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        guard let examDate = parseUTCDate(prefix),
              let mondayDate = parseUTCDate(firstWeekMonday) else {
            return nil
        }
        let days = Int(examDate.timeIntervalSince(mondayDate) / 86_400)
        guard days >= 0 else { return nil }
        let week = days / 7 + 1
        let dow = (days % 7) + 1
        let labels = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        guard (1...ScheduleWeeks.maxWeek).contains(week), (1...7).contains(dow) else { return nil }
        return "第\(week)周 \(labels[dow])"
    }
}

public struct ScheduleCourse: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceId: String
    public var name: String
    public var teacher: String
    public var location: String
    public var dayOfWeek: Int
    public var startPeriod: Int
    public var endPeriod: Int
    public var weeksText: String
    public var weeks: [Int]
    public var isCustom: Bool
    public var colorIndex: Int

    public init(
        id: String,
        sourceId: String = "",
        name: String,
        teacher: String = "",
        location: String = "",
        dayOfWeek: Int,
        startPeriod: Int,
        endPeriod: Int,
        weeksText: String,
        weeks: [Int],
        isCustom: Bool = false,
        colorIndex: Int = 0
    ) {
        self.id = id
        self.sourceId = sourceId
        self.name = name
        self.teacher = teacher
        self.location = location
        self.dayOfWeek = dayOfWeek
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weeksText = weeksText
        self.weeks = weeks
        self.isCustom = isCustom
        self.colorIndex = colorIndex
    }
}

public struct GradeItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseCode: String
    public let courseName: String
    public let score: String
    public let credits: Double
    public let serverGpa: Double?
    public let courseType: String
    public let year: String
    public let term: String
    public let college: String
    public let teachingClass: String
    public let jxbId: String
    public let examNature: String
    public var detail: String

    public init(
        id: String,
        courseCode: String = "",
        courseName: String,
        score: String,
        credits: Double,
        serverGpa: Double? = nil,
        courseType: String = "",
        year: String = "",
        term: String = "",
        college: String = "",
        teachingClass: String = "",
        jxbId: String = "",
        examNature: String = "",
        detail: String = ""
    ) {
        self.id = id
        self.courseCode = courseCode
        self.courseName = courseName
        self.score = score
        self.credits = credits
        self.serverGpa = serverGpa
        self.courseType = courseType
        self.year = year
        self.term = term
        self.college = college
        self.teachingClass = teachingClass
        self.jxbId = jxbId
        self.examNature = examNature
        self.detail = detail
    }
}

public struct OverallGradeSummary: Codable, Sendable, Equatable {
    public let officialGpa: Double?
    public let officialCredits: Double?
    public let officialCourseCount: Int?

    public init(officialGpa: Double? = nil, officialCredits: Double? = nil, officialCourseCount: Int? = nil) {
        self.officialGpa = officialGpa
        self.officialCredits = officialCredits
        self.officialCourseCount = officialCourseCount
    }
}

public struct CurriculumCourse: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseCode: String
    public let courseName: String
    public let credits: Double
    /// "4" = 已修通过, "1" = 在修, "2" = 未通过, "3" = 未修
    public let studyStatus: String
    public let grade: String
    public let suggestedYear: String
    public let suggestedTerm: String
    public let category: String

    public init(
        id: String,
        courseCode: String,
        courseName: String,
        credits: Double,
        studyStatus: String,
        grade: String = "",
        suggestedYear: String = "",
        suggestedTerm: String = "",
        category: String = ""
    ) {
        self.id = id
        self.courseCode = courseCode
        self.courseName = courseName
        self.credits = credits
        self.studyStatus = studyStatus
        self.grade = grade
        self.suggestedYear = suggestedYear
        self.suggestedTerm = suggestedTerm
        self.category = category
    }
}

public struct CurriculumNode: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let parentId: String
    public let name: String
    public let isLeaf: Bool
    public let earnedCredits: Double
    public let requiredCredits: Double
    public let passed: Bool
    public var courses: [CurriculumCourse]

    public init(
        id: String,
        parentId: String,
        name: String,
        isLeaf: Bool,
        earnedCredits: Double,
        requiredCredits: Double,
        passed: Bool,
        courses: [CurriculumCourse] = []
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.isLeaf = isLeaf
        self.earnedCredits = earnedCredits
        self.requiredCredits = requiredCredits
        self.passed = passed
        self.courses = courses
    }
}

public struct CurriculumTreeEntry: Sendable, Equatable, Identifiable {
    public let node: CurriculumNode
    public let depth: Int
    public let childCount: Int
    public let isExpandable: Bool
    public let isExpanded: Bool
    public let isLastChild: Bool
    public let ancestorHasNext: [Bool]

    public var id: String { node.id }
}

public enum CurriculumTreeBuilder {
    public static func deduplicateNodes(_ nodes: [CurriculumNode]) -> [CurriculumNode] {
        var indexById: [String: Int] = [:]
        var result: [CurriculumNode] = []

        for node in nodes {
            let trimmedId = node.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty else { continue }
            if let existingIdx = indexById[trimmedId] {
                if !node.courses.isEmpty {
                    var seenCourses = Set(result[existingIdx].courses.map { "\($0.courseCode)|\($0.courseName)" })
                    for course in node.courses {
                        let key = "\(course.courseCode)|\(course.courseName)"
                        if seenCourses.insert(key).inserted {
                            result[existingIdx].courses.append(course)
                        }
                    }
                }
            } else {
                indexById[trimmedId] = result.count
                var seenCourses = Set<String>()
                var dedupedCourses: [CurriculumCourse] = []
                for course in node.courses {
                    let key = "\(course.courseCode)|\(course.courseName)"
                    if seenCourses.insert(key).inserted {
                        dedupedCourses.append(course)
                    }
                }
                var cleanNode = node
                cleanNode.courses = dedupedCourses
                result.append(cleanNode)
            }
        }
        return result
    }

    public static func expandableIds(nodes: [CurriculumNode]) -> Set<String> {
        let uniqueNodes = deduplicateNodes(nodes)
        guard !uniqueNodes.isEmpty else { return [] }
        let rawChildrenByParent = Dictionary(
            grouping: uniqueNodes.filter { !$0.parentId.isEmpty && $0.parentId != $0.id },
            by: \.parentId
        )
        let meaningful = meaningfulNodeIds(nodes: uniqueNodes, childrenByParent: rawChildrenByParent)
        let rootId = uniqueNodes.first(where: { $0.parentId.isEmpty })?.id
        return Set(
            uniqueNodes.compactMap { node in
                guard meaningful.contains(node.id), node.id != rootId else { return nil }
                let hasMeaningfulChild = (rawChildrenByParent[node.id] ?? []).contains { meaningful.contains($0.id) }
                return (!node.courses.isEmpty || hasMeaningfulChild) ? node.id : nil
            }
        )
    }

    public static func defaultExpandedIds(nodes: [CurriculumNode]) -> Set<String> {
        let uniqueNodes = deduplicateNodes(nodes)
        guard !uniqueNodes.isEmpty else { return [] }
        let rawChildrenByParent = Dictionary(
            grouping: uniqueNodes.filter { !$0.parentId.isEmpty && $0.parentId != $0.id },
            by: \.parentId
        )
        let meaningful = meaningfulNodeIds(nodes: uniqueNodes, childrenByParent: rawChildrenByParent)
        let rootId = uniqueNodes.first(where: { $0.parentId.isEmpty })?.id
        let topLevelNodes: [CurriculumNode]
        if let rootId {
            topLevelNodes = (rawChildrenByParent[rootId] ?? []).filter { meaningful.contains($0.id) }
        } else {
            topLevelNodes = uniqueNodes.filter { $0.parentId.isEmpty && meaningful.contains($0.id) }
        }
        return Set(
            topLevelNodes.compactMap { top in
                let hasMeaningfulChild = (rawChildrenByParent[top.id] ?? []).contains { meaningful.contains($0.id) }
                return hasMeaningfulChild ? top.id : nil
            }
        )
    }

    public static func buildVisibleTree(
        nodes: [CurriculumNode],
        expandedIds: Set<String>
    ) -> [CurriculumTreeEntry] {
        let uniqueNodes = deduplicateNodes(nodes)
        guard !uniqueNodes.isEmpty else { return [] }

        let rawChildrenByParent = Dictionary(
            grouping: uniqueNodes.filter { !$0.parentId.isEmpty && $0.parentId != $0.id },
            by: \.parentId
        )
        let meaningful = meaningfulNodeIds(nodes: uniqueNodes, childrenByParent: rawChildrenByParent)
        let childrenByParent = rawChildrenByParent.mapValues { list in
            list.filter { meaningful.contains($0.id) }
        }

        let rootNode = uniqueNodes.first(where: { $0.parentId.isEmpty })
        let allIds = Set(uniqueNodes.map(\.id))
        let topNodes: [CurriculumNode]
        if let rootNode {
            topNodes = childrenByParent[rootNode.id] ?? []
        } else {
            topNodes = uniqueNodes.filter {
                meaningful.contains($0.id) && ($0.parentId.isEmpty || !allIds.contains($0.parentId))
            }
        }

        var output: [CurriculumTreeEntry] = []
        var visited = Set<String>()

        func dfs(_ list: [CurriculumNode], depth: Int, ancestorRails: [Bool]) {
            for (index, node) in list.enumerated() {
                guard visited.insert(node.id).inserted else { continue }
                let children = (childrenByParent[node.id] ?? []).filter { !visited.contains($0.id) }
                let hasNext = index < list.count - 1
                let expandable = !children.isEmpty || !node.courses.isEmpty
                let expanded = expandable && expandedIds.contains(node.id)
                output.append(
                    CurriculumTreeEntry(
                        node: node,
                        depth: depth,
                        childCount: children.count,
                        isExpandable: expandable,
                        isExpanded: expanded,
                        isLastChild: !hasNext,
                        ancestorHasNext: ancestorRails
                    )
                )
                if expanded && !children.isEmpty {
                    let childAncestors = depth == 0 ? [] : ancestorRails + [hasNext]
                    dfs(children, depth: depth + 1, ancestorRails: childAncestors)
                }
            }
        }
        dfs(topNodes, depth: 0, ancestorRails: [])
        return output
    }

    private static func meaningfulNodeIds(
        nodes: [CurriculumNode],
        childrenByParent: [String: [CurriculumNode]]
    ) -> Set<String> {
        let byId = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var memo: [String: Bool] = [:]

        func check(_ id: String, visiting: inout Set<String>) -> Bool {
            if let cached = memo[id] { return cached }
            guard let node = byId[id], visiting.insert(id).inserted else { return false }
            defer { visiting.remove(id) }
            let children = childrenByParent[id] ?? []
            let selfOK = node.isLeaf || !node.courses.isEmpty || node.requiredCredits > 0
            let childOK = children.contains { check($0.id, visiting: &visiting) }
            let res = selfOK || childOK
            memo[id] = res
            return res
        }

        var visiting = Set<String>()
        return Set(nodes.filter { check($0.id, visiting: &visiting) }.map(\.id))
    }
}

public struct OverallAcademicBundle: Codable, Sendable, Equatable {
    public let grades: [GradeItem]
    public let summary: OverallGradeSummary
    public let curriculumNodes: [CurriculumNode]

    public init(
        grades: [GradeItem],
        summary: OverallGradeSummary = OverallGradeSummary(),
        curriculumNodes: [CurriculumNode] = []
    ) {
        self.grades = grades
        self.summary = summary
        self.curriculumNodes = curriculumNodes
    }
}

public struct ExamItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var courseName: String
    public var examTime: String
    public var location: String
    public var seatNumber: String
    public var examName: String
    public var teacher: String
    public var isCustom: Bool

    public init(
        id: String,
        courseName: String,
        examTime: String,
        location: String = "",
        seatNumber: String = "",
        examName: String = "",
        teacher: String = "",
        isCustom: Bool = false
    ) {
        self.id = id
        self.courseName = courseName
        self.examTime = examTime
        self.location = location
        self.seatNumber = seatNumber
        self.examName = examName
        self.teacher = teacher
        self.isCustom = isCustom
    }

    public func parsedStartDate() -> Date? {
        let trimmed = examTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let datePart = String(trimmed.prefix(10))
        var timePart = "09:00"
        if let range = trimmed.range(of: #"\d{2}:\d{2}"#, options: .regularExpression) {
            timePart = String(trimmed[range])
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(datePart) \(timePart)")
    }
}

public enum EmptyClassroomCampus: Int, Codable, Sendable, CaseIterable, Identifiable {
    case north = 2
    case east = 1
    case west = 3
    case all = 0

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .north: return "北区"
        case .east: return "东区"
        case .west: return "西区"
        case .all: return "全部"
        }
    }
}

public struct EmptyClassroom: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let code: String
    public let name: String
    public let campus: String
    public let building: String
    public let floor: String
    public let type: String
    public let seats: Int
    public let examSeats: Int

    public init(
        id: String,
        code: String,
        name: String,
        campus: String,
        building: String,
        floor: String,
        type: String,
        seats: Int,
        examSeats: Int
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.campus = campus
        self.building = building
        self.floor = floor
        self.type = type
        self.seats = seats
        self.examSeats = examSeats
    }
}

public struct OfficialTermDate: Codable, Sendable, Equatable {
    public let wid: String
    public let academicYear: Int
    public let semester: Int
    public let termId: String
    public let beginDate: String
    public let endDate: String
    public let isCurrent: Bool

    public init(
        wid: String,
        academicYear: Int,
        semester: Int,
        termId: String,
        beginDate: String,
        endDate: String,
        isCurrent: Bool
    ) {
        self.wid = wid
        self.academicYear = academicYear
        self.semester = semester
        self.termId = termId
        self.beginDate = beginDate
        self.endDate = endDate
        self.isCurrent = isCurrent
    }
}

public struct CalendarHoliday: Codable, Sendable, Equatable {
    public let date: String
    public let name: String
    public let teachingWeek: Int

    public init(date: String, name: String, teachingWeek: Int) {
        self.date = date
        self.name = name
        self.teachingWeek = teachingWeek
    }
}

public struct OfficialCalendarSnapshot: Codable, Sendable, Equatable {
    public let currentTermId: String
    public let beginDate: String
    public let endDate: String
    public let currentTeachingWeek: Int
    public let terms: [OfficialTermDate]
    public let holidays: [CalendarHoliday]

    public init(
        currentTermId: String,
        beginDate: String,
        endDate: String,
        currentTeachingWeek: Int,
        terms: [OfficialTermDate],
        holidays: [CalendarHoliday] = []
    ) {
        self.currentTermId = currentTermId
        self.beginDate = beginDate
        self.endDate = endDate
        self.currentTeachingWeek = currentTeachingWeek
        self.terms = terms
        self.holidays = holidays
    }
}

public struct ReminderConfig: Codable, Sendable, Equatable {
    public var courseReminderEnabled: Bool
    public var courseLeadMinutes: Int
    public var examReminderEnabled: Bool
    public var mutedCourseIds: Set<String>

    public init(
        courseReminderEnabled: Bool = false,
        courseLeadMinutes: Int = 15,
        examReminderEnabled: Bool = false,
        mutedCourseIds: Set<String> = []
    ) {
        self.courseReminderEnabled = courseReminderEnabled
        self.courseLeadMinutes = courseLeadMinutes
        self.examReminderEnabled = examReminderEnabled
        self.mutedCourseIds = mutedCourseIds
    }
}

public struct TodayWidgetCourseItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let location: String
    public let timeRange: String
    public let startPeriod: Int
    public let endPeriod: Int

    public init(
        id: String,
        name: String,
        location: String,
        timeRange: String,
        startPeriod: Int,
        endPeriod: Int
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.timeRange = timeRange
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
    }
}

public struct TodayWidgetSnapshot: Codable, Sendable, Equatable {
    public let termDisplay: String
    public let currentWeek: Int?
    public let dayLabel: String
    public let courses: [TodayWidgetCourseItem]
    public let updatedAtMillis: Int64

    public init(
        termDisplay: String,
        currentWeek: Int?,
        dayLabel: String,
        courses: [TodayWidgetCourseItem],
        updatedAtMillis: Int64
    ) {
        self.termDisplay = termDisplay
        self.currentWeek = currentWeek
        self.dayLabel = dayLabel
        self.courses = courses
        self.updatedAtMillis = updatedAtMillis
    }
}
