import BuctModel
import SwiftUI

private enum HomeworkFilterTab: String, CaseIterable {
    case pending = "待办"
    case homeworks = "作业"
    case tests = "测验"
    case local = "本地"
}

struct HomeworkView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: HomeworkFilterTab = .pending
    @State private var selectedHomework: TheolHomeworkItem?
    @State private var selectedTest: TheolTestItem?
    @State private var showAddTodo = false
    @State private var didAutoSync = false

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                VStack(spacing: 10) {
                    Picker("筛选", selection: $selectedTab) {
                        ForEach(HomeworkFilterTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if environment.currentProfile == nil {
                        Spacer()
                        VStack(spacing: 10) {
                            Text("未登录统一身份认证").font(.headline)
                            Text("登录后自动同步北化在线（THEOL）待交作业、测验 DDL 与课件资料")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("去登录") {
                                environment.showLoginSheet = true
                            }
                            .buttonStyle(.glassProminent)
                        }
                        .padding(24)
                        .buctGlassCard(cornerRadius: 24, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        .padding(.horizontal, 20)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                switch selectedTab {
                                case .pending:
                                    pendingContent
                                case .homeworks:
                                    homeworksContent
                                case .tests:
                                    testsContent
                                case .local:
                                    localContent
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                        .refreshable {
                            await environment.refreshTheol(userInitiated: true)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("作业待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("作业待办")
                        .font(.headline)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if environment.currentProfile != nil {
                        Button {
                            showAddTodo = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            Task { await environment.refreshTheol(userInitiated: true) }
                        } label: {
                            if environment.isSyncingTheol {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedHomework) { item in
                HomeworkDetailSheet(item: item)
            }
            .sheet(item: $selectedTest) { item in
                TestDetailSheet(item: item)
            }
            .sheet(isPresented: $showAddTodo) {
                AddLocalTodoSheet()
            }
            .onAppear {
                environment.trackVisit(path: "/tab/homework", title: "作业")
                if !didAutoSync,
                   let profile = environment.currentProfile,
                   profile.systemType == .undergradJwglxt,
                   !profile.isDemoMode,
                   environment.theolSlice.provenance.refreshState == .never {
                    didAutoSync = true
                    Task { await environment.refreshTheol(userInitiated: false) }
                }
            }
        }
    }

    private var visibleHomeworks: [TheolHomeworkItem] {
        (environment.theolSlice.data?.homeworks ?? [])
            .filter { !environment.theolFilterPrefs.hiddenHomeworkIds.contains($0.id) }
    }

    private var visibleTests: [TheolTestItem] {
        (environment.theolSlice.data?.tests ?? [])
            .filter { !environment.theolFilterPrefs.hiddenTestKeys.contains($0.id) }
    }

    @ViewBuilder
    private var pendingContent: some View {
        let pendingHw = visibleHomeworks.filter { $0.canSubmit }
        let pendingTests = visibleTests.filter { $0.canStart }
        let pendingLocal = environment.localTodos.filter { !$0.completed }

        if pendingHw.isEmpty && pendingTests.isEmpty && pendingLocal.isEmpty {
            emptyStateCard(
                environment.theolSlice.provenance.refreshState == .never
                    ? "尚未同步北化在线，请点击右上角刷新"
                    : "太棒了，当前没有待提交作业或测验！"
            )
        } else {
            ForEach(pendingLocal) { todo in
                localTodoCard(todo)
            }
            ForEach(pendingHw) { hw in
                homeworkCard(hw)
            }
            ForEach(pendingTests) { test in
                testCard(test)
            }
        }
    }

    @ViewBuilder
    private var homeworksContent: some View {
        if visibleHomeworks.isEmpty {
            emptyStateCard("暂无北化在线作业记录")
        } else {
            ForEach(visibleHomeworks) { hw in
                homeworkCard(hw)
            }
        }
    }

    @ViewBuilder
    private var testsContent: some View {
        if visibleTests.isEmpty {
            emptyStateCard("暂无在线测验记录")
        } else {
            ForEach(visibleTests) { test in
                testCard(test)
            }
        }
    }

    @ViewBuilder
    private var localContent: some View {
        if environment.localTodos.isEmpty {
            emptyStateCard("暂无本地待办，点击右上角 + 添加")
        } else {
            ForEach(environment.localTodos) { todo in
                localTodoCard(todo)
            }
        }
    }

    private func homeworkCard(_ item: TheolHomeworkItem) -> some View {
        Button {
            selectedHomework = item
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.courseName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    deadlineBadge(millis: item.deadlineMillis, status: item.status, canAct: item.canSubmit, completed: item.hasResult)
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack {
                    if !item.deadline.isEmpty {
                        Label("截止 \(item.deadline)", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !item.score.isEmpty {
                        Text("成绩：\(item.score)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("隐藏此作业", role: .destructive) {
                Task { await environment.hideTheolHomework(id: item.id) }
            }
        }
    }

    private func testCard(_ item: TheolTestItem) -> some View {
        Button {
            selectedTest = item
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(item.courseName) · 测验")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    deadlineBadge(millis: item.endTimeMillis, status: item.status, canAct: item.canStart, completed: item.hasResult)
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if !item.endTime.isEmpty {
                    Label("截止 \(item.endTime) · 时长 \(item.duration)", systemImage: "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("隐藏此测验", role: .destructive) {
                Task { await environment.hideTheolTest(key: item.id) }
            }
        }
    }

    private func localTodoCard(_ todo: LocalTodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await environment.toggleLocalTodo(id: todo.id) }
            } label: {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.completed ? .green : Color.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(todo.completed)
                    .foregroundStyle(todo.completed ? .secondary : .primary)
                if !todo.courseName.isEmpty || !todo.note.isEmpty {
                    Text([todo.courseName, todo.note].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                Task { await environment.deleteLocalTodo(id: todo.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func deadlineBadge(millis: Int64?, status: String, canAct: Bool, completed: Bool) -> some View {
        let (text, color): (String, Color) = {
            if completed { return ("已完成", .green) }
            guard canAct else { return (status.isEmpty ? "已截止" : status, .secondary) }
            guard let millis else { return ("待完成", Color.accentColor) }
            let diffHours = Int((millis - Int64(Date().timeIntervalSince1970 * 1000)) / 3_600_000)
            if diffHours <= 0 { return ("即将截止", .red) }
            if diffHours < 24 { return ("剩 \(diffHours) 小时", .red) }
            return ("剩 \(diffHours / 24) 天", diffHours < 72 ? .orange : Color.accentColor)
        }()
        return Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func emptyStateCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(28)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }
}

struct HomeworkDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let item: TheolHomeworkItem
    @State private var detail: TheolHomeworkDetail?
    @State private var isLoading = true
    @State private var errorMsg = ""
    @State private var downloadingURL: String?
    @State private var previewFile: QuickLookFileItem?
    @State private var webLaunchContext: TheolWebLaunchContext?
    @State private var isOpeningWeb = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.courseName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(detail?.title ?? item.title)
                            .font(.title3.weight(.bold))
                        if !item.deadline.isEmpty {
                            Label("截止时间：\(item.deadline)", systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !item.publisher.isEmpty {
                            Label("发布人：\(item.publisher)", systemImage: "person")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

                    if isLoading {
                        ProgressView("正在加载作业详情...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let detail {
                        if !detail.contentText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("作业要求")
                                    .font(.subheadline.weight(.semibold))
                                Text(detail.contentText)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }

                        if !detail.attachments.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("作业附件")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(detail.attachments) { att in
                                    Button {
                                        Task { await downloadAndPreview(att) }
                                    } label: {
                                        HStack {
                                            Image(systemName: "doc.fill")
                                                .foregroundStyle(Color.accentColor)
                                            Text(att.name)
                                                .font(.caption.weight(.medium))
                                                .lineLimit(2)
                                            Spacer()
                                            if downloadingURL == att.url {
                                                ProgressView().controlSize(.small)
                                            } else {
                                                Image(systemName: "arrow.down.circle")
                                                    .foregroundStyle(Color.accentColor)
                                            }
                                        }
                                        .padding(10)
                                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }
                    }

                    let targetWebURL = item.submitHref.isEmpty ? item.detailHref : item.submitHref
                    if !targetWebURL.isEmpty {
                        Button {
                            Task { await openInAppWeb(urlString: targetWebURL) }
                        } label: {
                            HStack(spacing: 8) {
                                if isOpeningWeb {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "globe")
                                }
                                Text(isOpeningWeb ? "正在注入登录态..." : "应用内免登打开提交页")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(isOpeningWeb)
                    }
                }
                .padding(16)
            }
            .navigationTitle("作业详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $previewFile) { item in
                QuickLookPreviewSheet(fileURL: item.url)
            }
            .sheet(item: $webLaunchContext) { ctx in
                TheolWebViewSheet(context: ctx)
            }
            .task {
                guard let profile = environment.currentProfile else { return }
                isLoading = true
                do {
                    detail = try await environment.campusSync.fetchTheolHomeworkDetail(profile: profile, item: item)
                } catch {
                    errorMsg = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func downloadAndPreview(_ att: TheolHomeworkAttachment) async {
        guard let profile = environment.currentProfile else { return }
        downloadingURL = att.url
        defer { downloadingURL = nil }
        do {
            let file = try await environment.campusSync.downloadTheolFile(
                profile: profile,
                urlString: att.url,
                courseLid: item.lid,
                referer: item.detailHref
            )
            if file.isHtmlPage {
                await openInAppWeb(urlString: att.url)
            } else if !file.filePath.isEmpty {
                previewFile = QuickLookFileItem(url: URL(fileURLWithPath: file.filePath))
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func openInAppWeb(urlString: String) async {
        guard let profile = environment.currentProfile else { return }
        isOpeningWeb = true
        defer { isOpeningWeb = false }
        do {
            webLaunchContext = try await environment.campusSync.prepareTheolWebLaunchContext(
                profile: profile,
                urlString: urlString,
                title: item.title,
                courseLid: item.lid,
                touchHomework: true
            )
        } catch {
            errorMsg = error.localizedDescription
            if let fallback = URL(string: urlString) {
                openURL(fallback)
            }
        }
    }
}

struct TestDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let item: TheolTestItem
    @State private var detail: TheolTestDetail?
    @State private var webLaunchContext: TheolWebLaunchContext?
    @State private var isOpeningWeb = false

    var body: some View {
        NavigationStack {
            List {
                Section("测验信息") {
                    LabeledContent("课程", value: item.courseName)
                    LabeledContent("标题", value: detail?.title ?? item.title)
                    LabeledContent("状态", value: item.status)
                    if !item.startTime.isEmpty { LabeledContent("开始时间", value: item.startTime) }
                    if !item.endTime.isEmpty { LabeledContent("结束时间", value: item.endTime) }
                    if !item.duration.isEmpty { LabeledContent("考试时长", value: item.duration) }
                    if let ts = detail?.totalScore, !ts.isEmpty { LabeledContent("总分", value: ts) }
                    if let qc = detail?.questionCount, !qc.isEmpty { LabeledContent("题目数", value: qc) }
                }
                if let desc = detail?.description, !desc.isEmpty {
                    Section("测验说明") {
                        Text(desc).font(.footnote)
                    }
                }
                if !item.testUrl.isEmpty {
                    Section {
                        Button {
                            Task { await openTestInApp() }
                        } label: {
                            HStack(spacing: 8) {
                                if isOpeningWeb { ProgressView().controlSize(.small) }
                                Text(isOpeningWeb ? "正在注入登录态..." : "应用内免登打开在线测验")
                            }
                        }
                        .disabled(isOpeningWeb)
                    }
                }
            }
            .navigationTitle("测验详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .sheet(item: $webLaunchContext) { ctx in
                TheolWebViewSheet(context: ctx)
            }
            .task {
                guard let profile = environment.currentProfile else { return }
                detail = try? await environment.campusSync.fetchTheolTestDetail(profile: profile, item: item)
            }
        }
    }

    private func openTestInApp() async {
        guard let profile = environment.currentProfile else { return }
        isOpeningWeb = true
        defer { isOpeningWeb = false }
        do {
            webLaunchContext = try await environment.campusSync.prepareTheolWebLaunchContext(
                profile: profile,
                urlString: item.testUrl,
                title: item.title,
                courseLid: item.lid,
                touchHomework: false
            )
        } catch {
            if let url = URL(string: item.testUrl) {
                openURL(url)
            }
        }
    }
}

private struct AddLocalTodoSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var courseName = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("待办事项", text: $title)
                TextField("所属课程（可选）", text: $courseName)
                TextField("备注（可选）", text: $note)
            }
            .navigationTitle("添加本地待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let todo = LocalTodoItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            courseName: courseName.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        Task {
                            await environment.addLocalTodo(todo)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
