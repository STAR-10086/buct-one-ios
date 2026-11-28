import Foundation

public struct ImportedTaskDraft: Sendable, Equatable, Identifiable {
    public let id: String
    public let courseName: String
    public let title: String
    public let deadlineText: String
    public let deadlineMillis: Int64?
    public let note: String
    public let rowNumber: Int

    public init(
        id: String = UUID().uuidString,
        courseName: String,
        title: String,
        deadlineText: String = "",
        deadlineMillis: Int64? = nil,
        note: String = "",
        rowNumber: Int = 0
    ) {
        self.id = id
        self.courseName = courseName
        self.title = title
        self.deadlineText = deadlineText
        self.deadlineMillis = deadlineMillis
        self.note = note
        self.rowNumber = rowNumber
    }

    public func toLocalTodo() -> LocalTodoItem {
        LocalTodoItem(
            title: title,
            courseName: courseName,
            deadlineMillis: deadlineMillis,
            completed: false,
            note: note
        )
    }
}

public struct ImportedExamDraft: Sendable, Equatable, Identifiable {
    public let id: String
    public let courseName: String
    public let examName: String
    public let examTime: String
    public let location: String
    public let note: String
    public let rowNumber: Int

    public init(
        id: String = UUID().uuidString,
        courseName: String,
        examName: String,
        examTime: String = "",
        location: String = "",
        note: String = "",
        rowNumber: Int = 0
    ) {
        self.id = id
        self.courseName = courseName
        self.examName = examName
        self.examTime = examTime
        self.location = location
        self.note = note
        self.rowNumber = rowNumber
    }

    public func toExamItem() -> ExamItem {
        ExamItem(
            id: "import-exam-\(UUID().uuidString)",
            courseName: courseName.isEmpty ? examName : courseName,
            examTime: examTime,
            location: location,
            seatNumber: note,
            examName: examName,
            isCustom: true
        )
    }
}

public struct TaskImportReport: Sendable, Equatable {
    public let tasks: [ImportedTaskDraft]
    public let exams: [ImportedExamDraft]
    public let skippedRows: Int
    public let warnings: [String]

    public var totalImportedCount: Int { tasks.count + exams.count }

    public init(
        tasks: [ImportedTaskDraft] = [],
        exams: [ImportedExamDraft] = [],
        skippedRows: Int = 0,
        warnings: [String] = []
    ) {
        self.tasks = tasks
        self.exams = exams
        self.skippedRows = skippedRows
        self.warnings = warnings
    }
}

/// 纯 Swift RFC-4180 CSV / TSV 任务与考试表格解析器（对齐安卓版 TaskTableParser.kt）。
public enum TaskTableParser {
    public static let standardTemplateCSV: String = """
    类型,课程名称,任务内容,截止时间,提交方式,适用范围,地点,备注,链接
    作业,高等数学,第七章习题 1-10,2026-10-20 23:59,纸质版,全体,,课前交给学委,
    实验,大学物理实验,迈克尔逊干涉仪实验报告,2026-10-22 18:00,实践教学平台,全体,东区实验楼B302,,
    考试,线性代数,期中考试,2026-11-05 14:00-16:00,闭卷,全体,教A-201,带2B铅笔与学生证,
    """

    public static func parse(text: String, existingTodos: [LocalTodoItem] = []) -> TaskImportReport {
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let delimiter = detectDelimiter(in: cleaned)
        let rawRows = parseDelimitedRows(cleaned, delimiter: delimiter)
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

        guard !rawRows.isEmpty else {
            return TaskImportReport(warnings: ["表格内容为空"])
        }

        let firstRow = rawRows[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let headerMap = detectHeaderColumns(firstRow)
        let hasHeader = !headerMap.isEmpty
        let startIndex = hasHeader ? 1 : 0

        let typeIdx = headerMap["type"] ?? 0
        let courseIdx = headerMap["course"] ?? 1
        let titleIdx = headerMap["title"] ?? 2
        let deadlineIdx = headerMap["deadline"] ?? 3
        let submitIdx = headerMap["submit"] ?? 4
        let scopeIdx = headerMap["scope"] ?? 5
        let locationIdx = headerMap["location"] ?? 6
        let noteIdx = headerMap["note"] ?? 7
        let linkIdx = headerMap["link"] ?? 8

        var tasks: [ImportedTaskDraft] = []
        var exams: [ImportedExamDraft] = []
        var warnings: [String] = []
        var skipped = 0
        var lastCourseName = ""

        var seenKeys: Set<String> = Set(existingTodos.map {
            "\($0.courseName.lowercased())::\($0.title.lowercased())"
        })

        for rowOffset in startIndex..<rawRows.count {
            let row = rawRows[rowOffset]
            let rowNumber = rowOffset + 1

            let rawType = cell(row, typeIdx)
            var course = cell(row, courseIdx)
            var title = cell(row, titleIdx)
            let deadline = cell(row, deadlineIdx)
            let submit = cell(row, submitIdx)
            let scope = cell(row, scopeIdx)
            let location = cell(row, locationIdx)
            let note = cell(row, noteIdx)
            let link = cell(row, linkIdx)

            // 兼容 2-3 列简化格式（无“类型”列时：课程,任务,截止时间）
            if !hasHeader && row.count <= 3 {
                course = cell(row, 0)
                title = cell(row, 1)
            }

            if course.isEmpty && !lastCourseName.isEmpty {
                course = lastCourseName
            } else if !course.isEmpty {
                lastCourseName = course
            }

            if title.isEmpty {
                skipped += 1
                warnings.append("第 \(rowNumber) 行缺少任务内容，已跳过")
                continue
            }

            let isExam = rawType.contains("考") || title.contains("期中考试") || title.contains("期末考试")
            if isExam {
                let extraNote = [submit, scope, note].filter { !$0.isEmpty }.joined(separator: " · ")
                exams.append(ImportedExamDraft(
                    courseName: course,
                    examName: title,
                    examTime: deadline,
                    location: location,
                    note: extraNote,
                    rowNumber: rowNumber
                ))
            } else {
                let dedupKey = "\(course.lowercased())::\(title.lowercased())"
                if seenKeys.contains(dedupKey) {
                    skipped += 1
                    warnings.append("第 \(rowNumber) 行「\(title)」已存在，已自动去重")
                    continue
                }
                seenKeys.insert(dedupKey)

                let noteParts = [
                    rawType.isEmpty ? nil : rawType,
                    submit.isEmpty ? nil : "提交：\(submit)",
                    scope.isEmpty ? nil : "范围：\(scope)",
                    location.isEmpty ? nil : "地点：\(location)",
                    note.isEmpty ? nil : note,
                    link.isEmpty ? nil : link
                ].compactMap { $0 }

                let deadlineMillis = parseFlexibleDeadlineMillis(deadline)
                tasks.append(ImportedTaskDraft(
                    courseName: course,
                    title: title,
                    deadlineText: deadline,
                    deadlineMillis: deadlineMillis,
                    note: noteParts.joined(separator: " · "),
                    rowNumber: rowNumber
                ))
            }
        }

        return TaskImportReport(tasks: tasks, exams: exams, skippedRows: skipped, warnings: warnings)
    }

    private static func cell(_ row: [String], _ index: Int) -> String {
        guard index >= 0 && index < row.count else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let tabs = firstLine.filter { $0 == "\t" }.count
        let commas = firstLine.filter { $0 == "," || $0 == "，" }.count
        return tabs > commas ? "\t" : ","
    }

    private static func detectHeaderColumns(_ row: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, raw) in row.enumerated() {
            let h = raw.lowercased()
            if h.contains("类型") || h == "type" { map["type"] = i }
            else if h.contains("课程") || h == "course" { map["course"] = i }
            else if h.contains("任务") || h.contains("内容") || h.contains("标题") || h == "title" { map["title"] = i }
            else if h.contains("截止") || h.contains("时间") || h == "ddl" || h == "deadline" { map["deadline"] = i }
            else if h.contains("提交") || h.contains("方式") { map["submit"] = i }
            else if h.contains("范围") { map["scope"] = i }
            else if h.contains("地点") || h.contains("教室") { map["location"] = i }
            else if h.contains("备注") || h == "note" { map["note"] = i }
            else if h.contains("链接") || h == "url" || h == "link" { map["link"] = i }
        }
        return map.count >= 2 ? map : [:]
    }

    private static func parseDelimitedRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(ch)
                }
            } else {
                if ch == "\"" && currentField.isEmpty {
                    inQuotes = true
                } else if ch == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                } else if ch == "\r" {
                    if i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                } else if ch == "\n" {
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(ch)
                }
            }
            i += 1
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }

    public static func parseFlexibleDeadlineMillis(_ raw: String) -> Int64? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "年", with: "-")
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-M-d HH:mm",
            "yyyy-MM-dd",
            "yyyy-M-d"
        ]
        let tz = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = tz
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: normalized) {
                return Int64(date.timeIntervalSince1970 * 1000)
            }
        }
        return nil
    }
}
