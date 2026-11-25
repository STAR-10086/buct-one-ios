import BuctModel
import SwiftUI

private enum PortalSubTab: String, CaseIterable {
    case news = "校内资讯"
    case library = "图书在借"
    case calendar = "官方校历"
}

struct IBuctPortalView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var subTab: PortalSubTab = .news
    @State private var selectedColumn: PortalNewsColumn = .notice
    @State private var extraArticles: [String: [PortalNewsArticle]] = [:]
    @State private var isLoadingMore = false
    @State private var selectedArticle: PortalNewsArticle?
    @State private var didAutoSync = false

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            VStack(spacing: 10) {
                Picker("i北化", selection: $subTab) {
                    ForEach(PortalSubTab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        switch subTab {
                        case .news:
                            newsContent
                        case .library:
                            libraryContent
                        case .calendar:
                            calendarContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .refreshable {
                    extraArticles.removeAll()
                    await environment.refreshPortal(userInitiated: true)
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("i北化")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        if subTab == .calendar {
                            await environment.calibrateOfficialCalendar(forceOverrideManual: true)
                        } else {
                            await environment.refreshPortal(userInitiated: true)
                        }
                    }
                } label: {
                    if environment.isSyncingPortal || environment.isSyncingCalendar {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(item: $selectedArticle) { article in
            PortalNewsDetailSheet(article: article)
        }
        .onAppear {
            if !didAutoSync,
               let profile = environment.currentProfile,
               !profile.isDemoMode,
               environment.portalNewsSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshPortal(userInitiated: false) }
            }
        }
    }

    @ViewBuilder
    private var newsContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PortalNewsColumn.allCases) { col in
                    let active = selectedColumn == col
                    Button(col.title) {
                        withAnimation(.snappy) { selectedColumn = col }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(active ? .white : .primary)
                    .background(active ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
                }
            }
        }

        let page = environment.portalNewsSlice.data?.columns[selectedColumn.rawValue]
        let base = page?.articles ?? []
        let baseIds = Set(base.map(\.id))
        let merged = base + (extraArticles[selectedColumn.rawValue] ?? []).filter { !baseIds.contains($0.id) }

        if merged.isEmpty {
            emptyCard("暂无\(selectedColumn.title)，点击右上角刷新")
        } else {
            ForEach(merged) { article in
                Button {
                    selectedArticle = article
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(article.sourceOrg.isEmpty ? selectedColumn.sourceHint : article.sourceOrg)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            if article.isTop {
                                badge("置顶", color: .orange)
                            } else if article.isHot {
                                badge("热", color: .red)
                            } else if article.isNewest {
                                badge("新", color: .green)
                            }
                            Spacer()
                            Text(article.formattedDate)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(article.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        if !article.summary.isEmpty {
                            Text(article.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                }
                .buttonStyle(.plain)
            }

            if (page?.totalCount ?? 0) > merged.count {
                Button {
                    Task { await loadMoreColumn(offset: merged.count) }
                } label: {
                    if isLoadingMore {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("加载更多资讯").font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        let books = environment.portalLibrarySlice.data?.books ?? []
        if books.isEmpty {
            emptyCard(
                environment.portalLibrarySlice.provenance.refreshState == .emptyConfirmed
                    ? "当前没有在借图书"
                    : "尚未同步图书馆记录，请点击右上角刷新"
            )
        } else {
            ForEach(books) { book in
                HStack(spacing: 12) {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.subheadline.weight(.semibold))
                        Text("借阅 \(book.borrowDate) · 应还 \(book.dueDate)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let days = book.daysRemaining() {
                        let color: Color = days < 0 ? .red : (days <= 7 ? .orange : .green)
                        let text = days < 0 ? "逾期 \(-days) 天" : (days == 0 ? "今天到期" : "剩 \(days) 天")
                        badge(text, color: color)
                    }
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    @ViewBuilder
    private var calendarContent: some View {
        let cal = environment.calendarSlice.data
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("当前学期", value: cal?.currentTermId ?? environment.selectedTerm.id)
            LabeledContent("当前教学周", value: environment.currentTeachingWeek.map { "第 \($0) 周" } ?? "假期/非教学周")
            LabeledContent("开学日期", value: environment.firstWeekMonday)
            if let end = cal?.endDate, !end.isEmpty {
                LabeledContent("学期结束", value: end)
            }
        }
        .font(.footnote)
        .padding(16)
        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

        if let holidays = cal?.holidays, !holidays.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("节假日与调休")
                    .font(.subheadline.weight(.semibold))
                ForEach(holidays, id: \.date) { h in
                    HStack {
                        Text(h.date).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(h.name.isEmpty ? "节假日" : h.name).font(.caption.weight(.medium))
                    }
                }
            }
            .padding(16)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(28)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func loadMoreColumn(offset: Int) async {
        guard !isLoadingMore, let profile = environment.currentProfile else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        if let page = try? await environment.campusSync.loadMorePortalNews(profile: profile, column: selectedColumn, beginIndex: offset) {
            extraArticles[selectedColumn.rawValue, default: []].append(contentsOf: page.articles)
        }
    }
}

private struct PortalNewsDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let article: PortalNewsArticle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(article.title)
                        .font(.title3.weight(.bold))
                    Text([article.sourceOrg, article.formattedDate].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    let bodyText = article.content.isEmpty ? article.summary : article.content
                    Text(bodyText.isEmpty ? "暂无正文预览，可点击下方打开原文" : bodyText)
                        .font(.body)
                        .textSelection(.enabled)

                    if let url = URL(string: article.publicUrl),
                       ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Button {
                            openURL(url)
                        } label: {
                            Label("在浏览器中查看原文", systemImage: "safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .navigationTitle("资讯详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } }
            }
        }
    }
}
