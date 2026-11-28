import BuctModel
import Foundation
import Testing

struct M4ToolsTests {
    @Test func taskTableParserParsesTemplateAndSplitsExams() {
        let report = TaskTableParser.parse(text: TaskTableParser.standardTemplateCSV)
        #expect(report.tasks.count == 2)
        #expect(report.exams.count == 1)
        #expect(report.tasks[0].courseName == "高等数学")
        #expect(report.tasks[0].title == "第七章习题 1-10")
        #expect(report.tasks[0].deadlineMillis != nil)
        #expect(report.exams[0].courseName == "线性代数")
        #expect(report.exams[0].examName == "期中考试")
        #expect(report.exams[0].location == "教A-201")
    }

    @Test func taskTableParserInheritsCourseAndDeduplicates() {
        let csv = """
        类型,课程名称,任务内容,截止时间
        作业,大学物理,作业1,2026-10-10 23:59
        作业,,作业2,2026-10-17 23:59
        作业,大学物理,作业1,2026-10-10 23:59
        """
        let existing = [LocalTodoItem(title: "作业2", courseName: "大学物理")]
        let report = TaskTableParser.parse(text: csv, existingTodos: existing)
        #expect(report.tasks.count == 1)
        #expect(report.tasks[0].title == "作业1")
        #expect(report.skippedRows == 2)
    }

    @Test func icalExporterGeneratesValidVCalendarEvents() {
        let term = AcademicTerm(year: 2026, semester: 1)
        let course = ScheduleCourse(
            id: "c1",
            name: "高等数学,上",
            teacher: "张老师",
            location: "东区主教B-201",
            dayOfWeek: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeksText: "1-2周",
            weeks: [1, 2]
        )
        let ics = ICalExporter.exportSchedule(
            courses: [course],
            term: term,
            firstWeekMonday: "2026-09-07"
        )
        #expect(ics.contains("BEGIN:VCALENDAR"))
        #expect(ics.contains("END:VCALENDAR"))
        #expect(ics.contains("TZID:Asia/Shanghai"))
        #expect(ics.contains("DTSTART;TZID=Asia/Shanghai:20260907T080000"))
        #expect(ics.contains("DTEND;TZID=Asia/Shanghai:20260907T093500"))
        #expect(ics.contains("DTSTART;TZID=Asia/Shanghai:20260914T080000"))
        #expect(ics.contains("SUMMARY:高等数学\\,上"))
        #expect(ics.contains("LOCATION:东区主教B-201"))
    }

    @Test func theolFilterPrefsDecodesLegacyPayloadBackwardCompatibly() throws {
        let legacyJSON = #"{"hiddenHomeworkIds":["1:100"],"hiddenTestKeys":["1:200"]}"#
        let decoded = try JSONDecoder().decode(TheolFilterPrefs.self, from: Data(legacyJSON.utf8))
        #expect(decoded.hiddenHomeworkIds == ["1:100"])
        #expect(decoded.hiddenTestKeys == ["1:200"])
        #expect(decoded.hiddenCourseNames.isEmpty)
        #expect(decoded.hiddenExperimentIds.isEmpty)
    }
}
