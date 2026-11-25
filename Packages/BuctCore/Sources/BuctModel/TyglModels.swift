import Foundation

public struct TyglStudentProfile: Codable, Sendable, Equatable {
    public let name: String
    public let studentId: String
    public let gender: String
    public let grade: String
    public let className: String
    public let college: String
    public let testRequired: String
    public let specialNote: String

    public init(
        name: String = "",
        studentId: String = "",
        gender: String = "",
        grade: String = "",
        className: String = "",
        college: String = "",
        testRequired: String = "",
        specialNote: String = ""
    ) {
        self.name = name
        self.studentId = studentId
        self.gender = gender
        self.grade = grade
        self.className = className
        self.college = college
        self.testRequired = testRequired
        self.specialNote = specialNote
    }
}

public struct TyglFitnessItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let rawValue: String
    public let score: String
    public let grade: String

    public init(name: String, rawValue: String, score: String = "", grade: String = "") {
        self.name = name
        self.rawValue = rawValue
        self.score = score
        self.grade = grade
    }
}

public struct TyglFitnessRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { year }
    public let year: String
    public let updatedAt: String
    public let totalScore: String
    public let level: String
    public let heightCm: String
    public let weightKg: String
    public let bonusScore: String
    public let bonusReason: String
    public let items: [TyglFitnessItem]
    public let prescriptions: [String]

    public init(
        year: String,
        updatedAt: String = "",
        totalScore: String = "",
        level: String = "",
        heightCm: String = "",
        weightKg: String = "",
        bonusScore: String = "",
        bonusReason: String = "",
        items: [TyglFitnessItem] = [],
        prescriptions: [String] = []
    ) {
        self.year = year
        self.updatedAt = updatedAt
        self.totalScore = totalScore
        self.level = level
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.bonusScore = bonusScore
        self.bonusReason = bonusReason
        self.items = items
        self.prescriptions = prescriptions
    }
}

public struct TyglRunPlan: Codable, Sendable, Equatable {
    public let term: String
    public let startTime: String
    public let endTime: String
    public let targetText: String
    public let summary: String

    public init(term: String = "", startTime: String = "", endTime: String = "", targetText: String = "", summary: String = "") {
        self.term = term
        self.startTime = startTime
        self.endTime = endTime
        self.targetText = targetText
        self.summary = summary
    }
}

public struct TyglExerciseTerm: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(year)_\(term)" }
    public let year: String
    public let term: String
    public let values: [String: String]

    public init(year: String, term: String, values: [String: String]) {
        self.year = year
        self.term = term
        self.values = values
    }
}

public struct TyglPeCourseScore: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(year)_\(term)_\(courseName)" }
    public let year: String
    public let term: String
    public let courseName: String
    public let teacher: String
    public let score: String
    public let note: String

    public init(year: String, term: String, courseName: String, teacher: String = "", score: String = "", note: String = "") {
        self.year = year
        self.term = term
        self.courseName = courseName
        self.teacher = teacher
        self.score = score
        self.note = note
    }
}

public struct TyglExamInfo: Codable, Sendable, Equatable {
    public let currentTerm: String
    public let peClass: String
    public let remainingAttempts: String
    public let highestScore: String
    public let notice: String
    public let scheduleText: String

    public init(
        currentTerm: String = "",
        peClass: String = "",
        remainingAttempts: String = "",
        highestScore: String = "",
        notice: String = "",
        scheduleText: String = ""
    ) {
        self.currentTerm = currentTerm
        self.peClass = peClass
        self.remainingAttempts = remainingAttempts
        self.highestScore = highestScore
        self.notice = notice
        self.scheduleText = scheduleText
    }
}

public struct TyglSnapshot: Codable, Sendable, Equatable {
    public let profile: TyglStudentProfile
    public let fitnessRecords: [TyglFitnessRecord]
    public let runPlan: TyglRunPlan?
    public let exerciseColumns: [String]
    public let exerciseTerms: [TyglExerciseTerm]
    public let peCourses: [TyglPeCourseScore]
    public let examInfo: TyglExamInfo?

    public init(
        profile: TyglStudentProfile = TyglStudentProfile(),
        fitnessRecords: [TyglFitnessRecord] = [],
        runPlan: TyglRunPlan? = nil,
        exerciseColumns: [String] = [],
        exerciseTerms: [TyglExerciseTerm] = [],
        peCourses: [TyglPeCourseScore] = [],
        examInfo: TyglExamInfo? = nil
    ) {
        self.profile = profile
        self.fitnessRecords = fitnessRecords
        self.runPlan = runPlan
        self.exerciseColumns = exerciseColumns
        self.exerciseTerms = exerciseTerms
        self.peCourses = peCourses
        self.examInfo = examInfo
    }
}

// MARK: - 2014 国家学生体质健康标准（大学本科）算分器

public enum FitnessGender: String, Codable, Sendable, CaseIterable {
    case male = "男"
    case female = "女"
}

public enum FitnessGradeGroup: String, Codable, Sendable, CaseIterable {
    case lower = "大一/大二"
    case upper = "大三/大四"
}

public struct FitnessSimInput: Sendable, Equatable {
    public var gender: FitnessGender
    public var gradeGroup: FitnessGradeGroup
    public var heightCm: Double
    public var weightKg: Double
    public var lungCapacityMl: Double
    public var run50mSec: Double
    public var sitAndReachCm: Double
    public var standingJumpCm: Double
    public var strengthCount: Double // 男引体向上 / 女一分钟仰卧起坐
    public var enduranceSec: Double  // 男 1000m / 女 800m（秒）

    public init(
        gender: FitnessGender = .male,
        gradeGroup: FitnessGradeGroup = .lower,
        heightCm: Double = 175,
        weightKg: Double = 65,
        lungCapacityMl: Double = 4200,
        run50mSec: Double = 7.5,
        sitAndReachCm: Double = 14.0,
        standingJumpCm: Double = 235,
        strengthCount: Double = 12,
        enduranceSec: Double = 235
    ) {
        self.gender = gender
        self.gradeGroup = gradeGroup
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.lungCapacityMl = lungCapacityMl
        self.run50mSec = run50mSec
        self.sitAndReachCm = sitAndReachCm
        self.standingJumpCm = standingJumpCm
        self.strengthCount = strengthCount
        self.enduranceSec = enduranceSec
    }
}

public struct FitnessSimResult: Sendable, Equatable {
    public let bmi: Double
    public let bmiScore: Double
    public let lungScore: Double
    public let run50mScore: Double
    public let sitAndReachScore: Double
    public let standingJumpScore: Double
    public let strengthScore: Double
    public let enduranceScore: Double
    public let bonusScore: Double
    public let standardTotal: Double
    public let finalTotal: Double
    public let level: String
}

public enum NationalFitnessScorer {
    public static func evaluate(_ input: FitnessSimInput) -> FitnessSimResult {
        let hM = max(0.5, input.heightCm / 100.0)
        let bmi = input.weightKg / (hM * hM)
        let bmiScore = scoreBMI(bmi: bmi, gender: input.gender)

        let isMale = (input.gender == .male)
        let isUpper = (input.gradeGroup == .upper)

        let lungScore = scoreHigherIsBetter(
            value: input.lungCapacityMl,
            table: isMale
                ? (isUpper ? [(5140, 100), (4920, 90), (4400, 80), (3200, 60), (2350, 10)] : [(5040, 100), (4800, 90), (4300, 80), (3100, 60), (2300, 10)])
                : (isUpper ? [(3450, 100), (3350, 90), (3050, 80), (2050, 60), (1850, 10)] : [(3400, 100), (3300, 90), (3000, 80), (2000, 60), (1800, 10)])
        )
        let run50mScore = scoreLowerIsBetter(
            value: input.run50mSec,
            table: isMale
                ? (isUpper ? [(6.6, 100), (6.8, 90), (7.0, 80), (9.0, 60), (10.0, 10)] : [(6.7, 100), (6.9, 90), (7.1, 80), (9.1, 60), (10.1, 10)])
                : (isUpper ? [(7.4, 100), (7.6, 90), (8.2, 80), (10.2, 60), (11.2, 10)] : [(7.5, 100), (7.7, 90), (8.3, 80), (10.3, 60), (11.3, 10)])
        )
        let sitScore = scoreHigherIsBetter(
            value: input.sitAndReachCm,
            table: isMale
                ? (isUpper ? [(25.1, 100), (21.5, 90), (18.2, 80), (4.2, 60), (-0.8, 10)] : [(24.9, 100), (21.3, 90), (17.7, 80), (3.7, 60), (-1.3, 10)])
                : (isUpper ? [(26.3, 100), (22.4, 90), (19.5, 80), (6.5, 60), (2.5, 10)] : [(25.8, 100), (22.2, 90), (19.0, 80), (6.0, 60), (2.0, 10)])
        )
        let jumpScore = scoreHigherIsBetter(
            value: input.standingJumpCm,
            table: isMale
                ? (isUpper ? [(275, 100), (265, 90), (250, 80), (210, 60), (185, 10)] : [(273, 100), (263, 90), (248, 80), (208, 60), (183, 10)])
                : (isUpper ? [(208, 100), (196, 90), (182, 80), (152, 60), (127, 10)] : [(207, 100), (195, 90), (181, 80), (151, 60), (126, 10)])
        )
        let strengthTable: [(Double, Double)] = isMale
            ? (isUpper ? [(20, 100), (18, 90), (16, 80), (11, 60), (6, 10)] : [(19, 100), (17, 90), (15, 80), (10, 60), (5, 10)])
            : (isUpper ? [(57, 100), (53, 90), (47, 80), (27, 60), (17, 10)] : [(56, 100), (52, 90), (46, 80), (26, 60), (16, 10)])
        let strengthScore = scoreHigherIsBetter(value: input.strengthCount, table: strengthTable)

        let enduranceTable: [(Double, Double)] = isMale
            ? (isUpper ? [(195, 100), (205, 90), (220, 80), (270, 60), (370, 10)] : [(197, 100), (207, 90), (222, 80), (272, 60), (372, 10)])
            : (isUpper ? [(196, 100), (208, 90), (222, 80), (272, 60), (322, 10)] : [(198, 100), (210, 90), (224, 80), (274, 60), (324, 10)])
        let enduranceScore = scoreLowerIsBetter(value: input.enduranceSec, table: enduranceTable)

        // 加分项（最多各 10 分，总加分上限 20）
        var bonus = 0.0
        let strength100 = strengthTable[0].0
        if input.strengthCount > strength100 {
            let step = isMale ? 1.0 : 2.0
            bonus += min(10.0, floor((input.strengthCount - strength100) / step))
        }
        let endurance100 = enduranceTable[0].0
        if input.enduranceSec < endurance100 {
            let step = isMale ? 4.0 : 5.0
            bonus += min(10.0, floor((endurance100 - input.enduranceSec) / step))
        }

        let standard = bmiScore * 0.15 +
            lungScore * 0.15 +
            run50mScore * 0.20 +
            sitScore * 0.10 +
            jumpScore * 0.10 +
            strengthScore * 0.10 +
            enduranceScore * 0.20
        let finalTotal = min(120.0, standard + bonus)
        let level: String
        if finalTotal >= 90 { level = "优秀" }
        else if finalTotal >= 80 { level = "良好" }
        else if finalTotal >= 60 { level = "及格" }
        else { level = "不及格" }

        return FitnessSimResult(
            bmi: bmi,
            bmiScore: bmiScore,
            lungScore: lungScore,
            run50mScore: run50mScore,
            sitAndReachScore: sitScore,
            standingJumpScore: jumpScore,
            strengthScore: strengthScore,
            enduranceScore: enduranceScore,
            bonusScore: bonus,
            standardTotal: standard,
            finalTotal: finalTotal,
            level: level
        )
    }

    public static func parseEnduranceSeconds(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "分", with: ":")
            .replacingOccurrences(of: "'", with: ":")
            .replacingOccurrences(of: "′", with: ":")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "″", with: "")
            .replacingOccurrences(of: "秒", with: "")
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":")
            if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                return m * 60 + s
            }
        }
        if cleaned.contains(".") {
            let parts = cleaned.split(separator: ".")
            if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]), m <= 10, s < 60 {
                return m * 60 + s
            }
        }
        return Double(cleaned)
    }

    private static func scoreBMI(bmi: Double, gender: FitnessGender) -> Double {
        if gender == .male {
            if (17.9...23.9).contains(bmi) { return 100 }
            if bmi < 17.9 || (24.0...27.9).contains(bmi) { return 80 }
            return 60
        } else {
            if (17.2...23.9).contains(bmi) { return 100 }
            if bmi < 17.2 || (24.0...27.9).contains(bmi) { return 80 }
            return 60
        }
    }

    private static func scoreHigherIsBetter(value: Double, table: [(Double, Double)]) -> Double {
        guard let first = table.first, let last = table.last else { return 0 }
        if value >= first.0 { return first.1 }
        if value < last.0 { return 0 }
        for i in 0..<(table.count - 1) {
            let hi = table[i]
            let lo = table[i + 1]
            if value >= lo.0 {
                let ratio = (value - lo.0) / max(0.0001, hi.0 - lo.0)
                return lo.1 + ratio * (hi.1 - lo.1)
            }
        }
        return 0
    }

    private static func scoreLowerIsBetter(value: Double, table: [(Double, Double)]) -> Double {
        guard value > 0, let first = table.first, let last = table.last else { return 0 }
        if value <= first.0 { return first.1 }
        if value > last.0 { return 0 }
        for i in 0..<(table.count - 1) {
            let best = table[i]
            let worse = table[i + 1]
            if value <= worse.0 {
                let ratio = (worse.0 - value) / max(0.0001, worse.0 - best.0)
                return worse.1 + ratio * (best.1 - worse.1)
            }
        }
        return 0
    }
}
