import Foundation

public struct CourseSelectionTabParam: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(kklxdm)::\(xkkzId)" }
    public let kklxdm: String
    public let xkkzId: String
    public let njdmId: String
    public let zyhId: String
    public let title: String

    public init(kklxdm: String, xkkzId: String, njdmId: String = "", zyhId: String = "", title: String = "") {
        self.kklxdm = kklxdm
        self.xkkzId = xkkzId
        self.njdmId = njdmId
        self.zyhId = zyhId
        self.title = title.isEmpty ? Self.defaultTitle(for: kklxdm) : title
    }

    public static func defaultTitle(for kklxdm: String) -> String {
        switch kklxdm {
        case "01": return "主修课程"
        case "05": return "体育分项"
        case "06": return "特殊课程"
        case "10": return "通识选修"
        case "11": return "跨专业选修"
        default: return "类别 \(kklxdm)"
        }
    }
}

public struct CourseSelectionCourse: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(courseId)::\(classId.isEmpty ? doJxbId : classId)" }
    public let courseId: String
    public let classId: String
    public let doJxbId: String
    public let name: String
    public let teacher: String
    public let teachingClassName: String
    public let timeText: String
    public let location: String
    public let credits: String
    public let capacity: Int
    public let enrolled: Int
    public var isSelected: Bool
    public let kklxdm: String
    public let xkkzId: String
    public let rwlx: String
    public let xklc: String
    public let njdmId: String
    public let zyhId: String
    public let xkxnm: String
    public let xkxqm: String
    public let rlkz: String
    public let rlzlkz: String
    public let sxbj: String
    public let xxkbj: String
    public let cxbj: String
    public let jcxxId: String

    public init(
        courseId: String,
        classId: String,
        doJxbId: String = "",
        name: String,
        teacher: String = "",
        teachingClassName: String = "",
        timeText: String = "",
        location: String = "",
        credits: String = "",
        capacity: Int = 0,
        enrolled: Int = 0,
        isSelected: Bool = false,
        kklxdm: String = "10",
        xkkzId: String = "",
        rwlx: String = "1",
        xklc: String = "2",
        njdmId: String = "",
        zyhId: String = "",
        xkxnm: String = "",
        xkxqm: String = "",
        rlkz: String = "0",
        rlzlkz: String = "0",
        sxbj: String = "0",
        xxkbj: String = "0",
        cxbj: String = "0",
        jcxxId: String = ""
    ) {
        self.courseId = courseId
        self.classId = classId
        self.doJxbId = doJxbId
        self.name = name
        self.teacher = teacher
        self.teachingClassName = teachingClassName
        self.timeText = timeText
        self.location = location
        self.credits = credits
        self.capacity = capacity
        self.enrolled = enrolled
        self.isSelected = isSelected
        self.kklxdm = kklxdm
        self.xkkzId = xkkzId
        self.rwlx = rwlx
        self.xklc = xklc
        self.njdmId = njdmId
        self.zyhId = zyhId
        self.xkxnm = xkxnm
        self.xkxqm = xkxqm
        self.rlkz = rlkz
        self.rlzlkz = rlzlkz
        self.sxbj = sxbj
        self.xxkbj = xxkbj
        self.cxbj = cxbj
        self.jcxxId = jcxxId
    }

    public var remainingSeats: Int {
        max(0, capacity - enrolled)
    }

    public var hasSeats: Bool {
        capacity == 0 || enrolled < capacity
    }
}

public struct CourseSelectionWishlistItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseId: String
    public let classId: String
    public let name: String
    public let teacher: String
    public let teachingClassName: String
    public let timeText: String
    public let location: String
    public let credits: String
    public let kklxdm: String
    public let xkkzId: String
    public var note: String
    public let addedAt: Int64

    public init(
        id: String = UUID().uuidString,
        courseId: String,
        classId: String,
        name: String,
        teacher: String = "",
        teachingClassName: String = "",
        timeText: String = "",
        location: String = "",
        credits: String = "",
        kklxdm: String = "10",
        xkkzId: String = "",
        note: String = "",
        addedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.courseId = courseId
        self.classId = classId
        self.name = name
        self.teacher = teacher
        self.teachingClassName = teachingClassName
        self.timeText = timeText
        self.location = location
        self.credits = credits
        self.kklxdm = kklxdm
        self.xkkzId = xkkzId
        self.note = note
        self.addedAt = addedAt
    }

    public func toSelectionCourse(xkxnm: String = "", xkxqm: String = "") -> CourseSelectionCourse {
        CourseSelectionCourse(
            courseId: courseId,
            classId: classId,
            name: name,
            teacher: teacher,
            teachingClassName: teachingClassName,
            timeText: timeText,
            location: location,
            credits: credits,
            kklxdm: kklxdm,
            xkkzId: xkkzId,
            xkxnm: xkxnm,
            xkxqm: xkxqm
        )
    }
}

public struct CourseSelectionSnapshot: Codable, Sendable, Equatable {
    public let isOpen: Bool
    public let statusMessage: String
    public let xkxnm: String
    public let xkxqm: String
    public let tabs: [CourseSelectionTabParam]
    public var availableCourses: [CourseSelectionCourse]
    public var selectedCourses: [CourseSelectionCourse]

    public init(
        isOpen: Bool = false,
        statusMessage: String = "",
        xkxnm: String = "",
        xkxqm: String = "",
        tabs: [CourseSelectionTabParam] = [],
        availableCourses: [CourseSelectionCourse] = [],
        selectedCourses: [CourseSelectionCourse] = []
    ) {
        self.isOpen = isOpen
        self.statusMessage = statusMessage
        self.xkxnm = xkxnm
        self.xkxqm = xkxqm
        self.tabs = tabs
        self.availableCourses = availableCourses
        self.selectedCourses = selectedCourses
    }
}

public struct CourseSelectionActionResult: Sendable, Equatable {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}
