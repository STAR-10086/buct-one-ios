import BuctModel
import SwiftUI

struct HomeworkPlaceholderView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "checklist")
                                .font(.title2)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("作业 · \(RefreshState.never.displayLabel)")
                                    .font(.headline)
                                Text("M2 阶段接入北化在线（THEOL）两阶段同步待办、测验与表格导入")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

                        ForEach([
                            ("两阶段静默同步", "优先刷新待交作业与测验 DDL"),
                            ("原生预览与交作业", "QuickLook 预览附件，共享 Cookie 交作业"),
                            ("Excel / CSV 批量导入", "支持系统文件选择器与外部 App 分享导入")
                        ], id: \.0) { item in
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
            .navigationTitle("作业")
        }
        .onAppear {
            environment.trackVisit(path: "/tab/homework", title: "作业")
        }
    }
}
