import BuctModel
import SwiftUI

private enum JwNoticeTab: String, CaseIterable {
    case reminders = "教务提醒"
    case announcements = "通知公告"
}

struct JwNoticeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL

    @State private var tab: JwNoticeTab = .reminders
    @State private var selectedCategory: JwReminderCategory?
    @State private var searchText = ""
    @State private var extraReminders: [JwReminderItem] = []
    @State private var extraAnnouncements: [JwAnnouncementItem] = []
    @State private var reminderPage = 1
    @State private var announcementPage = 1
    @State private var isLoadingMore = false
    @State private var selectedAnnouncement: JwAnnouncementItem?
    @State private var didAutoSync = false

    private var allReminders: [JwReminderItem] {
        let base = environment.jwNoticeSlice.data?.reminders ?? []
        let baseIds = Set(base.map(\.id))
        let merged = base + extraReminders.filter { !baseIds.contains($0.id) }
        return merged.filter { item in
            let catOk = selectedCategory == nil || item.category == selectedCategory
            let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let kwOk = kw.isEmpty || item.title.localizedCaseInsensitiveContains(kw) || item.content.localizedCaseInsensitiveContains(kw)
            return catOk && kwOk
        }
    }

    private var allAnnouncements: [JwAnnouncementItem] {
        let base = environment.jwNoticeSlice.data?.announcements ?? []
        let baseIds = Set(base.map(\.id))
        let merged = base + extraAnnouncements.filter { !baseIds.contains($0.id) }
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return merged }
        return merged.filter { $0.title.localizedCaseInsensitiveContains(kw) || $0.publisher.localizedCaseInsensitiveContains(kw) }
    }

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            VStack(spacing: 10) {
                Picker("类型", selection: $tab) {
                    ForEach(JwNoticeTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                if tab == .reminders {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            categoryChip(title: "全部", category: nil)
                            ForEach(JwReminderCategory.allCases, id: \.self) { cat in
                                categoryChip(title: cat.displayName, category: cat)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        if tab == .reminders {
                            if allReminders.isEmpty {
                                emptyCard("暂无教务提醒")
                            } else {
                                ForEach(allReminders) { item in
                                    reminderCard(item)
                                }
                                if (environment.jwNoticeSlice.data?.reminderTotal ?? 0) > allReminders.count {
                                    loadMoreButton {
                                        await loadMoreReminders()
                                    }
                                }
                            }
                        } else {
                            if allAnnouncements.isEmpty {
                                emptyCard("暂无教务公告")
                            } else {
                                ForEach(allAnnouncements) { item in
                                    announcementCard(item)
                                }
                                if (environment.jwNoticeSlice.data?.announcementTotal ?? 0) > allAnnouncements.count {
                                    loadMoreButton {
                                        await loadMoreAnnouncements()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    extraReminders.removeAll()
                    extraAnnouncements.removeAll()
                    reminderPage = 1
                    announcementPage = 1
                    await environment.refreshJwNotice(userInitiated: true)
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("教务消息")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索消息或公告")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await environment.refreshJwNotice(userInitiated: true) }
                } label: {
                    if environment.isSyncingJwNotice {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(item: $selectedAnnouncement) { item in
            JwAnnouncementDetailSheet(item: item)
        }
        .onAppear {
            if !didAutoSync,
               let profile = environment.currentProfile,
               profile.systemType == .undergradJwglxt,
               !profile.isDemoMode,
               environment.jwNoticeSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshJwNotice(userInitiated: false) }
            }
        }
    }

    private func categoryChip(title: String, category: JwReminderCategory?) -> some View {
        let active = selectedCategory == category
        return Button(title) {
            withAnimation(.snappy) { selectedCategory = category }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(active ? .white : .primary)
        .background(active ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
    }

    private func reminderCard(_ item: JwReminderItem) -> some View {
        Button {
            Task { await environment.markJwReminderRead(id: item.id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(item.category.displayName, systemImage: item.category.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                    if !item.isRead {
                        Circle().fill(.red).frame(width: 7, height: 7)
                    }
                    Spacer()
                    Text(item.createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if item.content != item.title {
                    Text(item.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
        }
        .buttonStyle(.plain)
    }

    private func announcementCard(_ item: JwAnnouncementItem) -> some View {
        Button {
            Task { await environment.markJwAnnouncementRead(id: item.id) }
            if !item.externalUrl.isEmpty,
               let url = URL(string: item.externalUrl, relativeTo: URL(string: "https://jwglxt.buct.edu.cn/jwglxt/xtgl/")) {
                openURL(url)
            } else {
                selectedAnnouncement = item
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if item.isPinned {
                        Text("置顶")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.14), in: Capsule())
                    }
                    if !item.isRead {
                        Circle().fill(.red).frame(width: 7, height: 7)
                    }
                    Text(item.publisher.isEmpty ? "教务处" : item.publisher)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.publishedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
        }
        .buttonStyle(.plain)
    }

    private func loadMoreButton(action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            if isLoadingMore {
                ProgressView().controlSize(.small)
            } else {
                Text("加载更多")
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.glass)
        .padding(.top, 4)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(28)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func loadMoreReminders() async {
        guard !isLoadingMore, let profile = environment.currentProfile else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = reminderPage + 1
        if let res = try? await environment.campusSync.loadMoreJwReminders(profile: profile, page: next, keyword: searchText) {
            reminderPage = next
            extraReminders.append(contentsOf: res.items)
        }
    }

    private func loadMoreAnnouncements() async {
        guard !isLoadingMore, let profile = environment.currentProfile else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = announcementPage + 1
        if let res = try? await environment.campusSync.loadMoreJwAnnouncements(profile: profile, page: next, keyword: searchText) {
            announcementPage = next
            extraAnnouncements.append(contentsOf: res.items)
        }
    }
}

private struct JwAnnouncementDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let item: JwAnnouncementItem
    @State private var detail: JwAnnouncementDetail?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(detail?.title ?? item.title)
                        .font(.title3.weight(.bold))
                    Text("\(detail?.publisher ?? item.publisher) · \(detail?.publishedAt ?? item.publishedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    if isLoading {
                        ProgressView("正在加载正文...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(detail?.plainText.isEmpty == false ? detail!.plainText : "暂无正文内容")
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
            }
            .navigationTitle("公告详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task {
                guard let profile = environment.currentProfile else { return }
                detail = try? await environment.campusSync.fetchJwAnnouncementDetail(profile: profile, item: item)
                isLoading = false
            }
        }
    }
}
