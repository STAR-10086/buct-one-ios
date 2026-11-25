import BuctModel
import SwiftUI

struct TheolCourseView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var didAutoSync = false

    private var courses: [TheolCourseInfo] {
        let all = environment.theolSlice.data?.courses ?? []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.courseName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            if environment.currentProfile == nil {
                VStack(spacing: 12) {
                    Text("请先登录统一身份认证").font(.headline)
                    Button("去登录") { environment.showLoginSheet = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if courses.isEmpty {
                            Text(environment.isSyncingTheol ? "正在同步在修课程目录..." : "暂无课程，请下拉或点击右上角刷新")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(28)
                                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        } else {
                            ForEach(courses) { course in
                                NavigationLink {
                                    TheolCourseDetailView(course: course)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "books.vertical.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 34, height: 34)
                                            .background(Color.accentColor.opacity(0.12), in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(course.courseName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text("课程 ID：\(course.lid)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(14)
                                    .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await environment.refreshTheol(userInitiated: true)
                }
            }
        }
        .navigationTitle("北化在线")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索课程名称")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
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
        .onAppear {
            if !didAutoSync,
               let profile = environment.currentProfile,
               profile.systemType == .undergradJwglxt,
               !profile.isDemoMode,
               (environment.theolSlice.data?.courses ?? []).isEmpty {
                didAutoSync = true
                Task { await environment.refreshTheol(userInitiated: false) }
            }
        }
    }
}

private enum TheolCourseSection: String, CaseIterable {
    case resources = "课程资源"
    case units = "单元学习"
    case tasks = "作业与测验"
}

struct TheolCourseDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL

    let course: TheolCourseInfo
    @State private var section: TheolCourseSection = .resources
    @State private var resourceStack: [TheolResourcePage] = []
    @State private var units: [TheolCourseUnit] = []
    @State private var selectedUnit: TheolCourseUnit?
    @State private var unitPage: TheolResourcePage?

    @State private var isLoading = false
    @State private var errorMsg = ""
    @State private var downloadingURL: String?
    @State private var previewFile: QuickLookFileItem?
    @State private var selectedHomework: TheolHomeworkItem?
    @State private var selectedTest: TheolTestItem?
    @State private var webLaunchContext: TheolWebLaunchContext?
    @State private var isOpeningWeb = false

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            VStack(spacing: 10) {
                Picker("栏目", selection: $section) {
                    ForEach(TheolCourseSection.allCases, id: \.self) { sec in
                        Text(sec.rawValue).tag(sec)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        switch section {
                        case .resources:
                            resourcesContent
                        case .units:
                            unitsContent
                        case .tasks:
                            tasksContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle(course.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let homeURL = "https://course.buct.edu.cn/meol/jpk/course/layout/newpage/index.jsp?courseId=\(course.lid)"
                    Task { await openInAppWeb(urlString: homeURL, title: course.courseName) }
                } label: {
                    if isOpeningWeb {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "globe")
                    }
                }
                .disabled(isOpeningWeb)
            }
        }
        .sheet(item: $previewFile) { item in
            QuickLookPreviewSheet(fileURL: item.url)
        }
        .sheet(item: $webLaunchContext) { ctx in
            TheolWebViewSheet(context: ctx)
        }
        .sheet(item: $selectedHomework) { hw in
            HomeworkDetailSheet(item: hw)
        }
        .sheet(item: $selectedTest) { test in
            TestDetailSheet(item: test)
        }
        .task {
            await loadRootResources()
            await loadUnits()
        }
    }

    @ViewBuilder
    private var resourcesContent: some View {
        if resourceStack.count > 1 {
            Button {
                resourceStack.removeLast()
            } label: {
                Label("返回上一级目录", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if isLoading && resourceStack.isEmpty {
            ProgressView("正在加载课程资源...")
                .padding(24)
        } else if let current = resourceStack.last {
            if current.items.isEmpty {
                Text("当前目录暂无课件或资源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                ForEach(current.items) { item in
                    resourceRow(item, referer: current.currentUrl)
                }
            }
        }
    }

    @ViewBuilder
    private var unitsContent: some View {
        if let unit = selectedUnit, let page = unitPage {
            Button {
                selectedUnit = nil
                unitPage = nil
            } label: {
                Label("返回单元列表（\(unit.title)）", systemImage: "arrow.uturn.backward")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.glass)
            .frame(maxWidth: .infinity, alignment: .leading)

            if page.items.isEmpty {
                Text("该单元暂无可下载资源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(24)
            } else {
                ForEach(page.items) { item in
                    resourceRow(item, referer: page.currentUrl)
                }
            }
        } else if units.isEmpty {
            Text(isLoading ? "正在加载单元学习..." : "暂无单元学习目录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(24)
        } else {
            ForEach(units) { unit in
                Button {
                    Task { await openUnit(unit) }
                } label: {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(unit.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var tasksContent: some View {
        let hws = (environment.theolSlice.data?.homeworks ?? []).filter { $0.lid == course.lid }
        let tests = (environment.theolSlice.data?.tests ?? []).filter { $0.lid == course.lid }
        if hws.isEmpty && tests.isEmpty {
            Text("该课程暂无同步到的作业或测验")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(24)
        } else {
            ForEach(hws) { hw in
                Button { selectedHomework = hw } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hw.title).font(.subheadline.weight(.semibold))
                            Text("截止：\(hw.deadline.isEmpty ? "未知" : hw.deadline)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(hw.status).font(.caption2.weight(.semibold))
                            .foregroundStyle(hw.hasResult ? .green : Color.accentColor)
                    }
                    .padding(14)
                    .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                }
                .buttonStyle(.plain)
            }
            ForEach(tests) { test in
                Button { selectedTest = test } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(test.title).font(.subheadline.weight(.semibold))
                            Text("测验 · \(test.status)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resourceRow(_ item: TheolResourceItem, referer: String) -> some View {
        Button {
            if item.isFolder {
                Task { await openFolder(url: item.url) }
            } else {
                Task { await downloadAndPreview(item, referer: referer) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.isFolder ? "folder.fill" : "doc.fill")
                    .foregroundStyle(item.isFolder ? .orange : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background((item.isFolder ? Color.orange : Color.accentColor).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    let meta = [item.fileExt.uppercased(), item.sizeText, item.updatedAt].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if downloadingURL == item.url {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: item.isFolder ? "chevron.right" : "arrow.down.circle")
                        .foregroundStyle(item.isFolder ? Color.secondary : Color.accentColor)
                }
            }
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
        }
        .buttonStyle(.plain)
    }

    private func loadRootResources() async {
        guard let profile = environment.currentProfile, resourceStack.isEmpty else { return }
        isLoading = true
        do {
            let page = try await environment.campusSync.fetchTheolCourseResources(profile: profile, lid: course.lid, courseName: course.courseName)
            resourceStack = [page]
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    private func openFolder(url: String) async {
        guard let profile = environment.currentProfile else { return }
        isLoading = true
        do {
            let page = try await environment.campusSync.fetchTheolCourseResources(profile: profile, lid: course.lid, courseName: course.courseName, folderUrl: url)
            resourceStack.append(page)
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    private func loadUnits() async {
        guard let profile = environment.currentProfile, units.isEmpty else { return }
        if let list = try? await environment.campusSync.fetchTheolCourseUnits(profile: profile, lid: course.lid) {
            units = list
        }
    }

    private func openUnit(_ unit: TheolCourseUnit) async {
        guard let profile = environment.currentProfile else { return }
        isLoading = true
        do {
            let page = try await environment.campusSync.fetchTheolUnitResources(profile: profile, lid: course.lid, courseName: course.courseName, unit: unit)
            selectedUnit = unit
            unitPage = page
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    private func downloadAndPreview(_ item: TheolResourceItem, referer: String) async {
        guard let profile = environment.currentProfile else { return }
        downloadingURL = item.url
        defer { downloadingURL = nil }
        do {
            let file = try await environment.campusSync.downloadTheolFile(
                profile: profile,
                urlString: item.url,
                courseLid: course.lid,
                referer: item.previewUrl.isEmpty ? referer : item.previewUrl
            )
            if file.isHtmlPage {
                let target = item.previewUrl.isEmpty ? item.url : item.previewUrl
                await openInAppWeb(urlString: target, title: item.name)
            } else if !file.filePath.isEmpty {
                previewFile = QuickLookFileItem(url: URL(fileURLWithPath: file.filePath))
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func openInAppWeb(urlString: String, title: String) async {
        guard let profile = environment.currentProfile else { return }
        isOpeningWeb = true
        defer { isOpeningWeb = false }
        do {
            webLaunchContext = try await environment.campusSync.prepareTheolWebLaunchContext(
                profile: profile,
                urlString: urlString,
                title: title,
                courseLid: course.lid,
                touchHomework: false
            )
        } catch {
            errorMsg = error.localizedDescription
            if let fallback = URL(string: urlString) {
                openURL(fallback)
            }
        }
    }
}
