import Foundation

public enum ICalExporter {
    /// 生成 RFC-5545 标准的课表 `.ics` 内容，可直接导入 iOS 系统日历。
    public static func exportSchedule(
        courses: [ScheduleCourse],
        term: AcademicTerm,
        firstWeekMonday: String,
        calendarName: String = "北化一站课表"
    ) -> String {
        guard let mondayDate = ScheduleDates.parseUTCDate(firstWeekMonday) else {
            return ""
        }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!

        let nowStamp = formatUTCTimestamp(Date())
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//BUCT One//iOS Schedule Exporter//ZH",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:\(escapeText("\(calendarName) (\(term.shortLabel))"))",
            "X-WR-TIMEZONE:Asia/Shanghai",
            "BEGIN:VTIMEZONE",
            "TZID:Asia/Shanghai",
            "BEGIN:STANDARD",
            "TZOFFSETFROM:+0800",
            "TZOFFSETTO:+0800",
            "TZNAME:CST",
            "DTSTART:19700101T000000",
            "END:STANDARD",
            "END:VTIMEZONE"
        ]

        let sortedCourses = courses.sorted {
            if $0.dayOfWeek != $1.dayOfWeek { return $0.dayOfWeek < $1.dayOfWeek }
            if $0.startPeriod != $1.startPeriod { return $0.startPeriod < $1.startPeriod }
            return $0.name < $1.name
        }

        for course in sortedCourses {
            let startClock = (BuctTimeSlots.periods.first(where: { $0.period == course.startPeriod })?.start ?? "08:00")
                .replacingOccurrences(of: ":", with: "")
            let endClock = (BuctTimeSlots.periods.first(where: { $0.period == course.endPeriod })?.end ?? "09:35")
                .replacingOccurrences(of: ":", with: "")

            var descParts: [String] = []
            if !course.teacher.isEmpty { descParts.append("教师：\(course.teacher)") }
            descParts.append("节次：第 \(course.startPeriod)-\(course.endPeriod) 节")
            if !course.weeksText.isEmpty { descParts.append("周次：\(course.weeksText)") }
            let description = descParts.joined(separator: "\\n")

            let safeCourseId = course.id
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "@", with: "_")

            for week in course.weeks.sorted() where (1...ScheduleWeeks.maxWeek).contains(week) {
                let dayOffset = (week - 1) * 7 + max(0, course.dayOfWeek - 1)
                guard let eventDate = utcCal.date(byAdding: .day, value: dayOffset, to: mondayDate) else {
                    continue
                }
                let comps = utcCal.dateComponents([.year, .month, .day], from: eventDate)
                let dateStr = String(format: "%04d%02d%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)

                lines.append("BEGIN:VEVENT")
                lines.append("UID:buct-\(term.id)-\(safeCourseId)-w\(week)@buct.one")
                lines.append("DTSTAMP:\(nowStamp)")
                lines.append("DTSTART;TZID=Asia/Shanghai:\(dateStr)T\(startClock)00")
                lines.append("DTEND;TZID=Asia/Shanghai:\(dateStr)T\(endClock)00")
                lines.append("SUMMARY:\(escapeText(course.name))")
                if !course.location.isEmpty {
                    lines.append("LOCATION:\(escapeText(course.location))")
                }
                lines.append("DESCRIPTION:\(description)")
                lines.append("END:VEVENT")
            }
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func escapeText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func formatUTCTimestamp(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            c.year ?? 2026, c.month ?? 1, c.day ?? 1,
            c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
    }
}
