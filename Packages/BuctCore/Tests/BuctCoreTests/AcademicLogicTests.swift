@testable import BuctModel
import XCTest

final class AcademicLogicTests: XCTestCase {

    func testScheduleWeeksParsingOddEvenPerSegment() {
        XCTAssertEqual(ScheduleWeeks.parse("1-4周(单),6-8周(双),10"), [1, 3, 6, 8, 10])
        XCTAssertEqual(ScheduleWeeks.parse("第1~3周"), [1, 2, 3])
        XCTAssertEqual(ScheduleWeeks.parse("1-2周(单双)"), [])
    }

    func testScheduleDatesMondayAndTeachingWeek() {
        // 2026-03-04 为周三，规范化后应退回 2026-03-02（周一）
        XCTAssertEqual(ScheduleDates.normalizeFirstWeekMonday("2026-03-04"), "2026-03-02")
        let monday = ScheduleDates.parseUTCDate("2026-03-02")!
        XCTAssertEqual(ScheduleDates.weekAt(firstWeekMonday: "2026-03-02", now: monday), 1)
        let week3Day = Calendar(identifier: .gregorian).date(byAdding: .day, value: 14, to: monday)!
        XCTAssertEqual(ScheduleDates.weekAt(firstWeekMonday: "2026-03-02", now: week3Day), 3)
    }

    func testBuctGpaScaleAndExclusions() {
        XCTAssertEqual(BuctGpaScale.gradePointFromScore("96"), 4.33)
        XCTAssertEqual(BuctGpaScale.gradePointFromScore("85"), 3.67)
        XCTAssertEqual(BuctGpaScale.gradePointFromScore("59"), 0.00)
        XCTAssertEqual(BuctGpaScale.gradePointFromScore("优秀"), 4.00)

        let grades = [
            GradeItem(id: "1", courseCode: "CS101", courseName: "程序设计", score: "95", credits: 4.0, courseType: "专业必修", year: "2024", term: "3"),
            GradeItem(id: "2", courseCode: "CS101", courseName: "程序设计", score: "80", credits: 4.0, courseType: "专业必修", year: "2024", term: "12"), // 应保留最佳成绩 95
            GradeItem(id: "3", courseCode: "PE101", courseName: "体育 I", score: "95", credits: 1.0, courseType: "通识必修", year: "2024", term: "3"), // 体育排除
            GradeItem(id: "4", courseCode: "PHE101", courseName: "军事理论", score: "90", credits: 2.0, courseType: "通识必修", year: "2024", term: "3"), // 军事理论保留
            GradeItem(id: "5", courseCode: "SZ101", courseName: "通识讲座", score: "95", credits: 1.0, courseType: "素质教育", year: "2024", term: "3"), // 素质教育排除
            GradeItem(id: "6", courseCode: "LAB101", courseName: "金工实习", score: "合格", credits: 2.0, courseType: "实践", year: "2024", term: "3") // 两级制排除
        ]

        let stats = BuctGpaScale.computeWeightedGpa(grades)
        // (4.0 * 4.33 + 2.0 * 4.00) / 6.0 = 25.32 / 6.0 = 4.22
        XCTAssertEqual(stats.credits, 6.0, accuracy: 1e-6)
        XCTAssertEqual(stats.gpa, 4.22, accuracy: 1e-4)

        let estimate = BuctGpaScale.estimateTargetGpa(
            grades: grades,
            officialGpa: nil,
            targetGpa: 4.25,
            plannedCredits: 6.0
        )
        XCTAssertEqual(estimate.requiredGpa, 4.28, accuracy: 1e-3)
        XCTAssertTrue(estimate.achievable)
    }

    func testDemoDataConsistency() {
        let bundle = DemoData.overallBundle()
        XCTAssertEqual(DemoData.scheduleCourses().count, 13)
        XCTAssertEqual(bundle.grades.count, 10)
        XCTAssertEqual(DemoData.exams().count, 4)
        XCTAssertEqual(DemoData.emptyClassrooms(campus: .all).count, 4)
    }

    func testCurriculumTreeBuilderDeduplicatesAndPreventsCycles() {
        let courseA = CurriculumCourse(id: "C1|高数", courseCode: "C1", courseName: "高数", credits: 4, studyStatus: "4", grade: "90")
        let nodes: [CurriculumNode] = [
            CurriculumNode(id: "root", parentId: "", name: "培养方案", isLeaf: false, earnedCredits: 10, requiredCredits: 100, passed: false),
            CurriculumNode(id: "m1", parentId: "root", name: "模块一", isLeaf: false, earnedCredits: 4, requiredCredits: 20, passed: false),
            CurriculumNode(id: "m1", parentId: "root", name: "模块一", isLeaf: false, earnedCredits: 4, requiredCredits: 20, passed: false),
            CurriculumNode(id: "m1", parentId: "root", name: "模块一", isLeaf: false, earnedCredits: 4, requiredCredits: 20, passed: false),
            CurriculumNode(id: "m2", parentId: "m1", name: "模块二", isLeaf: true, earnedCredits: 4, requiredCredits: 10, passed: false, courses: [courseA]),
            CurriculumNode(id: "m2", parentId: "m1", name: "模块二", isLeaf: true, earnedCredits: 4, requiredCredits: 10, passed: false, courses: [courseA]),
            CurriculumNode(id: "cycA", parentId: "cycB", name: "环A", isLeaf: false, earnedCredits: 0, requiredCredits: 5, passed: false),
            CurriculumNode(id: "cycB", parentId: "cycA", name: "环B", isLeaf: false, earnedCredits: 0, requiredCredits: 5, passed: false),
            CurriculumNode(id: "selfC", parentId: "selfC", name: "自环C", isLeaf: true, earnedCredits: 0, requiredCredits: 2, passed: false)
        ]

        let expandable = CurriculumTreeBuilder.expandableIds(nodes: nodes)
        XCTAssertEqual(expandable, ["m1", "m2", "cycA", "cycB"])

        let entries = CurriculumTreeBuilder.buildVisibleTree(
            nodes: nodes,
            expandedIds: Set(nodes.map(\.id))
        )
        XCTAssertEqual(entries.map(\.id), ["m1", "m2"])
        XCTAssertEqual(entries.last?.node.courses.count, 1)
    }
}
