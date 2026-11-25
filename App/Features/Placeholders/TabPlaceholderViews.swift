import BuctModel
import SwiftUI

struct SchedulePlaceholderView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        PlaceholderTabContainer(
            title: "课表",
            icon: "calendar",
            subtitle: "M1 阶段接入本科 jwglxt / 研究生 gmis 课表与 i北化校历自动校准",
            cards: [
                ("周视图与日视图", "支持多学期切换、自定义课程与 ICS 日历导出"),
                ("官方校历自动校准", "首次同步 i北化后自动对齐当前教学周"),
                ("本地智能提醒", "支持课前提醒与考试倒计时本地通知")
            ]
        )
        .onAppear {
            environment.trackVisit(path: "/tab/schedule", title: "课表")
        }
    }
}

struct GradesPlaceholderView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        PlaceholderTabContainer(
            title: "成绩",
            icon: "chart.line.uptrend.xyaxis",
            subtitle: "M1 阶段接入成绩明细、Swift Charts 累计 GPA 折线图与培养方案树",
            cards: [
                ("学期与总体成绩", "保留重修 / 补考徽章与官方口径去重"),
                ("目标 GPA 试算器", "本地即时模拟后续学分绩点走势"),
                ("多级培养方案", "原生可展开树状课程完成度视图")
            ]
        )
        .onAppear {
            environment.trackVisit(path: "/tab/grades", title: "成绩")
        }
    }
}

struct HomeworkPlaceholderView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        PlaceholderTabContainer(
            title: "作业",
            icon: "checklist",
            subtitle: "M2 阶段接入北化在线（THEOL）两阶段同步待办、测验与表格导入",
            cards: [
                ("两阶段静默同步", "优先刷新待办作业与测验 DDL"),
                ("原生预览与交作业", "QuickLook 预览附件，共享 Cookie 交作业"),
                ("Excel / CSV 批量导入", "支持系统文件选择器与外部 App 分享导入")
            ]
        )
        .onAppear {
            environment.trackVisit(path: "/tab/homework", title: "作业")
        }
    }
}

private struct PlaceholderTabContainer: View {
    @Environment(AppEnvironment.self) private var environment

    let title: String
    let icon: String
    let subtitle: String
    let cards: [(String, String)]

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: icon)
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(title) · \(RefreshState.never.displayLabel)")
                                    .font(.headline)
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

                        ForEach(cards, id: \.0) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.0)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.1)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(title)
        }
    }
}
