import BuctModel
import SwiftUI

struct ScheduleView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isDayView = false
    @State private var selectedDayOfWeek = ScheduleDates.todayDayOfWeek()
    @State private var selectedCourse: ScheduleCourse?
    @State private var showAddCourseSheet = false
    @State private var showCalendarSettings = false

    private let palette: [Color] = [
        .blue, .teal, .indigo, .cyan, .mint, .purple,
        .orange, .pink, .green, .brown, .red, .yellow
    ]

    private var coursesInSelectedWeek: [ScheduleCourse] {
        environment.allScheduleCourses.filter { $0.weeks.contains(environment.selectedWeek) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                VStack(spacing: 10) {
                    controlBar

                    if environment.currentProfile == nil {
                        emptyPromptCard(
                            title: "未登录教务账号",
                            subtitle: "登录后自动同步本科/研究生课表，并与 i北化官方校历校准教学周",
                            buttonTitle: "去登录"
                        ) {
                            environment.showLoginSheet = true
                        }
                    } else if isDayView {
                        dayScheduleList
                    } else {
                        weekScheduleGrid
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .navigationTitle("课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("课表")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    if environment.currentProfile != nil {
                        Button {
                            showCalendarSettings = true
                        } label: {
                            Image(systemName: "calendar.badge.clock")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if environment.currentProfile != nil {
                        Button {
                            showAddCourseSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        Button {
                            Task { await environment.refreshSchedule(userInitiated: true) }
                        } label: {
                            if environment.isSyncingSchedule {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .sheet(item: $selectedCourse) { course in
                CourseDetailSheet(course: course)
            }
            .sheet(isPresented: $showAddCourseSheet) {
                AddCustomCourseSheet()
            }
            .sheet(isPresented: $showCalendarSettings) {
                ScheduleCalendarSettingsSheet()
            }
            .onAppear {
                environment.trackVisit(path: "/tab/schedule", title: "课表")
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(environment.availableTerms) { term in
                    Button(term.displayName) {
                        Task { await environment.selectTerm(term) }
                    }
                }
            } label: {
                Label(environment.selectedTerm.shortLabel, systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            Menu {
                if let current = environment.currentTeachingWeek, current != environment.selectedWeek {
                    Button("回到本周（第 \(current) 周）") {
                        withAnimation(.snappy) {
                            environment.selectedWeek = current
                        }
                    }
                    Divider()
                }
                ForEach(1...ScheduleWeeks.maxWeek, id: \.self) { week in
                    Button {
                        withAnimation(.snappy) {
                            environment.selectedWeek = week
                        }
                    } label: {
                        if environment.currentTeachingWeek == week {
                            Text("第 \(week) 周（本周）")
                        } else {
                            Text("第 \(week) 周")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text("第\(environment.selectedWeek)周")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    if environment.currentTeachingWeek == environment.selectedWeek {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            Spacer(minLength: 4)

            Picker("视图", selection: $isDayView) {
                Text("周").tag(false)
                Text("日").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 84)
        }
        .frame(height: 36)
    }

    private var weekScheduleGrid: some View {
        let weekBinding = Binding<Int>(
            get: { environment.selectedWeek },
            set: { environment.selectedWeek = $0 }
        )

        return TabView(selection: weekBinding) {
            ForEach(1...ScheduleWeeks.maxWeek, id: \.self) { week in
                weekPageGrid(for: week)
                    .tag(week)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func weekPageGrid(for week: Int) -> some View {
        let rowHeight: CGFloat = 68
        let railW: CGFloat = 34
        let gap: CGFloat = 3
        let dayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let todayDow = ScheduleDates.todayDayOfWeek()
        let weekCourses = environment.allScheduleCourses.filter { $0.weeks.contains(week) }
        let weekStartDate = ScheduleDates.parseUTCDate(environment.firstWeekMonday)
            .flatMap { Calendar(identifier: .gregorian).date(byAdding: .day, value: (week - 1) * 7, to: $0) }

        return VStack(spacing: 6) {
            HStack(spacing: gap) {
                Text("节")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: railW)

                ForEach(1...7, id: \.self) { day in
                    let isToday = day == todayDow && environment.currentTeachingWeek == week
                    VStack(spacing: 1) {
                        Text(dayLabels[day - 1])
                            .font(.caption2.weight(isToday ? .bold : .medium))
                        if let start = weekStartDate,
                           let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: day - 1, to: start) {
                            Text(shortMonthDay(date))
                                .font(.system(size: 8.5))
                                .foregroundStyle(isToday ? Color.accentColor : .secondary)
                        }
                    }
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        isToday ? Color.accentColor.opacity(0.14) : Color.clear,
                        in: Capsule()
                    )
                }
            }

            ScrollView {
                GeometryReader { geo in
                    let colW = max(24, (geo.size.width - railW - gap * 7) / 7)

                    ZStack(alignment: .topLeading) {
                        // 左侧节次时间轴与背景网格线（对齐安卓版 12 节作息时间与边界网格）
                        VStack(spacing: 0) {
                            ForEach(BuctTimeSlots.periods, id: \.period) { slot in
                                HStack(alignment: .top, spacing: 0) {
                                    VStack(spacing: 1) {
                                        Text("\(slot.period)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(slot.start)
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        Text(slot.end)
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    .padding(.top, 4)
                                    .frame(width: railW, height: rowHeight, alignment: .top)

                                    VStack(spacing: 0) {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.12))
                                            .frame(height: 0.5)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: rowHeight)
                                }
                            }
                        }

                        // 课程色块（课程名 + 任课教师 + 教室地点）
                        ForEach(weekCourses) { course in
                            let x = railW + gap + CGFloat(course.dayOfWeek - 1) * (colW + gap)
                            let y = CGFloat(course.startPeriod - 1) * rowHeight + 2
                            let span = max(1, course.endPeriod - course.startPeriod + 1)
                            let h = CGFloat(span) * rowHeight - 4
                            let tint = palette[course.colorIndex % palette.count]

                            Button {
                                selectedCourse = course
                            } label: {
                                HStack(spacing: 0) {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(tint.opacity(0.85))
                                        .frame(width: 3)
                                        .padding(.vertical, 3)

                                    VStack(alignment: .leading, spacing: 1.5) {
                                        Text(course.name)
                                            .font(.system(size: span == 1 ? 9.5 : 10.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(span == 1 ? 2 : 3)
                                            .multilineTextAlignment(.leading)

                                        if !course.teacher.isEmpty {
                                            Text(course.teacher)
                                                .font(.system(size: 8.5, weight: .medium))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        if !course.location.isEmpty {
                                            Text(course.location)
                                                .font(.system(size: 8.5))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(span >= 3 ? 3 : 2)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 3)
                                }
                                .frame(width: colW, height: h, alignment: .topLeading)
                                .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(tint.opacity(0.38), lineWidth: 0.7)
                                )
                            }
                            .buttonStyle(.plain)
                            .offset(x: x, y: y)
                        }
                    }
                }
                .frame(height: rowHeight * CGFloat(BuctTimeSlots.periods.count) + 16)
            }
            .refreshable {
                await environment.refreshSchedule(userInitiated: true)
            }
        }
    }

    private func shortMonthDay(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = cal.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 1)/\(comps.day ?? 1)"
    }

    private var dayScheduleList: some View {
        let dayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let dayCourses = coursesInSelectedWeek
            .filter { $0.dayOfWeek == selectedDayOfWeek }
            .sorted { $0.startPeriod < $1.startPeriod }

        return VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...7, id: \.self) { day in
                        Button {
                            selectedDayOfWeek = day
                        } label: {
                            Text(dayLabels[day - 1])
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .tint(selectedDayOfWeek == day ? Color.accentColor : .secondary)
                    }
                }
            }

            ScrollView {
                if dayCourses.isEmpty {
                    Text("当日无课")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(32)
                        .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                } else {
                    VStack(spacing: 10) {
                        ForEach(dayCourses) { course in
                            Button {
                                selectedCourse = course
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(course.startPeriod)-\(course.endPeriod) 节")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.accentColor)
                                        Text(BuctTimeSlots.timeRangeText(startPeriod: course.startPeriod, endPeriod: course.endPeriod))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 74, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(course.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text([course.location, course.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .buctGlassCard(cornerRadius: 18, interactive: true, enabled: environment.appearance.liquidGlassEnabled)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func emptyPromptCard(title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Spacer()
            VStack(spacing: 10) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(buttonTitle, action: action)
                    .buttonStyle(.glassProminent)
            }
            .padding(24)
            .buctGlassCard(cornerRadius: 24, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            Spacer()
        }
    }
}

private struct CourseDetailSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let course: ScheduleCourse

    private var isMuted: Bool {
        environment.reminderConfig.mutedCourseIds.contains(course.id)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("课程信息") {
                    LabeledContent("课程名称", value: course.name)
                    if !course.teacher.isEmpty { LabeledContent("任课教师", value: course.teacher) }
                    if !course.location.isEmpty { LabeledContent("上课地点", value: course.location) }
                    LabeledContent("节次时间", value: "第 \(course.startPeriod)-\(course.endPeriod) 节 · \(BuctTimeSlots.timeRangeText(startPeriod: course.startPeriod, endPeriod: course.endPeriod))")
                    LabeledContent("上课周次", value: course.weeksText)
                }

                Section("本地通知") {
                    Toggle("开启本课程课前提醒", isOn: Binding(
                        get: { !isMuted },
                        set: { enabled in
                            var cfg = environment.reminderConfig
                            if enabled {
                                cfg.mutedCourseIds.remove(course.id)
                            } else {
                                cfg.mutedCourseIds.insert(course.id)
                            }
                            Task { await environment.updateReminderConfig(cfg) }
                        }
                    ))
                }

                if course.isCustom {
                    Section {
                        Button("删除自定义课程", role: .destructive) {
                            Task {
                                await environment.deleteCustomCourse(id: course.id)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("课程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct AddCustomCourseSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var teacher = ""
    @State private var location = ""
    @State private var dayOfWeek = 1
    @State private var startPeriod = 1
    @State private var endPeriod = 2
    @State private var weeksText = "1-16周"

    var body: some View {
        NavigationStack {
            Form {
                TextField("课程名称", text: $name)
                TextField("教师（可选）", text: $teacher)
                TextField("教室（可选）", text: $location)
                Picker("星期", selection: $dayOfWeek) {
                    ForEach(1...7, id: \.self) { d in
                        Text(["周一", "周二", "周三", "周四", "周五", "周六", "周日"][d - 1]).tag(d)
                    }
                }
                Stepper("开始节次：第 \(startPeriod) 节", value: $startPeriod, in: 1...12)
                Stepper("结束节次：第 \(endPeriod) 节", value: $endPeriod, in: startPeriod...12)
                TextField("周次（如 1-16周 或 1-8周(单)）", text: $weeksText)
            }
            .navigationTitle("添加自定义课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let weeks = ScheduleWeeks.parse(weeksText)
                        let course = ScheduleCourse(
                            id: "custom-\(UUID().uuidString)",
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                            dayOfWeek: dayOfWeek,
                            startPeriod: startPeriod,
                            endPeriod: max(startPeriod, endPeriod),
                            weeksText: weeksText,
                            weeks: weeks.isEmpty ? Array(1...16) : weeks,
                            isCustom: true,
                            colorIndex: abs(name.hashValue) % 12
                        )
                        Task {
                            await environment.addCustomCourse(course)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ScheduleCalendarSettingsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var manualDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("i北化官方校历校准") {
                    LabeledContent("当前学期", value: environment.selectedTerm.displayName)
                    LabeledContent("第一周周一", value: environment.firstWeekMonday)
                    LabeledContent("校准状态", value: environment.calendarSlice.provenance.refreshState.displayLabel)

                    if environment.currentProfile?.systemType == .undergradJwglxt {
                        Button {
                            Task { await environment.calibrateOfficialCalendar(forceOverrideManual: true) }
                        } label: {
                            HStack {
                                Text("从 i北化一键重校准")
                                Spacer()
                                if environment.isSyncingCalendar { ProgressView() }
                            }
                        }
                    }
                }

                Section("手动调整开学日期") {
                    DatePicker("选择开学周任意一天", selection: $manualDate, displayedComponents: .date)
                    Button("应用手动开学日期") {
                        Task { await environment.setManualSemesterStart(manualDate) }
                    }
                }

                Section("课前本地通知") {
                    Toggle("启用课前提醒", isOn: Binding(
                        get: { environment.reminderConfig.courseReminderEnabled },
                        set: { enabled in
                            Task {
                                if enabled {
                                    _ = await environment.reminderService.requestAuthorization()
                                }
                                var cfg = environment.reminderConfig
                                cfg.courseReminderEnabled = enabled
                                await environment.updateReminderConfig(cfg)
                            }
                        }
                    ))
                    Stepper(
                        "提前 \(environment.reminderConfig.courseLeadMinutes) 分钟提醒",
                        value: Binding(
                            get: { environment.reminderConfig.courseLeadMinutes },
                            set: { mins in
                                var cfg = environment.reminderConfig
                                cfg.courseLeadMinutes = mins
                                Task { await environment.updateReminderConfig(cfg) }
                            }
                        ),
                        in: 5...60,
                        step: 5
                    )
                }
            }
            .navigationTitle("校历与提醒设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if let parsed = ScheduleDates.parseUTCDate(environment.firstWeekMonday) {
                    manualDate = parsed
                }
            }
        }
    }
}
