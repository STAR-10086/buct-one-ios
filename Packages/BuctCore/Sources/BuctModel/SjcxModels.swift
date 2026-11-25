import Foundation

public struct SjcxReportItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let reportId: String
    public let groupId: String
    public let courseName: String
    public let expName: String
    public let docName: String
    public let templateId: String
    public let templateName: String
    public let state: Int
    public let stateText: String
    public let scoreText: String
    public let opinion: String
    public let submitTime: String

    public init(
        id: String,
        reportId: String = "",
        groupId: String = "",
        courseName: String,
        expName: String,
        docName: String = "",
        templateId: String = "",
        templateName: String = "",
        state: Int = 0,
        stateText: String = "",
        scoreText: String = "",
        opinion: String = "",
        submitTime: String = ""
    ) {
        self.id = id
        self.reportId = reportId
        self.groupId = groupId
        self.courseName = courseName
        self.expName = expName
        self.docName = docName
        self.templateId = templateId
        self.templateName = templateName
        self.state = state
        self.stateText = stateText
        self.scoreText = scoreText
        self.opinion = opinion
        self.submitTime = submitTime
    }

    public var isSubmitted: Bool {
        state > 0 || !docName.isEmpty
    }
}

public struct SjcxScheduleItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseName: String
    public let expName: String
    public let week: Int
    public let weekDay: Int
    public let jcText: String
    public let roomName: String
    public let teacherName: String

    public init(
        id: String,
        courseName: String,
        expName: String,
        week: Int,
        weekDay: Int,
        jcText: String = "",
        roomName: String = "",
        teacherName: String = ""
    ) {
        self.id = id
        self.courseName = courseName
        self.expName = expName
        self.week = week
        self.weekDay = weekDay
        self.jcText = jcText
        self.roomName = roomName
        self.teacherName = teacherName
    }
}

public struct SjcxScoreItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let courseName: String
    public let expName: String
    public let scoreText: String
    public let detailScores: [String]

    public init(
        id: String,
        courseName: String,
        expName: String,
        scoreText: String,
        detailScores: [String] = []
    ) {
        self.id = id
        self.courseName = courseName
        self.expName = expName
        self.scoreText = scoreText
        self.detailScores = detailScores
    }
}

public struct SjcxLectureItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectTimeId: String
    public let registrationId: String
    public let title: String
    public let speaker: String
    public let location: String
    public let startTime: String
    public let credit: Double
    public let capacityText: String
    public let statusText: String
    public let isRegistered: Bool
    public let hasExperience: Bool

    public init(
        id: String,
        projectTimeId: String = "",
        registrationId: String = "",
        title: String,
        speaker: String = "",
        location: String = "",
        startTime: String = "",
        credit: Double = 0,
        capacityText: String = "",
        statusText: String = "",
        isRegistered: Bool = false,
        hasExperience: Bool = false
    ) {
        self.id = id
        self.projectTimeId = projectTimeId
        self.registrationId = registrationId
        self.title = title
        self.speaker = speaker
        self.location = location
        self.startTime = startTime
        self.credit = credit
        self.capacityText = capacityText
        self.statusText = statusText
        self.isRegistered = isRegistered
        self.hasExperience = hasExperience
    }
}

public struct SjcxCreditRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let category: String
    public let credit: Double
    public let grantedAt: String

    public init(id: String, title: String, category: String = "", credit: Double, grantedAt: String = "") {
        self.id = id
        self.title = title
        self.category = category
        self.credit = credit
        self.grantedAt = grantedAt
    }
}

public struct SjcxSnapshot: Codable, Sendable, Equatable {
    public let yearterm: String
    public let currentWeek: Int
    public let reports: [SjcxReportItem]
    public let schedules: [SjcxScheduleItem]
    public let scores: [SjcxScoreItem]
    public let openLectures: [SjcxLectureItem]
    public let endedLectures: [SjcxLectureItem]
    public let myLectures: [SjcxLectureItem]
    public let creditRecords: [SjcxCreditRecord]
    public let totalCredit: Double
    public let noSignCount: Int

    public init(
        yearterm: String = "",
        currentWeek: Int = 1,
        reports: [SjcxReportItem] = [],
        schedules: [SjcxScheduleItem] = [],
        scores: [SjcxScoreItem] = [],
        openLectures: [SjcxLectureItem] = [],
        endedLectures: [SjcxLectureItem] = [],
        myLectures: [SjcxLectureItem] = [],
        creditRecords: [SjcxCreditRecord] = [],
        totalCredit: Double = 0,
        noSignCount: Int = 0
    ) {
        self.yearterm = yearterm
        self.currentWeek = currentWeek
        self.reports = reports
        self.schedules = schedules
        self.scores = scores
        self.openLectures = openLectures
        self.endedLectures = endedLectures
        self.myLectures = myLectures
        self.creditRecords = creditRecords
        self.totalCredit = totalCredit
        self.noSignCount = noSignCount
    }
}
