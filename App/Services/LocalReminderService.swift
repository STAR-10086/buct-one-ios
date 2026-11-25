import BuctModel
import Foundation
import UserNotifications

public actor LocalReminderService {
    private static let coursePrefix = "buct_course_"
    private static let examPrefix = "buct_exam_"
    private static let ddlPrefix = "buct_ddl_"

    public init() {}

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    public func clearAllReminders() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
    }

    public func reschedule(
        courses: [ScheduleCourse],
        exams: [ExamItem],
        books: [PortalBookItem] = [],
        homeworks: [TheolHomeworkItem] = [],
        firstWeekMonday: String,
        config: ReminderConfig,
        isDemoMode: Bool
    ) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let oldIds = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.coursePrefix) || $0.hasPrefix(Self.examPrefix) || $0.hasPrefix(Self.ddlPrefix) }
        if !oldIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: oldIds)
        }

        guard !isDemoMode else { return }
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        let now = Date()
        var scheduledCount = 0

        if config.courseReminderEnabled {
            var upcoming: [(date: Date, title: String, body: String, id: String)] = []
            let currentWeek = ScheduleDates.weekAt(firstWeekMonday: firstWeekMonday, now: now) ?? 1

            for course in courses where !config.mutedCourseIds.contains(course.id) {
                guard let startSlot = BuctTimeSlots.periods.first(where: { $0.period == course.startPeriod }) else {
                    continue
                }
                let timeParts = startSlot.start.split(separator: ":").compactMap { Int($0) }
                guard timeParts.count == 2 else { continue }

                for week in course.weeks where week >= currentWeek {
                    guard let dayUTC = ScheduleDates.dateFor(
                        firstWeekMonday: firstWeekMonday,
                        week: week,
                        dayOfWeek: course.dayOfWeek
                    ) else { continue }
                    let dateStr = ScheduleDates.formatUTCDate(dayUTC)
                    guard let classStart = Self.beijingDate(dateStr: dateStr, hour: timeParts[0], minute: timeParts[1]) else {
                        continue
                    }
                    let trigger = classStart.addingTimeInterval(TimeInterval(-config.courseLeadMinutes * 60))
                    if trigger > now {
                        let body = [
                            BuctTimeSlots.timeRangeText(startPeriod: course.startPeriod, endPeriod: course.endPeriod),
                            course.location
                        ].filter { !$0.isEmpty }.joined(separator: " · ")
                        upcoming.append((
                            date: trigger,
                            title: "即将上课：\(course.name)",
                            body: body.isEmpty ? "请准备上课" : body,
                            id: "\(Self.coursePrefix)\(course.id)_w\(week)"
                        ))
                        break
                    }
                }
            }

            for item in upcoming.sorted(by: { $0.date < $1.date }).prefix(32) {
                await scheduleNotification(id: item.id, title: item.title, body: item.body, fireDate: item.date)
                scheduledCount += 1
            }
        }

        if config.examReminderEnabled {
            let offsets: [(minutes: Int, label: String)] = [
                (1440, "明天"),
                (120, "2 小时后")
            ]
            for exam in exams {
                guard let start = exam.parsedStartDate() else { continue }
                for offset in offsets {
                    guard scheduledCount < 58 else { break }
                    let trigger = start.addingTimeInterval(TimeInterval(-offset.minutes * 60))
                    guard trigger > now else { continue }
                    let body = [exam.examTime, exam.location, exam.seatNumber.isEmpty ? "" : "座位 \(exam.seatNumber)"]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    await scheduleNotification(
                        id: "\(Self.examPrefix)\(exam.id)_\(offset.minutes)",
                        title: "\(offset.label)考试：\(exam.courseName)",
                        body: body,
                        fireDate: trigger
                    )
                    scheduledCount += 1
                }
            }
        }

        if config.examReminderEnabled {
            for hw in homeworks where hw.canSubmit {
                guard let deadlineMs = hw.deadlineMillis else { continue }
                let deadline = Date(timeIntervalSince1970: TimeInterval(deadlineMs) / 1000.0)
                for (hours, label) in [(24, "明天截止"), (2, "2 小时后截止")] {
                    guard scheduledCount < 60 else { break }
                    let trigger = deadline.addingTimeInterval(TimeInterval(-hours * 3600))
                    guard trigger > now else { continue }
                    await scheduleNotification(
                        id: "\(Self.ddlPrefix)hw_\(hw.id)_\(hours)",
                        title: "\(label)：\(hw.title)",
                        body: "\(hw.courseName) · 截止 \(hw.deadline)",
                        fireDate: trigger
                    )
                    scheduledCount += 1
                }
            }

            for book in books {
                let normalized = book.dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "/", with: "-")
                guard normalized.count >= 10,
                      let day09 = Self.beijingDate(dateStr: String(normalized.prefix(10)), hour: 9, minute: 0) else {
                    continue
                }
                for (days, label) in [(3, "3 天后到期"), (0, "今日到期")] {
                    guard scheduledCount < 62 else { break }
                    let trigger = day09.addingTimeInterval(TimeInterval(-days * 86_400))
                    guard trigger > now else { continue }
                    await scheduleNotification(
                        id: "\(Self.ddlPrefix)book_\(book.barcode)_\(days)",
                        title: "图书\(label)：\(book.title)",
                        body: "应还日期：\(book.dueDate)",
                        fireDate: trigger
                    )
                    scheduledCount += 1
                }
            }
        }
    }

    private func scheduleNotification(id: String, title: String, body: String, fireDate: Date) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func beijingDate(dateStr: String, hour: Int, minute: Int) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: String(format: "%@ %02d:%02d", dateStr, hour, minute))
    }
}
