import Foundation

public struct GpaTrendPoint: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let shortLabel: String
    public let gpa: Double
    public let credits: Double
    public let courseCount: Int
}

public struct TargetGpaEstimate: Sendable, Equatable {
    public let currentGpa: Double
    public let currentCredits: Double
    public let requiredGpa: Double
    public let achievable: Bool
    public let alreadyReached: Bool
}

public enum BuctGpaScale {
    public static let maxGpa: Double = 4.33

    public static func gradePointFromScore(_ rawScore: String, numericFallback: String = "") -> Double? {
        let token = rawScore.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let num = Double(token) ?? Double(numericFallback.trimmingCharacters(in: .whitespacesAndNewlines)) {
            switch num {
            case 95...: return 4.33
            case 90..<95: return 4.00
            case 85..<90: return 3.67
            case 82..<85: return 3.33
            case 78..<82: return 3.00
            case 75..<78: return 2.67
            case 72..<75: return 2.33
            case 68..<72: return 2.00
            case 64..<68: return 1.67
            case 61..<64: return 1.33
            case 60..<61: return 1.00
            default: return 0.00
            }
        }
        switch token {
        case "A+": return 4.33
        case "A", "优秀", "优": return 4.00
        case "A-": return 3.67
        case "B+": return 3.33
        case "B", "良好", "良": return 3.00
        case "B-": return 2.67
        case "C+": return 2.33
        case "C", "中等", "中": return 2.00
        case "C-": return 1.67
        case "D+": return 1.33
        case "D", "及格": return 1.00
        case "F", "E", "不及格": return 0.00
        default: return nil
        }
    }

    public static func isCreditEarned(_ rawScore: String) -> Bool {
        let token = rawScore.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let num = Double(token) {
            return num >= 60.0
        }
        let passTokens: Set<String> = [
            "合格", "及格", "通过", "P", "PASS",
            "优秀", "优", "良好", "良", "中等", "中",
            "A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D"
        ]
        return passTokens.contains(token)
    }

    public static func isGpaExcluded(_ item: GradeItem) -> Bool {
        if item.courseType.contains("素质教育") {
            return true
        }
        if item.courseName.contains("体育") {
            return true
        }
        let token = item.score.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let excludedTokens: Set<String> = [
            "", "--", "NULL", "未出分", "缓考", "缺考", "免修",
            "合格", "不合格", "通过", "不通过", "未通过", "P", "U", "PASS", "UNPASS"
        ]
        return excludedTokens.contains(token)
    }

    public static func effectiveGpaPoint(_ item: GradeItem) -> Double? {
        if isGpaExcluded(item) { return nil }
        if let jd = item.serverGpa, jd >= 0 {
            return jd
        }
        if item.examNature.contains("补考"), isCreditEarned(item.score) {
            return 1.0
        }
        return gradePointFromScore(item.score)
    }

    public static func deduplicateBestAttempts(_ items: [GradeItem]) -> [GradeItem] {
        var bestByKey: [String: GradeItem] = [:]
        var orderedKeys: [String] = []

        for item in items {
            let key: String
            let code = item.courseCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !code.isEmpty {
                key = "code:\(code)"
            } else {
                key = "name:\(item.courseName.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
            if let existing = bestByKey[key] {
                if isBetterAttempt(item, than: existing) {
                    bestByKey[key] = item
                }
            } else {
                orderedKeys.append(key)
                bestByKey[key] = item
            }
        }
        return orderedKeys.compactMap { bestByKey[$0] }
    }

    private static func isBetterAttempt(_ lhs: GradeItem, than rhs: GradeItem) -> Bool {
        let lp = effectiveGpaPoint(lhs) ?? -1
        let rp = effectiveGpaPoint(rhs) ?? -1
        if abs(lp - rp) > 1e-6 { return lp > rp }

        let ls = Double(lhs.score) ?? -1
        let rs = Double(rhs.score) ?? -1
        if abs(ls - rs) > 1e-6 { return ls > rs }

        let lt = (Int(lhs.year) ?? 0) * 100 + (Int(lhs.term) ?? 0)
        let rt = (Int(rhs.year) ?? 0) * 100 + (Int(rhs.term) ?? 0)
        return lt > rt
    }

    public static func computeWeightedGpa(_ items: [GradeItem]) -> (gpa: Double, credits: Double) {
        let deduped = deduplicateBestAttempts(items)
        var totalCredits = 0.0
        var weightedSum = 0.0
        for item in deduped {
            guard item.credits > 0, let pt = effectiveGpaPoint(item) else { continue }
            totalCredits += item.credits
            weightedSum += item.credits * pt
        }
        guard totalCredits > 0 else { return (0, 0) }
        return (weightedSum / totalCredits, totalCredits)
    }

    public static func buildYearlyGpaTrend(_ items: [GradeItem]) -> [GpaTrendPoint] {
        let grouped = Dictionary(grouping: items.filter { !$0.year.isEmpty }) { $0.year }
        let sortedKeys = grouped.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        var accumulated: [GradeItem] = []
        var points: [GpaTrendPoint] = []

        for year in sortedKeys {
            accumulated.append(contentsOf: grouped[year] ?? [])
            let stats = computeWeightedGpa(accumulated)
            guard stats.credits > 0 else { continue }
            let yInt = Int(year) ?? 2025
            let short = String(format: "%02d-%02d", yInt % 100, (yInt + 1) % 100)
            points.append(
                GpaTrendPoint(
                    id: year,
                    label: "\(yInt)-\(yInt + 1)",
                    shortLabel: short,
                    gpa: stats.gpa,
                    credits: stats.credits,
                    courseCount: deduplicateBestAttempts(accumulated).count
                )
            )
        }
        return points
    }

    public static func buildTermGpaTrend(_ items: [GradeItem]) -> [GpaTrendPoint] {
        let valid = items.filter { !$0.year.isEmpty && !$0.term.isEmpty }
        let grouped = Dictionary(grouping: valid) { "\($0.year)|\($0.term)" }
        let sortedKeys = grouped.keys.sorted { lhs, rhs in
            let lp = lhs.split(separator: "|")
            let rp = rhs.split(separator: "|")
            let ly = Int(lp.first ?? "") ?? 0
            let ry = Int(rp.first ?? "") ?? 0
            if ly != ry { return ly < ry }
            let lt = Int(lp.last ?? "") ?? 0
            let rt = Int(rp.last ?? "") ?? 0
            return lt < rt
        }

        var accumulated: [GradeItem] = []
        var points: [GpaTrendPoint] = []
        for key in sortedKeys {
            accumulated.append(contentsOf: grouped[key] ?? [])
            let stats = computeWeightedGpa(accumulated)
            guard stats.credits > 0 else { continue }
            let parts = key.split(separator: "|")
            let yInt = Int(parts.first ?? "") ?? 2025
            let termRaw = String(parts.last ?? "")
            let semText = termRaw == "3" ? "1" : (termRaw == "12" ? "2" : "小")
            let short = String(format: "%02d-%02d·%@", yInt % 100, (yInt + 1) % 100, semText)
            points.append(
                GpaTrendPoint(
                    id: key,
                    label: "\(yInt)-\(yInt + 1) 第\(semText)学期",
                    shortLabel: short,
                    gpa: stats.gpa,
                    credits: stats.credits,
                    courseCount: deduplicateBestAttempts(accumulated).count
                )
            )
        }
        return points
    }

    public static func estimateTargetGpa(
        grades: [GradeItem],
        officialGpa: Double?,
        targetGpa: Double,
        plannedCredits: Double
    ) -> TargetGpaEstimate {
        let computed = computeWeightedGpa(grades)
        let currentCredits = computed.credits
        let currentGpa = officialGpa ?? computed.gpa
        let baseWeighted = currentGpa * currentCredits
        let safePlan = max(plannedCredits, 1.0)
        let required = (targetGpa * (currentCredits + safePlan) - baseWeighted) / safePlan
        return TargetGpaEstimate(
            currentGpa: currentGpa,
            currentCredits: currentCredits,
            requiredGpa: required,
            achievable: required <= maxGpa + 1e-4,
            alreadyReached: currentCredits > 0 && currentGpa >= targetGpa - 1e-6
        )
    }
}
