import BuctModel
import Foundation

public actor AcademicDataStore {
    private let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AppContainerResolver.resolveRootDirectory().url
    }

    public func scheduleStore(accountKey: String, termId: String) -> DomainSliceStore<[ScheduleCourse]> {
        DomainSliceStore(
            source: "academic_schedule",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("schedule_\(sanitize(termId)).json")
        )
    }

    public func loadCustomCourses(accountKey: String, termId: String) -> [ScheduleCourse] {
        let url = accountDirectory(accountKey).appendingPathComponent("custom_schedule_\(sanitize(termId)).json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([ScheduleCourse].self, from: data)) ?? []
    }

    public func saveCustomCourses(_ courses: [ScheduleCourse], accountKey: String, termId: String) throws {
        let dir = accountDirectory(accountKey)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("custom_schedule_\(sanitize(termId)).json")
        let data = try encoder.encode(courses)
        try data.write(to: url, options: [.atomic])
    }

    public func semesterGradesStore(accountKey: String, termId: String) -> DomainSliceStore<[GradeItem]> {
        DomainSliceStore(
            source: "academic_grades",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("grades_\(sanitize(termId)).json")
        )
    }

    public func overallAcademicStore(accountKey: String) -> DomainSliceStore<OverallAcademicBundle> {
        DomainSliceStore(
            source: "academic_overall",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("overall_academic.json")
        )
    }

    public func examsStore(accountKey: String, termId: String) -> DomainSliceStore<[ExamItem]> {
        DomainSliceStore(
            source: "academic_exams",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("exams_\(sanitize(termId)).json")
        )
    }

    public func loadCustomExams(accountKey: String) -> [ExamItem] {
        let url = accountDirectory(accountKey).appendingPathComponent("custom_exams.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([ExamItem].self, from: data)) ?? []
    }

    public func saveCustomExams(_ exams: [ExamItem], accountKey: String) throws {
        let dir = accountDirectory(accountKey)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("custom_exams.json")
        let data = try encoder.encode(exams)
        try data.write(to: url, options: [.atomic])
    }

    public func officialCalendarStore() -> DomainSliceStore<OfficialCalendarSnapshot> {
        DomainSliceStore(
            source: "portal_calendar",
            parserVersion: 2,
            fileURL: rootDirectory.appendingPathComponent("portal_official_calendar.json")
        )
    }

    private func accountDirectory(_ accountKey: String) -> URL {
        rootDirectory
            .appendingPathComponent("academic", isDirectory: true)
            .appendingPathComponent(sanitize(accountKey), isDirectory: true)
    }

    private func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "[^A-Za-z0-9_\\-]", with: "_", options: .regularExpression)
    }
}
