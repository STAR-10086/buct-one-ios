import BuctModel
import SwiftUI
import UniformTypeIdentifiers

struct TaskImportSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var rawText = ""
    @State private var report: TaskImportReport?
    @State private var showFileImporter = false
    @State private var fileError = ""
    @State private var templateURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section("导入方式") {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("从「文件」选择 CSV / TSV 表格", systemImage: "doc.badge.plus")
                    }

                    if let templateURL {
                        ShareLink(item: templateURL) {
                            Label("导出标准 CSV 模板", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button {
                        rawText = TaskTableParser.standardTemplateCSV
                        parseNow()
                    } label: {
                        Label("填入示例表格预览", systemImage: "text.badge.plus")
                    }
                }

                Section("粘贴表格内容（CSV / TSV）") {
                    TextEditor(text: $rawText)
                        .font(.caption.monospaced())
                        .frame(minHeight: 110)

                    Button("解析预览") {
                        parseNow()
                    }
                    .disabled(rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if !fileError.isEmpty {
                        Text(fileError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let report {
                    Section("解析结果（共 \(report.totalImportedCount) 项）") {
                        if !report.tasks.isEmpty {
                            ForEach(report.tasks) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.courseName.isEmpty ? "待办" : item.courseName)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Color.accentColor)
                                        Spacer()
                                        if !item.deadlineText.isEmpty {
                                            Text(item.deadlineText)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(item.title)
                                        .font(.subheadline.weight(.medium))
                                    if !item.note.isEmpty {
                                        Text(item.note)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        if !report.exams.isEmpty {
                            ForEach(report.exams) { exam in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("考试 · \(exam.courseName)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                        Spacer()
                                        Text(exam.examTime)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(exam.examName)
                                        .font(.subheadline.weight(.medium))
                                    if !exam.location.isEmpty {
                                        Text(exam.location)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        if report.tasks.isEmpty && report.exams.isEmpty {
                            Text("未识别到可导入的任务或考试记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !report.warnings.isEmpty {
                        Section("提示（\(report.warnings.count)）") {
                            ForEach(report.warnings, id: \.self) { warn in
                                Text(warn)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("表格批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认导入") {
                        guard let report, report.totalImportedCount > 0 else { return }
                        Task {
                            await environment.importTasksAndExams(tasks: report.tasks, exams: report.exams)
                            dismiss()
                        }
                    }
                    .disabled((report?.totalImportedCount ?? 0) == 0)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        if let utf8 = String(data: data, encoding: .utf8) {
                            rawText = utf8
                        } else {
                            let cfEnc = CFStringConvertEncodingToNSStringEncoding(
                                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
                            )
                            rawText = String(data: data, encoding: String.Encoding(rawValue: cfEnc)) ?? ""
                        }
                        fileError = ""
                        parseNow()
                    } catch {
                        fileError = "读取文件失败：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    fileError = "选择文件失败：\(error.localizedDescription)"
                }
            }
            .onAppear {
                prepareTemplateFile()
            }
        }
    }

    private func parseNow() {
        report = TaskTableParser.parse(text: rawText, existingTodos: environment.localTodos)
    }

    private func prepareTemplateFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("buct-one-tasks-template.csv")
        let bom = "\u{FEFF}" + TaskTableParser.standardTemplateCSV
        try? bom.write(to: url, atomically: true, encoding: .utf8)
        templateURL = url
    }
}
