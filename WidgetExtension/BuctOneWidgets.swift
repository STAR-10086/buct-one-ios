import BuctModel
import BuctStore
import SwiftUI
import WidgetKit

struct TodayScheduleEntry: TimelineEntry {
    let date: Date
    let snapshot: TodayWidgetSnapshot?
    let containerLabel: String
}

struct TodayScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayScheduleEntry {
        TodayScheduleEntry(date: Date(), snapshot: nil, containerLabel: "今日课表")
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayScheduleEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayScheduleEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> TodayScheduleEntry {
        let resolved = AppContainerResolver.resolveRootDirectory()
        let snapshotURL = resolved.url.appendingPathComponent("today_widget_snapshot.json")
        let snapshot: TodayWidgetSnapshot? = {
            guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
            return try? JSONDecoder().decode(TodayWidgetSnapshot.self, from: data)
        }()
        return TodayScheduleEntry(date: Date(), snapshot: snapshot, containerLabel: resolved.mode.displayName)
    }
}

struct TodayScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayScheduleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentColor)
                Text("今日课表")
                    .font(.headline)
                Spacer()
                if let week = entry.snapshot?.currentWeek {
                    Text("第\(week)周")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = entry.snapshot {
                if snapshot.courses.isEmpty {
                    Spacer()
                    Text("\(snapshot.dayLabel) 无课程")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    let limit = family == .systemSmall ? 2 : 3
                    ForEach(snapshot.courses.prefix(limit)) { course in
                        HStack(spacing: 6) {
                            Text("\(course.startPeriod)-\(course.endPeriod)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28, alignment: .leading)
                            Text(course.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            if family != .systemSmall && !course.location.isEmpty {
                                Text(course.location)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Spacer()
                Text("打开北化一站同步课表")
                    .font(.subheadline)
                Text(entry.containerLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
        .description("展示当天课程与节次地点")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BuctOneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayScheduleWidget()
    }
}
