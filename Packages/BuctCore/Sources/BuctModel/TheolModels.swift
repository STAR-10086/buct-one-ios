import Foundation

public struct TheolCourseInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { lid }
    public let lid: String
    public let courseName: String
    public let type: String
    public let url: String

    public init(lid: String, courseName: String, type: String = "course", url: String) {
        self.lid = lid
        self.courseName = courseName
        self.type = type
        self.url = url
    }
}

public struct TheolHomeworkItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(lid):\(hwtid)" }
    public let hwtid: String
    public let lid: String
    public let courseName: String
    public let title: String
    public let deadline: String
    public let deadlineMillis: Int64?
    public let score: String
    public let publisher: String
    public let canSubmit: Bool
    public let hasResult: Bool
    public let isGroup: Bool
    public let status: String
    public let detailHref: String
    public let submitHref: String
    public let resultHref: String

    public init(
        hwtid: String,
        lid: String,
        courseName: String,
        title: String,
        deadline: String = "",
        deadlineMillis: Int64? = nil,
        score: String = "",
        publisher: String = "",
        canSubmit: Bool = false,
        hasResult: Bool = false,
        isGroup: Bool = false,
        status: String = "",
        detailHref: String = "",
        submitHref: String = "",
        resultHref: String = ""
    ) {
        self.hwtid = hwtid
        self.lid = lid
        self.courseName = courseName
        self.title = title
        self.deadline = deadline
        self.deadlineMillis = deadlineMillis
        self.score = score
        self.publisher = publisher
        self.canSubmit = canSubmit
        self.hasResult = hasResult
        self.isGroup = isGroup
        self.status = status
        self.detailHref = detailHref
        self.submitHref = submitHref
        self.resultHref = resultHref
    }
}

public struct TheolHomeworkAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { url }
    public let name: String
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

public struct TheolHomeworkDetail: Codable, Sendable, Equatable {
    public let hwtid: String
    public let title: String
    public let deadline: String
    public let score: String
    public let publisher: String
    public let contentText: String
    public let attachments: [TheolHomeworkAttachment]
    public let fetchedAt: Int64

    public init(
        hwtid: String,
        title: String,
        deadline: String,
        score: String,
        publisher: String,
        contentText: String,
        attachments: [TheolHomeworkAttachment] = [],
        fetchedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.hwtid = hwtid
        self.title = title
        self.deadline = deadline
        self.score = score
        self.publisher = publisher
        self.contentText = contentText
        self.attachments = attachments
        self.fetchedAt = fetchedAt
    }
}

public struct TheolTestItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(lid):\(testId)" }
    public let testId: String
    public let lid: String
    public let courseName: String
    public let title: String
    public let startTime: String
    public let endTime: String
    public let endTimeMillis: Int64?
    public let duration: String
    public let allowedAttempts: String
    public let canStart: Bool
    public let hasResult: Bool
    public let status: String
    public let testUrl: String
    public let resultHref: String

    public init(
        testId: String,
        lid: String,
        courseName: String,
        title: String,
        startTime: String = "",
        endTime: String = "",
        endTimeMillis: Int64? = nil,
        duration: String = "",
        allowedAttempts: String = "",
        canStart: Bool = false,
        hasResult: Bool = false,
        status: String = "",
        testUrl: String = "",
        resultHref: String = ""
    ) {
        self.testId = testId
        self.lid = lid
        self.courseName = courseName
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.endTimeMillis = endTimeMillis
        self.duration = duration
        self.allowedAttempts = allowedAttempts
        self.canStart = canStart
        self.hasResult = hasResult
        self.status = status
        self.testUrl = testUrl
        self.resultHref = resultHref
    }
}

public struct TheolTestDetail: Codable, Sendable, Equatable {
    public let testId: String
    public let title: String
    public let description: String
    public let startTime: String
    public let endTime: String
    public let duration: String
    public let totalScore: String
    public let questionCount: String
    public let fetchedAt: Int64

    public init(
        testId: String,
        title: String,
        description: String,
        startTime: String,
        endTime: String,
        duration: String,
        totalScore: String,
        questionCount: String,
        fetchedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.testId = testId
        self.title = title
        self.description = description
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.totalScore = totalScore
        self.questionCount = questionCount
        self.fetchedAt = fetchedAt
    }
}

public struct TheolCourseUnit: Codable, Sendable, Equatable, Identifiable {
    public var id: String { columnId }
    public let columnId: String
    public let title: String
    public let url: String

    public init(columnId: String, title: String, url: String) {
        self.columnId = columnId
        self.title = title
        self.url = url
    }
}

public struct TheolResourceItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { url }
    public let name: String
    public let isFolder: Bool
    public let url: String
    public let sizeText: String
    public let updatedAt: String
    public let fileExt: String
    public let previewUrl: String

    public init(
        name: String,
        isFolder: Bool,
        url: String,
        sizeText: String = "",
        updatedAt: String = "",
        fileExt: String = "",
        previewUrl: String = ""
    ) {
        self.name = name
        self.isFolder = isFolder
        self.url = url
        self.sizeText = sizeText
        self.updatedAt = updatedAt
        self.fileExt = fileExt
        self.previewUrl = previewUrl
    }
}

public struct TheolResourcePage: Codable, Sendable, Equatable {
    public let lid: String
    public let courseName: String
    public let currentUrl: String
    public let folderTitle: String
    public let items: [TheolResourceItem]

    public init(
        lid: String,
        courseName: String,
        currentUrl: String,
        folderTitle: String,
        items: [TheolResourceItem]
    ) {
        self.lid = lid
        self.courseName = courseName
        self.currentUrl = currentUrl
        self.folderTitle = folderTitle
        self.items = items
    }
}

public struct TheolDownloadedFile: Codable, Sendable, Equatable {
    public let filePath: String
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int64
    public let isHtmlPage: Bool

    public init(
        filePath: String,
        fileName: String,
        mimeType: String,
        sizeBytes: Int64,
        isHtmlPage: Bool = false
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.isHtmlPage = isHtmlPage
    }
}

public struct TheolSnapshot: Codable, Sendable, Equatable {
    public var homeworks: [TheolHomeworkItem]
    public var tests: [TheolTestItem]
    public var failedCourseCount: Int
    public var courses: [TheolCourseInfo]

    public init(
        homeworks: [TheolHomeworkItem] = [],
        tests: [TheolTestItem] = [],
        failedCourseCount: Int = 0,
        courses: [TheolCourseInfo] = []
    ) {
        self.homeworks = homeworks
        self.tests = tests
        self.failedCourseCount = failedCourseCount
        self.courses = courses
    }
}

public struct LocalTodoItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var courseName: String
    public var deadlineMillis: Int64?
    public var completed: Bool
    public var note: String
    public let createdAt: Int64

    public init(
        id: String = UUID().uuidString,
        title: String,
        courseName: String = "",
        deadlineMillis: Int64? = nil,
        completed: Bool = false,
        note: String = "",
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.title = title
        self.courseName = courseName
        self.deadlineMillis = deadlineMillis
        self.completed = completed
        self.note = note
        self.createdAt = createdAt
    }
}

public struct TheolFilterPrefs: Codable, Sendable, Equatable {
    public var hiddenHomeworkIds: Set<String>
    public var hiddenTestKeys: Set<String>
    public var hiddenCourseNames: Set<String>
    public var hiddenExperimentIds: Set<String>

    public init(
        hiddenHomeworkIds: Set<String> = [],
        hiddenTestKeys: Set<String> = [],
        hiddenCourseNames: Set<String> = [],
        hiddenExperimentIds: Set<String> = []
    ) {
        self.hiddenHomeworkIds = hiddenHomeworkIds
        self.hiddenTestKeys = hiddenTestKeys
        self.hiddenCourseNames = hiddenCourseNames
        self.hiddenExperimentIds = hiddenExperimentIds
    }

    private enum CodingKeys: String, CodingKey {
        case hiddenHomeworkIds
        case hiddenTestKeys
        case hiddenCourseNames
        case hiddenExperimentIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hiddenHomeworkIds = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenHomeworkIds) ?? []
        self.hiddenTestKeys = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenTestKeys) ?? []
        self.hiddenCourseNames = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenCourseNames) ?? []
        self.hiddenExperimentIds = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenExperimentIds) ?? []
    }

    public var totalHiddenCount: Int {
        hiddenCourseNames.count + hiddenHomeworkIds.count + hiddenTestKeys.count + hiddenExperimentIds.count
    }

    public func isCourseHidden(_ courseName: String) -> Bool {
        let key = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && hiddenCourseNames.contains(key)
    }
}

public struct TheolWebSessionCookie: Codable, Sendable, Equatable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool

    public init(name: String, value: String, domain: String, path: String, isSecure: Bool) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.isSecure = isSecure
    }
}

public struct TheolWebLaunchContext: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let urlString: String
    public let title: String
    public let cookies: [TheolWebSessionCookie]

    public init(
        id: String = UUID().uuidString,
        urlString: String,
        title: String,
        cookies: [TheolWebSessionCookie]
    ) {
        self.id = id
        self.urlString = urlString
        self.title = title
        self.cookies = cookies
    }
}

public enum TheolSorting {
    public static func sortHomeworks(_ items: [TheolHomeworkItem]) -> [TheolHomeworkItem] {
        items.sorted { a, b in
            let rankA = rank(a)
            let rankB = rank(b)
            if rankA != rankB { return rankA < rankB }
            switch rankA {
            case 0:
                let ta = a.deadlineMillis ?? Int64.max
                let tb = b.deadlineMillis ?? Int64.max
                if ta != tb { return ta < tb }
            case 2:
                let ta = a.deadlineMillis ?? Int64.min
                let tb = b.deadlineMillis ?? Int64.min
                if ta != tb { return ta > tb }
            default:
                break
            }
            return a.title < b.title
        }
    }

    public static func sortTests(_ items: [TheolTestItem]) -> [TheolTestItem] {
        items.sorted { a, b in
            let rankA = testRank(a)
            let rankB = testRank(b)
            if rankA != rankB { return rankA < rankB }
            let ta = a.endTimeMillis ?? Int64.max
            let tb = b.endTimeMillis ?? Int64.max
            if ta != tb { return ta < tb }
            return a.title < b.title
        }
    }

    private static func rank(_ hw: TheolHomeworkItem) -> Int {
        if hw.canSubmit { return 0 }
        if hw.hasResult || hw.status == "已完成" { return 1 }
        return 2
    }

    private static func testRank(_ test: TheolTestItem) -> Int {
        if test.canStart { return 0 }
        if test.hasResult || test.status == "已完成" { return 1 }
        return 2
    }
}
