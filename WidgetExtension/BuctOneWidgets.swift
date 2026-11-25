import BuctModel
import BuctStore
import SwiftUI
import WidgetKit

struct TodayScheduleEntry: TimelineEntry {
    let date: Date
    let containerLabel: String
}

struct TodayScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayScheduleEntry {
        TodayScheduleEntry(date: Date(), containerLabel: "今日课表")
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayScheduleEntry) -> Void) {
        let resolved = AppContainerResolver.resolveRootDirectory()
        completion(TodayScheduleEntry(date: Date(), containerLabel: resolved.mode.displayName))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayScheduleEntry>) -> Void) {
        let resolved = AppContainerResolver.resolveRootDirectory()
        let entry = TodayScheduleEntry(date: Date(), containerLabel: resolved.mode.displayName)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct TodayScheduleWidgetView: View {
    let entry: TodayScheduleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                Text("今日课表")
                    .font(.headline)
            }
            Spacer()
            Text("打开北化一站同步课表")
                .font(.subheadline)
            Text(entry.containerLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct TodayScheduleWidget: Widget {
    let kind = "com.buct.one.widget.today"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayScheduleProvider()) { entry in
            TodayScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("今日课表")
        .description("展示当天课程与下一节课提示（M4 完整接入）")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BuctOneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayScheduleWidget()
    }
}
