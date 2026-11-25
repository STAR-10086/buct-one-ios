import BuctModel
import SwiftUI

private enum CampusNetLogTab: String, CaseIterable {
    case pay = "缴费清单"
    case checkout = "月度结算"
}

struct CampusNetView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var logTab: CampusNetLogTab = .pay
    @State private var didAutoSync = false

    private var snapshot: CampusNetSnapshot? {
        environment.campusNetSlice.data
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
                    LazyVStack(spacing: 12) {
                        if let err = environment.campusNetSlice.lastError, !err.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                if err.contains("WebVPN") || err.contains("校园网") {
                                    Text("校外网络会自动通过 w.buct.edu.cn WebVPN 代理访问 tree.buct.edu.cn，如提示认证失效请前往「我的 → WebVPN」完成一次认证。")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }

                        if let snap = snapshot {
                            heroCard(snap)
                            onlineDevicesCard(snap)

                            Picker("记录类型", selection: $logTab) {
                                ForEach(CampusNetLogTab.allCases, id: \.self) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)

                            if logTab == .pay {
                                payRecordsSection(snap.payRecords)
                            } else {
                                checkoutRecordsSection(snap.checkoutRecords)
                            }
                        } else {
                            Text(environment.isSyncingCampusNet ? "正在查询校园网状态与账单..." : "暂无数据，下拉或点击右上角刷新")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(28)
                                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await environment.refreshCampusNet(userInitiated: true)
                }
            }
        }
        .navigationTitle("校园网网费")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        Task { await environment.refreshCampusNet(userInitiated: true) }
                    } label: {
                        if environment.isSyncingCampusNet {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            environment.trackVisit(path: "/module/campusNet", title: "校园网网费")
            if !didAutoSync, environment.currentProfile != nil,
               environment.campusNetSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshCampusNet(userInitiated: false) }
            }
        }
    }

    private func heroCard(_ snap: CampusNetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.productsName.isEmpty ? "校园网套餐" : snap.productsName)
                        .font(.headline)
                    if !snap.billingName.isEmpty {
                        Text(snap.billingName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(snap.accountStatus.isEmpty ? (snap.isOnline ? "在线" : "离线") : snap.accountStatus)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(snap.isOnline ? Color.green : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background((snap.isOnline ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
            }

            HStack(spacing: 12) {
                metricBox(title: "产品余额", value: formatMoney(snap.userBalance))
                metricBox(title: "电子钱包", value: formatMoney(snap.walletBalance))
                metricBox(title: "本月月租", value: formatMoney(snap.userCharge))
            }

            Divider()

            HStack {
                Label("已用流量：\(snap.displayTrafficText)", systemImage: "arrow.up.arrow.down")
                    .font(.caption)
                Spacer()
                Label("在线时长：\(snap.displayDurationText)", systemImage: "clock")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if !snap.onlineIp.isEmpty {
                Label("当前 IP：\(snap.onlineIp)", systemImage: "network")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func metricBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func onlineDevicesCard(_ snap: CampusNetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("在线设备")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(snap.onlineDeviceTotal) 台")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if snap.onlineDevices.isEmpty {
                Text(snap.isOnline ? "当前设备已在线（\(snap.onlineIp)）" : "暂无在线设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snap.onlineDevices) { dev in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.ip)
                                .font(.caption.weight(.semibold).monospaced())
                            if !dev.loginTime.isEmpty {
                                Text("上线：\(dev.loginTime)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !dev.billingName.isEmpty {
                            Text(dev.billingName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    @ViewBuilder
    private func payRecordsSection(_ records: [CampusNetPayRecord]) -> some View {
        if records.isEmpty {
            emptyCard("暂无缴费记录")
        } else {
            ForEach(records) { rec in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.payType.isEmpty ? "校园网充值" : rec.payType)
                            .font(.subheadline.weight(.medium))
                        Text(rec.payTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(rec.amountText)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    @ViewBuilder
    private func checkoutRecordsSection(_ records: [CampusNetCheckoutRecord]) -> some View {
        if records.isEmpty {
            emptyCard("暂无月度结算记录")
        } else {
            ForEach(records) { rec in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(rec.productName.isEmpty ? "月度结算" : rec.productName)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(rec.feeText)
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    HStack {
                        if !rec.trafficText.isEmpty { Text("流量：\(rec.trafficText)") }
                        if !rec.durationText.isEmpty { Text("时长：\(rec.durationText)") }
                        Spacer()
                        Text(rec.checkoutTime)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    private func formatMoney(_ val: Double?) -> String {
        guard let val else { return "--" }
        return String(format: "¥%.2f", val)
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
