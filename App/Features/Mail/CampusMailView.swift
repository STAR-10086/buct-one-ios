import BuctModel
import SwiftUI
import WebKit

private enum MailTabMode: String, CaseIterable {
    case inbox = "收件箱"
    case unread = "未读"
    case folders = "文件夹"
}

struct CampusMailView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tab: MailTabMode = .inbox
    @State private var searchText = ""
    @State private var activeFolderId: Int = MailFolder.inboxId
    @State private var activeFolderName: String = "收件箱"
    @State private var messages: [MailMessageSummary] = []
    @State private var totalCount: Int = 0
    @State private var isLoadingMore = false
    @State private var errorMsg = ""
    @State private var selectedMessage: MailMessageSummary?
    @State private var didAutoSync = false

    private var displayedMessages: [MailMessageSummary] {
        let base: [MailMessageSummary]
        if tab == .inbox && activeFolderId == MailFolder.inboxId && messages.isEmpty {
            base = environment.mailSlice.data?.inboxMessages ?? []
        } else {
            base = messages
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.subject.localizedCaseInsensitiveContains(q) ||
            $0.fromName.localizedCaseInsensitiveContains(q) ||
            $0.fromAddress.localizedCaseInsensitiveContains(q) ||
            $0.summary.localizedCaseInsensitiveContains(q)
        }
    }

    private var visibleFolders: [MailFolder] {
        (environment.mailSlice.data?.folders ?? []).filter { $0.id != MailFolder.draftsId && $0.id != 6 }
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
                VStack(spacing: 10) {
                    Picker("邮箱视图", selection: $tab) {
                        ForEach(MailTabMode.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .onChange(of: tab) { _, newTab in
                        Task { await reloadForCurrentTab(newTab) }
                    }

                    if let email = environment.mailSlice.data?.account.email, !email.isEmpty {
                        HStack {
                            Label(email, systemImage: "envelope.badge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if tab != .folders {
                                Button("全部已读") {
                                    Task { await markAllRead() }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.horizontal, 18)
                    }

                    if !errorMsg.isEmpty {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    } else if let lastErr = environment.mailSlice.lastError, !lastErr.isEmpty {
                        Text(lastErr)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                    }

                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if tab == .folders {
                                foldersContent
                            } else {
                                messagesContent
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        await environment.refreshMail(userInitiated: true)
                        await reloadForCurrentTab(tab)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle(tab == .folders ? "校园邮箱" : activeFolderName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索邮件主题、发件人或摘要")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        Task {
                            await environment.refreshMail(userInitiated: true)
                            await reloadForCurrentTab(tab)
                        }
                    } label: {
                        if environment.isSyncingMail || isLoadingMore {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(item: $selectedMessage) { msg in
            MailDetailSheet(
                message: msg,
                onStateChanged: { updatedId, isRead, deleted in
                    if deleted {
                        messages.removeAll { $0.id == updatedId }
                    } else if let idx = messages.firstIndex(where: { $0.id == updatedId }) {
                        messages[idx].isRead = isRead
                    }
                }
            )
        }
        .onAppear {
            environment.trackVisit(path: "/module/campusMail", title: "校园邮箱")
            if !didAutoSync, environment.currentProfile != nil {
                didAutoSync = true
                Task {
                    if environment.mailSlice.provenance.refreshState == .never {
                        await environment.refreshMail(userInitiated: false)
                    }
                    messages = environment.mailSlice.data?.inboxMessages ?? []
                    totalCount = environment.mailSlice.data?.inboxTotal ?? messages.count
                }
            }
        }
    }

    @ViewBuilder
    private var foldersContent: some View {
        if visibleFolders.isEmpty {
            emptyCard("暂无文件夹，下拉刷新以同步校园邮箱")
        } else {
            ForEach(visibleFolders) { folder in
                Button {
                    activeFolderId = folder.id
                    activeFolderName = folder.name
                    tab = .inbox
                    Task { await loadFolderMessages(folderId: folder.id, unreadOnly: false, reset: true) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: folderIcon(folder.id))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("共 \(folder.totalCount) 封")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if folder.unreadCount > 0 {
                            Text("\(folder.unreadCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor, in: Capsule())
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
    private var messagesContent: some View {
        if displayedMessages.isEmpty {
            emptyCard(environment.isSyncingMail ? "正在同步校园邮箱..." : "当前列表暂无邮件")
        } else {
            ForEach(displayedMessages) { msg in
                Button {
                    selectedMessage = msg
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(msg.isRead ? Color.clear : Color.accentColor)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(msg.fromName)
                                    .font(.caption.weight(msg.isRead ? .medium : .bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if msg.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(msg.receivedAt)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(msg.subject)
                                .font(.subheadline.weight(msg.isRead ? .medium : .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if !msg.summary.isEmpty {
                                Text(msg.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                    }
                    .padding(14)
                    .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                }
                .buttonStyle(.plain)
            }

            if messages.count < totalCount && searchText.isEmpty {
                Button {
                    Task {
                        await loadFolderMessages(
                            folderId: tab == .unread ? MailFolder.inboxId : activeFolderId,
                            unreadOnly: tab == .unread,
                            reset: false
                        )
                    }
                } label: {
                    if isLoadingMore {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("加载更多（\(messages.count) / \(totalCount)）")
                            .font(.caption.weight(.semibold))
                    }
                }
                .buttonStyle(.glass)
                .padding(.vertical, 8)
            }
        }
    }

    private func reloadForCurrentTab(_ target: MailTabMode) async {
        switch target {
        case .inbox:
            if activeFolderId == MailFolder.inboxId {
                activeFolderName = "收件箱"
            }
            await loadFolderMessages(folderId: activeFolderId, unreadOnly: false, reset: true)
        case .unread:
            activeFolderName = "未读邮件"
            await loadFolderMessages(folderId: MailFolder.inboxId, unreadOnly: true, reset: true)
        case .folders:
            break
        }
    }

    private func loadFolderMessages(folderId: Int, unreadOnly: Bool, reset: Bool) async {
        guard let profile = environment.currentProfile else { return }
        isLoadingMore = true
        errorMsg = ""
        defer { isLoadingMore = false }
        let start = reset ? 0 : messages.count
        do {
            let res = try await environment.campusSync.listMailMessages(
                profile: profile,
                folderId: folderId,
                start: start,
                limit: 30,
                unreadOnly: unreadOnly
            )
            totalCount = res.total
            if reset {
                messages = res.messages
            } else {
                let existing = Set(messages.map(\.id))
                messages.append(contentsOf: res.messages.filter { !existing.contains($0.id) })
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func markAllRead() async {
        guard let profile = environment.currentProfile else { return }
        do {
            try await environment.campusSync.markMailFolderAllRead(profile: profile, folderId: activeFolderId)
            messages = messages.map { m in
                var copy = m
                copy.isRead = true
                return copy
            }
            await environment.refreshMail(userInitiated: true)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func folderIcon(_ id: Int) -> String {
        switch id {
        case MailFolder.inboxId: return "tray.fill"
        case MailFolder.sentId: return "paperplane.fill"
        case MailFolder.trashId: return "trash.fill"
        case MailFolder.spamId: return "exclamationmark.octagon.fill"
        default: return "folder.fill"
        }
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(28)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }
}

private struct MailDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    let message: MailMessageSummary
    let onStateChanged: (String, Bool, Bool) -> Void

    @State private var detail: MailMessageDetail?
    @State private var isRead: Bool = true
    @State private var showPlainText = false
    @State private var isLoading = true
    @State private var errorMsg = ""
    @State private var downloadingPartId: String?
    @State private var previewFile: QuickLookFileItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(detail?.subject ?? message.subject)
                                .font(.title3.weight(.bold))
                            Text("发件人：\(message.fromName)\(message.fromAddress.isEmpty ? "" : " <\(message.fromAddress)>")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let to = detail?.to, !to.isEmpty {
                                Text("收件人：\(to.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !message.sentAt.isEmpty {
                                Text("时间：\(message.sentAt)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

                        if isLoading {
                            ProgressView("正在加载邮件正文...")
                                .frame(maxWidth: .infinity)
                                .padding(24)
                        } else if !errorMsg.isEmpty {
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if let detail {
                            let visibleAttachments = detail.attachments.filter { !$0.isInlined }
                            if !visibleAttachments.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("附件（\(visibleAttachments.count)）")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(visibleAttachments) { att in
                                        Button {
                                            Task { await downloadAttachment(att) }
                                        } label: {
                                            HStack {
                                                Image(systemName: "doc.fill")
                                                    .foregroundStyle(Color.accentColor)
                                                Text(att.filename)
                                                    .font(.caption.weight(.medium))
                                                    .lineLimit(1)
                                                Spacer()
                                                if downloadingPartId == att.partId {
                                                    ProgressView().controlSize(.small)
                                                } else {
                                                    Image(systemName: "arrow.down.circle")
                                                        .foregroundStyle(Color.accentColor)
                                                }
                                            }
                                            .padding(10)
                                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(14)
                                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }

                            if !detail.htmlBody.isEmpty && !showPlainText {
                                MailHtmlBodyView(html: detail.htmlBody)
                                    .frame(minHeight: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                Text(detail.plainText.isEmpty ? "（邮件无文本内容）" : detail.plainText)
                                    .font(.footnote)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("邮件详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let d = detail, !d.htmlBody.isEmpty {
                        Button {
                            showPlainText.toggle()
                        } label: {
                            Image(systemName: showPlainText ? "doc.richtext" : "doc.plaintext")
                        }
                    }
                    Button {
                        Task { await toggleRead() }
                    } label: {
                        Image(systemName: isRead ? "envelope.badge" : "envelope.open")
                    }
                    if message.folderId == MailFolder.trashId {
                        Button {
                            Task { await restoreMessage() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                    }
                    Button(role: .destructive) {
                        Task { await deleteMessage() }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .sheet(item: $previewFile) { item in
                QuickLookPreviewSheet(fileURL: item.url)
            }
            .task {
                isRead = message.isRead
                guard let profile = environment.currentProfile else { return }
                isLoading = true
                do {
                    detail = try await environment.campusSync.fetchMailDetail(profile: profile, message: message)
                    if !message.isRead {
                        try? await environment.campusSync.setMailRead(profile: profile, messageId: message.id, isRead: true)
                        isRead = true
                        onStateChanged(message.id, true, false)
                    }
                } catch {
                    errorMsg = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func toggleRead() async {
        guard let profile = environment.currentProfile else { return }
        let next = !isRead
        do {
            try await environment.campusSync.setMailRead(profile: profile, messageId: message.id, isRead: next)
            isRead = next
            onStateChanged(message.id, next, false)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func deleteMessage() async {
        guard let profile = environment.currentProfile else { return }
        do {
            try await environment.campusSync.deleteMail(profile: profile, messageId: message.id, currentFolderId: message.folderId)
            onStateChanged(message.id, isRead, true)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func restoreMessage() async {
        guard let profile = environment.currentProfile else { return }
        do {
            try await environment.campusSync.restoreMailToInbox(profile: profile, messageId: message.id)
            onStateChanged(message.id, isRead, true)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func downloadAttachment(_ att: MailAttachment) async {
        guard let profile = environment.currentProfile else { return }
        downloadingPartId = att.partId
        defer { downloadingPartId = nil }
        do {
            let file = try await environment.campusSync.downloadMailAttachment(profile: profile, messageId: message.id, attachment: att)
            previewFile = QuickLookFileItem(url: URL(fileURLWithPath: file.filePath))
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private struct MailHtmlBodyView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let wrapped = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0">
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 15px; line-height: 1.6; padding: 12px; margin: 0; word-break: break-word; color: #1c1c1e; background: #ffffff; }
          img { max-width: 100%; height: auto; }
          table { max-width: 100%; }
          @media (prefers-color-scheme: dark) {
            body { color: #f2f2f7; background: #1c1c1e; }
            a { color: #64d2ff; }
          }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(wrapped, baseURL: nil)
    }
}
