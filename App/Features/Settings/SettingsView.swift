import BuctModel
import BuctStore
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var copiedSourceURL = false

    private let sideStoreSourceURL = "https://update.buct.one/ios/apps.json"

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
                        appearanceCard
                        dataAndSecurityCard
                        aboutCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle("我的")
            .onAppear {
                environment.trackVisit(path: "/tab/settings", title: "我的")
            }
        }
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("未登录统一身份认证")
                    .font(.headline)
                Text("M1 阶段接入 sidportal 原生认证、短信 2FA 与 Face ID 通行密钥")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
}
