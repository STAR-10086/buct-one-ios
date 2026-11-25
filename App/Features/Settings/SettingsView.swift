import BuctModel
import BuctStore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var copiedSourceURL = false
    @State private var hasPasskey = false
    @State private var showPasskeySheet = false
    @State private var vpnTicketActive = false
    @State private var vpnLastReason = ""

    private let sideStoreSourceURL = "https://update.buct.one/ios/apps.json"

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
                        if environment.currentProfile?.systemType == .undergradJwglxt {
                            passkeyAndVpnCard
                        }
                        reminderCard
                        appearanceCard
                        dataAndSecurityCard
                        aboutCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showPasskeySheet) {
                PasskeyRegisterSheet(hasPasskey: $hasPasskey)
            }
            .task {
                await refreshDiagnostics()
            }
            .onAppear {
                environment.trackVisit(path: "/tab/settings", title: "我的")
                Task { await refreshDiagnostics() }
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Image(systemName: environment.currentProfile == nil ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle.badge.checkmark")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor)

            if let profile = environment.currentProfile {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(profile.studentName)
                            .font(.headline)
                        Text(profile.systemType.shortBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    Text("学号：\(profile.maskedStudentId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("退出") {
                    Task { await environment.logout(clearSavedCredential: false) }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未登录统一身份认证")
                        .font(.headline)
                    Text("点击登录本科 / 研究生教务或体验演示数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("登录") {
                    environment.showLoginSheet = true
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var passkeyAndVpnCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("账号与校外访问")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack {
                Label(
                    hasPasskey ? "Face ID 通行密钥已启用" : "Face ID 通行密钥未注册",
                    systemImage: "faceid"
                )
                .font(.subheadline)
                Spacer()
                Button(hasPasskey ? "管理" : "启用") {
                    showPasskeySheet = true
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WebVPN 自动降级状态")
                        .font(.subheadline)
                    Text(vpnTicketActive ? "已缓存有效票据" : (vpnLastReason.isEmpty ? "校内直连 / 待按需激活" : vpnLastReason))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("重置票据") {
                    Task {
                        await environment.syncService.resetWebVpnSession()
                        await refreshDiagnostics()
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地智能提醒")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle("课前提醒（提前 \(environment.reminderConfig.courseLeadMinutes) 分钟）", isOn: Binding(
                get: { environment.reminderConfig.courseReminderEnabled },
                set: { enabled in
                    Task {
                        if enabled { _ = await environment.reminderService.requestAuthorization() }
                        var cfg = environment.reminderConfig
                        cfg.courseReminderEnabled = enabled
                        await environment.updateReminderConfig(cfg)
                    }
                }
            ))

            Toggle("考试倒计时提醒（考前 1 天 + 2 小时）", isOn: Binding(
                get: { environment.reminderConfig.examReminderEnabled },
                set: { enabled in
                    Task {
                        if enabled { _ = await environment.reminderService.requestAuthorization() }
                        var cfg = environment.reminderConfig
                        cfg.examReminderEnabled = enabled
                        await environment.updateReminderConfig(cfg)
                    }
                }
            ))
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(
                "深浅模式",
                selection: Binding(
                    get: { environment.appearance.themeMode },
                    set: { mode in
                        var updated = environment.appearance
                        updated.themeMode = mode
                        environment.updateAppearance(updated)
                    }
                )
            ) {
                ForEach(ThemeMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Toggle(
                "原生液态玻璃材质",
                isOn: Binding(
                    get: { environment.appearance.liquidGlassEnabled },
                    set: { enabled in
                        var updated = environment.appearance
                        updated.liquidGlassEnabled = enabled
                        environment.updateAppearance(updated)
                    }
                )
            )
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var dataAndSecurityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据与安全")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Toggle(
                "匿名使用统计（自托管 Umami）",
                isOn: Binding(
                    get: { environment.appearance.umamiEnabled },
                    set: { enabled in
                        var updated = environment.appearance
                        updated.umamiEnabled = enabled
                        environment.updateAppearance(updated)
                    }
                )
            )

            Text("仅使用本地随机 UUIDv4 上报日活与模块热度，绝不采集学号、姓名或硬件指纹。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            LabeledContent("发行包类型", value: environment.editionLabel)
                .font(.footnote)
            LabeledContent("存储容器", value: environment.containerMode.displayName)
                .font(.footnote)
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用与自签更新")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            LabeledContent("版本", value: "v\(environment.appVersion) (\(environment.buildNumber))")
                .font(.footnote)

            LabeledContent("开源协议", value: "GPL-3.0")
                .font(.footnote)

            Button {
                UIPasteboard.general.string = sideStoreSourceURL
                copiedSourceURL = true
            } label: {
                HStack {
                    Text(copiedSourceURL ? "已复制 SideStore / AltStore 源地址" : "复制 SideStore / AltStore 源地址")
                    Spacer()
                    Image(systemName: copiedSourceURL ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .font(.subheadline)
            }
            .buttonStyle(.glass)
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func refreshDiagnostics() async {
        if let profile = environment.currentProfile, profile.systemType == .undergradJwglxt {
            hasPasskey = await environment.syncService.hasPasskey(username: profile.studentId)
        } else {
            hasPasskey = false
        }
        let status = await environment.syncService.webVpnStatus()
        vpnTicketActive = status.hasTicket
        vpnLastReason = status.lastFailureReason
    }
}

private struct PasskeyRegisterSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Binding var hasPasskey: Bool

    @State private var password = ""
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                if let profile = environment.currentProfile {
                    Section("通行密钥管理") {
                        LabeledContent("学号", value: profile.studentId)
                        if hasPasskey {
                            Button("清除本机通行密钥", role: .destructive) {
                                Task {
                                    await environment.syncService.clearPasskey(username: profile.studentId)
                                    hasPasskey = false
                                    dismiss()
                                }
                            }
                        } else {
                            SecureField("输入统一身份认证密码以绑定本机 Face ID", text: $password)
                            Button {
                                Task {
                                    isLoading = true
                                    defer { isLoading = false }
                                    let res = await environment.syncService.registerPasskey(
                                        username: profile.studentId,
                                        password: password
                                    )
                                    switch res {
                                    case .success:
                                        hasPasskey = true
                                        dismiss()
                                    case .failure(let err):
                                        message = err.localizedDescription
                                    }
                                }
                            } label: {
                                if isLoading { ProgressView() }
                                Text("验证密码并创建通行密钥")
                            }
                            .disabled(password.isEmpty || isLoading)
                        }
                    }
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("通行密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
