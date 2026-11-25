import BuctModel
import SwiftUI

private enum CourseSelectionTab: String, CaseIterable {
    case available = "可选课程"
    case selected = "已选课程"
    case wishlist = "志愿队列"
}

struct CourseSelectionView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tab: CourseSelectionTab = .available
    @State private var searchText = ""
    @State private var onlyWithSeats = false
    @State private var selectedKklxdm: String = "ALL"
    @State private var activeCourseForClasses: CourseSelectionCourse?
    @State private var pendingDropCourse: CourseSelectionCourse?
    @State private var showBatchConfirm = false
    @State private var isSubmittingBatch = false
    @State private var actionLogs: [String] = []
    @State private var didAutoSync = false

    private var snapshot: CourseSelectionSnapshot? {
        environment.courseSelectionSlice.data
    }

    private var groupedAvailable: [(key: String, lead: CourseSelectionCourse, count: Int)] {
        let all = snapshot?.availableCourses ?? []
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = all.filter { c in
            if selectedKklxdm != "ALL" && c.kklxdm != selectedKklxdm { return false }
            if onlyWithSeats && !c.hasSeats { return false }
            if !q.isEmpty {
                return c.name.localizedCaseInsensitiveContains(q) ||
                    c.teacher.localizedCaseInsensitiveContains(q) ||
                    c.courseId.localizedCaseInsensitiveContains(q)
            }
            return true
        }
        var order: [String] = []
        var grouped: [String: [CourseSelectionCourse]] = [:]
        for c in filtered {
            let key = "\(c.courseId)|\(c.name)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(c)
        }
        return order.compactMap { key in
            guard let list = grouped[key], let first = list.first else { return nil }
            return (key, first, list.count)
        }
    }

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            if environment.currentProfile == nil {
                VStack(spacing: 12) {
                    Text("请先登录本科教务账号").font(.headline)
                    Button("去登录") { environment.showLoginSheet = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                VStack(spacing: 10) {
                    Picker("选课栏目", selection: $tab) {
                        ForEach(CourseSelectionTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if let snap = snapshot, !snap.statusMessage.isEmpty {
                        HStack {
                            Image(systemName: snap.isOpen ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                                .foregroundStyle(snap.isOpen ? Color.green : Color.orange)
                            Text(snap.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 18)
                    }

                    if tab == .available {
                        filterStrip
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if let err = environment.courseSelectionSlice.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }

                            switch tab {
                            case .available:
                                availableContent
                            case .selected:
                                selectedContent
                            case .wishlist:
                                wishlistContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        await environment.refreshCourseSelection(onlyWithSeats: onlyWithSeats, keyword: searchText)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("选课中心")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索课程名、教师或课程代码")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        Task { await environment.refreshCourseSelection(onlyWithSeats: onlyWithSeats, keyword: searchText) }
                    } label: {
                        if environment.isSyncingCourseSelection {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(item: $activeCourseForClasses) { course in
            CourseTeachingClassesSheet(course: course) { msg in
                actionLogs.insert(msg, at: 0)
                Task { await environment.refreshCourseSelection(onlyWithSeats: onlyWithSeats, keyword: searchText) }
            }
        }
        .alert("确认退课", isPresented: Binding(
            get: { pendingDropCourse != nil },
            set: { if !$0 { pendingDropCourse = nil } }
        )) {
            Button("取消", role: .cancel) { pendingDropCourse = nil }
            Button("确认退课", role: .destructive) {
                if let target = pendingDropCourse {
                    Task { await performDrop(target) }
                }
            }
        } message: {
            Text("确定要退选「\(pendingDropCourse?.name ?? "")」吗？退选后名额可能被其他同学选走。")
        }
        .alert("确认按序提交志愿队列", isPresented: $showBatchConfirm) {
            Button("取消", role: .cancel) {}
            Button("开始提交") {
                Task { await submitWishlistSequentially() }
            }
        } message: {
            Text("将依次为队列中的 \(environment.courseWishlist.count) 门课程手动提交一次选课请求（间隔 0.5 秒），不会在后台自动循环。")
        }
        .onAppear {
            environment.trackVisit(path: "/module/courseSelection", title: "选课中心")
            if !didAutoSync, environment.currentProfile != nil,
               environment.courseSelectionSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshCourseSelection() }
            }
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Toggle("仅有余量", isOn: $onlyWithSeats)
                    .toggleStyle(.button)
                    .controlSize(.small)

                Button("全部") { selectedKklxdm = "ALL" }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .tint(selectedKklxdm == "ALL" ? Color.accentColor : Color.secondary)

                ForEach(snapshot?.tabs ?? []) { t in
                    Button(t.title) { selectedKklxdm = t.kklxdm }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .tint(selectedKklxdm == t.kklxdm ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var availableContent: some View {
        if groupedAvailable.isEmpty {
            emptyCard(environment.isSyncingCourseSelection ? "正在拉取可选课程..." : "暂无匹配的可选课程")
        } else {
            ForEach(groupedAvailable, id: \.key) { group in
                let c = group.lead
                Button {
                    activeCourseForClasses = c
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(c.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                if c.isSelected {
                                    Text("已选")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.14), in: Capsule())
                                }
                            }
                            let meta = [c.courseId, c.credits.isEmpty ? "" : "\(c.credits) 学分", c.teacher].filter { !$0.isEmpty }.joined(separator: " · ")
                            Text(meta)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if !c.timeText.isEmpty {
                                Text(c.timeText)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(group.count) 个教学班")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                            if c.capacity > 0 {
                                Text("余 \(c.remainingSeats)/\(c.capacity)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(c.hasSeats ? Color.secondary : Color.red)
                            }
                        }
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
    private var selectedContent: some View {
        let selected = snapshot?.selectedCourses ?? []
        if selected.isEmpty {
            emptyCard("当前暂无已选课程")
        } else {
            ForEach(selected) { c in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.name).font(.subheadline.weight(.semibold))
                        Text([c.teacher, c.credits.isEmpty ? "" : "\(c.credits) 学分", c.teachingClassName].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !c.timeText.isEmpty || !c.location.isEmpty {
                            Text([c.timeText, c.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("退课", role: .destructive) {
                        pendingDropCourse = c
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    @ViewBuilder
    private var wishlistContent: some View {
        if environment.courseWishlist.isEmpty {
            emptyCard("志愿队列为空，可在「可选课程」中点击任意课程加入志愿队列。")
        } else {
            Button {
                showBatchConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isSubmittingBatch { ProgressView().controlSize(.small) }
                    Text(isSubmittingBatch ? "正在按序提交..." : "手动按序提交全部志愿（\(environment.courseWishlist.count) 门）")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isSubmittingBatch)

            ForEach(Array(environment.courseWishlist.enumerated()), id: \.element.id) { idx, item in
                HStack(spacing: 10) {
                    Text("\(idx + 1)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.subheadline.weight(.semibold))
                        Text([item.teacher, item.teachingClassName, item.timeText].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await environment.removeFromCourseWishlist(id: item.id) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }

        if !actionLogs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("最近操作记录").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(actionLogs.prefix(8).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
    }

    private func performDrop(_ course: CourseSelectionCourse) async {
        guard let profile = environment.currentProfile else { return }
        pendingDropCourse = nil
        do {
            let res = try await environment.campusSync.dropCourse(profile: profile, course: course)
            actionLogs.insert("退课「\(course.name)」：\(res.message)", at: 0)
            await environment.refreshCourseSelection(onlyWithSeats: onlyWithSeats, keyword: searchText)
        } catch {
            actionLogs.insert("退课「\(course.name)」失败：\(error.localizedDescription)", at: 0)
        }
    }

    private func submitWishlistSequentially() async {
        guard let profile = environment.currentProfile else { return }
        isSubmittingBatch = true
        defer { isSubmittingBatch = false }
        let xkxnm = snapshot?.xkxnm ?? ""
        let xkxqm = snapshot?.xkxqm ?? ""

        for item in environment.courseWishlist {
            do {
                let res = try await environment.campusSync.selectCourse(
                    profile: profile,
                    course: item.toSelectionCourse(xkxnm: xkxnm, xkxqm: xkxqm)
                )
                actionLogs.insert("「\(item.name)」：\(res.message)", at: 0)
                if res.success {
                    await environment.removeFromCourseWishlist(id: item.id)
                }
            } catch {
                actionLogs.insert("「\(item.name)」失败：\(error.localizedDescription)", at: 0)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        await environment.refreshCourseSelection(onlyWithSeats: onlyWithSeats, keyword: searchText)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
            .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }
}

private struct CourseTeachingClassesSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let course: CourseSelectionCourse
    let onActionFinished: (String) -> Void

    @State private var classes: [CourseSelectionCourse] = []
    @State private var isLoading = true
    @State private var errorMsg = ""
    @State private var pendingSelect: CourseSelectionCourse?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if isLoading {
                        ProgressView("正在拉取教学班与实时余量...")
                            .padding(24)
                    } else if !errorMsg.isEmpty {
                        Text(errorMsg).font(.caption).foregroundStyle(.red)
                    } else {
                        ForEach(classes.isEmpty ? [course] : classes) { cls in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(cls.teachingClassName.isEmpty ? cls.name : cls.teachingClassName)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if cls.capacity > 0 {
                                        Text("余 \(cls.remainingSeats)/\(cls.capacity)")
                                            .font(.caption2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(cls.hasSeats ? Color.green : Color.red)
                                    }
                                }
                                if !cls.teacher.isEmpty {
                                    Label(cls.teacher, systemImage: "person")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if !cls.timeText.isEmpty {
                                    Label(cls.timeText, systemImage: "clock")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if !cls.location.isEmpty {
                                    Label(cls.location, systemImage: "mappin.and.ellipse")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }

                                HStack(spacing: 10) {
                                    Button("加入志愿队列") {
                                        let item = CourseSelectionWishlistItem(
                                            courseId: cls.courseId,
                                            classId: cls.classId,
                                            name: cls.name,
                                            teacher: cls.teacher,
                                            teachingClassName: cls.teachingClassName,
                                            timeText: cls.timeText,
                                            location: cls.location,
                                            credits: cls.credits,
                                            kklxdm: cls.kklxdm,
                                            xkkzId: cls.xkkzId
                                        )
                                        Task {
                                            await environment.addToCourseWishlist(item)
                                            onActionFinished("已加入志愿队列：\(cls.name)")
                                        }
                                    }
                                    .buttonStyle(.glass)
                                    .controlSize(.small)

                                    Button("确认选课") {
                                        pendingSelect = cls
                                    }
                                    .buttonStyle(.glassProminent)
                                    .controlSize(.small)
                                    .disabled(isSubmitting)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(course.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .alert("确认选课", isPresented: Binding(
                get: { pendingSelect != nil },
                set: { if !$0 { pendingSelect = nil } }
            )) {
                Button("取消", role: .cancel) { pendingSelect = nil }
                Button("提交选课") {
                    if let target = pendingSelect {
                        Task { await performSelect(target) }
                    }
                }
            } message: {
                Text("确认选修「\(pendingSelect?.name ?? "")」（\(pendingSelect?.teacher ?? "")）？")
            }
            .task {
                guard let profile = environment.currentProfile else { return }
                isLoading = true
                do {
                    classes = try await environment.campusSync.fetchCourseTeachingClasses(profile: profile, course: course)
                } catch {
                    errorMsg = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func performSelect(_ cls: CourseSelectionCourse) async {
        guard let profile = environment.currentProfile else { return }
        pendingSelect = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let res = try await environment.campusSync.selectCourse(profile: profile, course: cls)
            onActionFinished("选课「\(cls.name)」：\(res.message)")
            if res.success { dismiss() }
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
