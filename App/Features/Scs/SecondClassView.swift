import BuctModel
import SwiftUI

private enum ScsViewTab: String, CaseIterable {
    case scores = "五育成绩"
    case activities = "校园活动"
}

struct SecondClassView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var tab: ScsViewTab = .scores
    @State private var selectedTermId: String = ""
    @State private var didAutoSync = false

    private var snapshot: ScsSnapshot? {
        environment.scsSlice.data
    }

    private var currentTerm: ScsTermScore? {
        guard let terms = snapshot?.terms, !terms.isEmpty else { return nil }
        return terms.first(where: { $0.id == selectedTermId }) ?? terms.first
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
                    Picker("栏目", selection: $tab) {
                        ForEach(ScsViewTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if let err = environment.scsSlice.lastError, !err.isEmpty {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }

                            if let snap = snapshot {
                                if tab == .scores {
                                    scoresContent(snap)
                                } else {
                                    activitiesContent(snap.activities)
                                }
                            } else {
                                Text(environment.isSyncingScs ? "正在同步第二课堂数据..." : "暂无数据，下拉或点击右上角刷新")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(28)
                                    .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .refreshable {
                        await environment.refreshScs(userInitiated: true)
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("第二课堂")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if environment.currentProfile != nil {
                    Button {
                        Task { await environment.refreshScs(userInitiated: true) }
                    } label: {
                        if environment.isSyncingScs {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .onAppear {
            environment.trackVisit(path: "/module/secondClass", title: "第二课堂")
            if !didAutoSync, environment.currentProfile != nil,
               environment.scsSlice.provenance.refreshState == .never {
                didAutoSync = true
                Task { await environment.refreshScs(userInitiated: false) }
            }
        }
    }

    @ViewBuilder
    private func scoresContent(_ snap: ScsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snap.studentName.isEmpty ? "第二课堂综合素质" : snap.studentName)
                        .font(.headline)
                    let meta = [snap.collegeName, snap.className, snap.gradeName].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !meta.isEmpty {
                        Text(meta).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let win = snap.currentWindow {
                    Text(win.isOpen ? "自评开放中" : "自评未开放")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(win.isOpen ? Color.green : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((win.isOpen ? Color.green : Color.secondary).opacity(0.14), in: Capsule())
                }
            }

            if let term = currentTerm {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.1f", term.totalScore))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("总分").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if snap.terms.count > 1 {
                        Menu {
                            ForEach(snap.terms) { t in
                                Button(t.displayTitle) { selectedTermId = t.id }
                            }
                        } label: {
                            Label(term.displayTitle, systemImage: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.glass)
                    } else {
                        Text(term.displayTitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

        if let term = currentTerm {
            VStack(alignment: .leading, spacing: 10) {
                Text("五育进度").font(.subheadline.weight(.semibold))
                let maxMap = Dictionary(uniqueKeysWithValues: snap.dimensions.map { ($0.id, $0.totalScore) })
                dimensionBar("德育", score: term.moral, max: maxMap[1] ?? 180, color: .red)
                dimensionBar("智育", score: term.academic, max: maxMap[2] ?? 120, color: .blue)
                dimensionBar("体育", score: term.physical, max: maxMap[3] ?? 100, color: .green)
                dimensionBar("美育", score: term.aesthetics, max: maxMap[4] ?? 100, color: .purple)
                dimensionBar("劳育", score: term.labor, max: maxMap[5] ?? 100, color: .orange)
            }
            .padding(16)
            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

            ForEach(term.details) { cat in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(cat.typeName).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%.1f / %.0f", cat.score, cat.maxScore))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ForEach(cat.items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.caption.weight(.medium))
                                if item.laborHours > 0 {
                                    Text(String(format: "劳动时长：%.1f 小时", item.laborHours))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if !item.comment.isEmpty {
                                    Text(item.comment).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(String(format: "%.1f", item.score))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }

    private func dimensionBar(_ title: String, score: Double, max: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.weight(.medium))
                Spacer()
                Text(String(format: "%.1f / %.0f", score, max))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(1.0, max > 0 ? score / max : 0))
                .tint(color)
        }
    }

    @ViewBuilder
    private func activitiesContent(_ activities: [ScsActivityItem]) -> some View {
        if activities.isEmpty {
            Text("暂无活动记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(24)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        } else {
            ForEach(activities) { act in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(act.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        if !act.scoreText.isEmpty {
                            Text(act.scoreText)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    HStack(spacing: 8) {
                        if !act.categoryName.isEmpty { Text(act.categoryName) }
                        if !act.startTime.isEmpty { Text(act.startTime) }
                        if !act.location.isEmpty { Text(act.location) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
        }
    }
}
