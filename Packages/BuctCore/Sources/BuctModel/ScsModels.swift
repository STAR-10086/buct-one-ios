import Foundation

public struct ScsEvalWindow: Codable, Sendable, Equatable {
    public let yearId: Int
    public let termId: Int
    public let yearName: String
    public let termName: String
    public let isOpen: Bool
    public let selfStartTime: String
    public let selfEndTime: String

    public init(
        yearId: Int = 0,
        termId: Int = 0,
        yearName: String = "",
        termName: String = "",
        isOpen: Bool = false,
        selfStartTime: String = "",
        selfEndTime: String = ""
    ) {
        self.yearId = yearId
        self.termId = termId
        self.yearName = yearName
        self.termName = termName
        self.isOpen = isOpen
        self.selfStartTime = selfStartTime
        self.selfEndTime = selfEndTime
    }
}

public struct ScsDimensionDef: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let totalScore: Double
    public let basicScore: Double
    public let extScore: Double

    public init(id: Int, name: String, totalScore: Double, basicScore: Double = 0, extScore: Double = 0) {
        self.id = id
        self.name = name
        self.totalScore = totalScore
        self.basicScore = basicScore
        self.extScore = extScore
    }
}

public struct ScsEvalItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let isBasic: Bool
    public let score: Double
    public let maxScore: Double
    public let laborHours: Double
    public let comment: String

    public init(
        id: String,
        title: String,
        isBasic: Bool = true,
        score: Double = 0,
        maxScore: Double = 0,
        laborHours: Double = 0,
        comment: String = ""
    ) {
        self.id = id
        self.title = title
        self.isBasic = isBasic
        self.score = score
        self.maxScore = maxScore
        self.laborHours = laborHours
        self.comment = comment
    }
}

public struct ScsCategoryDetail: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { typeId }
    public let typeId: Int
    public let typeName: String
    public let score: Double
    public let maxScore: Double
    public let items: [ScsEvalItem]

    public init(typeId: Int, typeName: String, score: Double, maxScore: Double, items: [ScsEvalItem] = []) {
        self.typeId = typeId
        self.typeName = typeName
        self.score = score
        self.maxScore = maxScore
        self.items = items
    }
}

public struct ScsTermScore: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(yearId)_\(termId)_\(yearName)_\(termName)" }
    public let yearId: Int
    public let termId: Int
    public let yearName: String
    public let termName: String
    public let isFullYear: Bool
    public let totalScore: Double
    public let moral: Double
    public let academic: Double
    public let physical: Double
    public let aesthetics: Double
    public let labor: Double
    public let details: [ScsCategoryDetail]

    public init(
        yearId: Int = 0,
        termId: Int = 0,
        yearName: String,
        termName: String,
        isFullYear: Bool = false,
        totalScore: Double = 0,
        moral: Double = 0,
        academic: Double = 0,
        physical: Double = 0,
        aesthetics: Double = 0,
        labor: Double = 0,
        details: [ScsCategoryDetail] = []
    ) {
        self.yearId = yearId
        self.termId = termId
        self.yearName = yearName
        self.termName = termName
        self.isFullYear = isFullYear
        self.totalScore = totalScore
        self.moral = moral
        self.academic = academic
        self.physical = physical
        self.aesthetics = aesthetics
        self.labor = labor
        self.details = details
    }

    public var displayTitle: String {
        isFullYear ? "\(yearName) 全年" : "\(yearName) \(termName)"
    }
}

public struct ScsActivityItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let categoryName: String
    public let startTime: String
    public let location: String
    public let scoreText: String
    public let status: String

    public init(
        id: String,
        title: String,
        categoryName: String = "",
        startTime: String = "",
        location: String = "",
        scoreText: String = "",
        status: String = ""
    ) {
        self.id = id
        self.title = title
        self.categoryName = categoryName
        self.startTime = startTime
        self.location = location
        self.scoreText = scoreText
        self.status = status
    }
}

public struct ScsSnapshot: Codable, Sendable, Equatable {
    public let studentName: String
    public let studentId: String
    public let collegeName: String
    public let className: String
    public let gradeName: String
    public let currentWindow: ScsEvalWindow?
    public let dimensions: [ScsDimensionDef]
    public let terms: [ScsTermScore]
    public let activities: [ScsActivityItem]

    public init(
        studentName: String = "",
        studentId: String = "",
        collegeName: String = "",
        className: String = "",
        gradeName: String = "",
        currentWindow: ScsEvalWindow? = nil,
        dimensions: [ScsDimensionDef] = [],
        terms: [ScsTermScore] = [],
        activities: [ScsActivityItem] = []
    ) {
        self.studentName = studentName
        self.studentId = studentId
        self.collegeName = collegeName
        self.className = className
        self.gradeName = gradeName
        self.currentWindow = currentWindow
        self.dimensions = dimensions
        self.terms = terms
        self.activities = activities
    }
}
