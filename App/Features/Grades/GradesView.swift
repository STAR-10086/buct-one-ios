import BuctModel
import Charts
import SwiftUI

private enum GradesSubTab: String, CaseIterable {
    case grades = "成绩"
    case curriculum = "培养方案"
    case exams = "考试"
}

struct GradesView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var subTab: GradesSubTab = .grades
    @State private var showAllSemesters = true
    @State private var trendByTerm = false
    @State private var showSimulator = false
    @State private var targetGpa: Double = 3.50
    @State private var plannedCredits: Double = 20
    @State private var expandedGradeIds: Set<String> = []

    // 培养方案状态
    @State private var curriculumFilterMode = 0 // 0=未修/在修, 1=已通过, 2=全部
    @State private var expandedCurriculumIds: Set<String> = []
    @State private var didInitCurriculumExpand = false

    // 考试状态
    @State private var showAddExamSheet = false

    private var activeGrades: [GradeItem] {
        if showAllSemesters {
            return environment.overallAcademicSlice.data?.grades ?? (environment.semesterGradesSlice.data ?? [])
        }
        return environment.semesterGradesSlice.data ?? []
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                VStack(spacing: 10) {
                    Picker("学业模块", selection: $subTab) {
                        ForEach(GradesSubTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if environment.currentProfile == nil {
                        Spacer()
                        VStack(spacing: 10) {
                            Text("未登录教务账号").font(.headline)
                            Text("登录后可查看成绩单、累计 GPA 曲线、培养方案树与考试倒计时")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("去登录") {
                                environment.showLoginSheet = true
                            }
                            .buttonStyle(.glassProminent)
                        }
                        .padding(24)
                        .buctGlassCard(cornerRadius: 24, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                        .padding(.horizontal, 20)
                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: 14) {
                                switch subTab {
                                case .grades:
                                    gradesContent
                                case .curriculum:
                                    curriculumContent
                                case .exams:
                                    examsContent
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("学业")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if environment.currentProfile != nil {
                        if subTab == .exams {
                            Button {
                                showAddExamSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                        Button {
                            Task {
                                if subTab == .exams {
                                    await environment.refreshExams(userInitiated: true)
                                } else {
                                    await environment.refreshGrades(userInitiated: true)
                                }
                            }
                        } label: {
                            if environment.isSyncingGrades || environment.isSyncingExams {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddExamSheet) {
                AddCustomExamSheet()
            }
            .onAppear {
                environment.trackVisit(path: "/tab/grades", title: "成绩")
            }
        }
    }

    // MARK: - 成绩 Tab

    @ViewBuilder
    private var gradesContent: some View {
        HStack {
            Menu {
                Button("全部学期（总览）") {
                    showAllSemesters = true
                }
                ForEach(environment.availableTerms) { term in
                    Button(term.displayName) {
                        showAllSemesters = false
                        Task {
                            await environment.selectTerm(term)
                            await environment.refreshGrades(userInitiated: true)
                        }
                    }
                }
            } label: {
                Label(showAllSemesters ? "全部学期" : environment.selectedTerm.displayName, systemImage: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)

            Spacer()

            Text(environment.overallAcademicSlice.provenance.refreshState.displayLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        let summary = environment.overallAcademicSlice.data?.summary
        let computed = BuctGpaScale.computeWeightedGpa(activeGrades)
        let displayGpa = (showAllSemesters ? summary?.officialGpa : nil) ?? computed.gpa
        let displayCredits = (showAllSemesters ? summary?.officialCredits : nil) ?? computed.credits

        HStack(spacing: 12) {
            statTile(title: "加权 GPA", value: String(format: "%.2f", displayGpa), accent: true)
            statTile(title: "已获学分", value: String(format: "%.1f", displayCredits), accent: false)
            statTile(title: "课程门数", value: "\(BuctGpaScale.deduplicateBestAttempts(activeGrades).count)", accent: false)
        }

        let allForTrend = environment.overallAcademicSlice.data?.grades ?? activeGrades
        let trendPoints = trendByTerm
            ? BuctGpaScale.buildTermGpaTrend(allForTrend)
            : BuctGpaScale.buildYearlyGpaTrend(allForTrend)

        if trendPoints.count >= 2 {
            gpaTrendCard(points: trendPoints)
        }

        if computed.credits > 0 {
            targetGpaSimulatorCard(grades: allForTrend, officialGpa: summary?.officialGpa)
        }

        if activeGrades.isEmpty {
            Text("暂无成绩记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(28)
                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(activeGrades) { item in
                    gradeRow(item)
                }
            }
        }
    }

    private func statTile(title: String, value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(accent ? Color.accentColor : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func gpaTrendCard(points: [GpaTrendPoint]) -> some View {
        let minY = max(0.0, (points.map(\.gpa).min() ?? 2.0) - 0.35)
        let maxY = min(4.33, (points.map(\.gpa).max() ?? 4.0) + 0.25)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("累计 GPA 趋势")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("维度", selection: $trendByTerm) {
                    Text("按学年").tag(false)
                    Text("按学期").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 126)
            }

            Chart(points) { pt in
                AreaMark(
                    x: .value("时间", pt.shortLabel),
                    yStart: .value("下界", minY),
                    yEnd: .value("GPA", pt.gpa)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", pt.shortLabel),
                    y: .value("GPA", pt.gpa)
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .foregroundStyle(Color.accentColor)

                PointMark(
                    x: .value("时间", pt.shortLabel),
                    y: .value("GPA", pt.gpa)
                )
                .foregroundStyle(Color.accentColor)
                .annotation(position: .top) {
                    Text(String(format: "%.2f", pt.gpa))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: minY...maxY)
            .frame(height: 150)
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func targetGpaSimulatorCard(grades: [GradeItem], officialGpa: Double?) -> some View {
        let est = BuctGpaScale.estimateTargetGpa(
            grades: grades,
            officialGpa: officialGpa,
            targetGpa: targetGpa,
            plannedCredits: plannedCredits
        )

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { showSimulator.toggle() }
            } label: {
                HStack {
                    Label("目标 GPA 试算器", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: showSimulator ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showSimulator {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("目标 GPA：\(String(format: "%.2f", targetGpa))")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                    Slider(value: $targetGpa, in: 2.0...4.33, step: 0.05)

                    HStack {
                        Text("计划后续学分：\(Int(plannedCredits))")
                            .font(.caption.weight(.medium))
                        Spacer()
                    }
                    Slider(value: $plannedCredits, in: 5...80, step: 1)

                    let bannerColor: Color = est.alreadyReached ? .green : (est.achievable ? .accentColor : .red)
                    let bannerText: String = {
                        if est.alreadyReached {
                            return "当前 GPA（\(String(format: "%.2f", est.currentGpa))）已达到目标！"
                        } else if est.achievable {
                            return "后续 \(Int(plannedCredits)) 学分需平均取得 GPA \(String(format: "%.2f", est.requiredGpa))"
                        } else {
                            return "后续需 GPA \(String(format: "%.2f", est.requiredGpa))（超过 4.33 上限，建议增加计划学分）"
                        }
                    }()

                    Text(bannerText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(bannerColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(bannerColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(16)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func gradeRow(_ item: GradeItem) -> some View {
        let isExpanded = expandedGradeIds.contains(item.id)
        let isSpecialNature = item.examNature.contains("重修") || item.examNature.contains("补考")
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy) {
                    if isExpanded { expandedGradeIds.remove(item.id) }
                    else { expandedGradeIds.insert(item.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(item.courseName)
                                .font(.subheadline.weight(.semibold))
                            if isSpecialNature {
                                Text(item.examNature)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                            }
                        }
                        Text("\(String(format: "%.1f", item.credits)) 学分 · \(item.courseType.isEmpty ? "课程" : item.courseType)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(item.score)
                            .font(.headline)
                            .foregroundStyle(BuctGpaScale.isCreditEarned(item.score) ? Color.accentColor : Color.red)
                        if let pt = BuctGpaScale.effectiveGpaPoint(item) {
                            Text("绩点 \(String(format: "%.2f", pt))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded && !item.detail.isEmpty {
                Divider()
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    // MARK: - 培养方案 Tab

    @ViewBuilder
    private var curriculumContent: some View {
        let nodes = environment.overallAcademicSlice.data?.curriculumNodes ?? []
        if nodes.isEmpty {
            Text(environment.currentProfile?.systemType == .graduateGmis ? "研究生端暂不提供独立树状培养方案，请查看成绩标签中的学位课/非学位课分类" : "暂无培养方案数据，请点击右上角刷新")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(28)
                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        } else {
            let entries = CurriculumTreeBuilder.buildVisibleTree(nodes: nodes, expandedIds: expandedCurriculumIds)
            HStack {
                Picker("课程筛选", selection: $curriculumFilterMode) {
                    Text("待修").tag(0)
                    Text("已过").tag(1)
                    Text("全部").tag(2)
                }
                .pickerStyle(.segmented)

                Button(expandedCurriculumIds.isEmpty ? "全展" : "收起") {
                    withAnimation(.snappy) {
                        if expandedCurriculumIds.isEmpty {
                            expandedCurriculumIds = CurriculumTreeBuilder.expandableIds(nodes: nodes)
                        } else {
                            expandedCurriculumIds.removeAll()
                        }
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .onAppear {
                if !didInitCurriculumExpand {
                    didInitCurriculumExpand = true
                    expandedCurriculumIds = CurriculumTreeBuilder.defaultExpandedIds(nodes: nodes)
                }
            }

            LazyVStack(spacing: 8) {
                ForEach(entries) { entry in
                    curriculumRow(entry)
                }
            }
        }
    }

    private func curriculumRow(_ entry: CurriculumTreeEntry) -> some View {
        let filteredCourses = entry.node.courses.filter { c in
            switch curriculumFilterMode {
            case 0: return c.studyStatus != "4"
            case 1: return c.studyStatus == "4"
            default: return true
            }
        }

        return HStack(alignment: .top, spacing: 0) {
            if entry.depth > 0 {
                Canvas { context, size in
                    let slotW: CGFloat = 14
                    let strokeColor = Color.secondary.opacity(0.35)
                    for level in 0..<entry.depth {
                        let x = CGFloat(level) * slotW + slotW / 2
                        let hasRail = level < entry.ancestorHasNext.count && entry.ancestorHasNext[level]
                        if level < entry.depth - 1 {
                            if hasRail {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(strokeColor), lineWidth: 1.2)
                            }
                        } else {
                            let midY = min(24, size.height * 0.5)
                            var path = Path()
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: entry.isLastChild ? midY : size.height))
                            path.move(to: CGPoint(x: x, y: midY))
                            path.addLine(to: CGPoint(x: x + slotW / 2, y: midY))
                            context.stroke(path, with: .color(strokeColor), lineWidth: 1.2)
                        }
                    }
                }
                .frame(width: CGFloat(entry.depth) * 14)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    guard entry.isExpandable else { return }
                    withAnimation(.snappy) {
                        if entry.isExpanded { expandedCurriculumIds.remove(entry.id) }
                        else { expandedCurriculumIds.insert(entry.id) }
                    }
                } label: {
                    HStack {
                        if entry.isExpandable {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .rotationEffect(.degrees(entry.isExpanded ? 90 : 0))
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.node.name)
                                .font(.subheadline.weight(.semibold))
                            Text("已修 \(String(format: "%.1f", entry.node.earnedCredits)) / 要求 \(String(format: "%.1f", entry.node.requiredCredits)) 学分")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.node.passed ? "已修满" : "差 \(String(format: "%.1f", max(0, entry.node.requiredCredits - entry.node.earnedCredits)))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(entry.node.passed ? .green : .orange)
                    }
                }
                .buttonStyle(.plain)

                if entry.isExpanded && !filteredCourses.isEmpty {
                    Divider()
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredCourses) { course in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.courseName).font(.caption.weight(.medium))
                                    Text("\(course.courseCode) · \(String(format: "%.1f", course.credits)) 学分")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                curriculumStatusBadge(course)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .buctGlassCard(cornerRadius: 16, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        }
    }

    private func curriculumStatusBadge(_ course: CurriculumCourse) -> some View {
        let (label, color): (String, Color) = switch course.studyStatus {
        case "4": (course.grade.isEmpty ? "已通过" : course.grade, .green)
        case "1": ("在修", .accentColor)
        case "2": ("未通过", .red)
        default: ("未修", .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: - 考试 Tab

    @ViewBuilder
    private var examsContent: some View {
        let exams = environment.allExams
        if exams.isEmpty {
            Text(environment.currentProfile?.systemType == .graduateGmis ? "研究生系统暂无考试安排接口，可点击右上角 + 添加自定义考试" : "当前学期暂无考试安排")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(28)
                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(exams) { exam in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(exam.courseName)
                                .font(.headline)
                            Spacer()
                            if let start = exam.parsedStartDate() {
                                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: start)).day ?? 0
                                Text(days > 0 ? "还有 \(days) 天" : (days == 0 ? "今天" : "已结束"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(days >= 0 ? Color.accentColor : .secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }

                        if !exam.examTime.isEmpty {
                            let weekTag = ScheduleDates.examWeekDayLabel(
                                examTime: exam.examTime,
                                firstWeekMonday: environment.firstWeekMonday
                            )
                            Label(
                                weekTag.map { "\(exam.examTime) · \($0)" } ?? exam.examTime,
                                systemImage: "clock"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        let locText = [exam.location, exam.seatNumber.isEmpty ? "" : "座位 \(exam.seatNumber)", exam.examName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !locText.isEmpty {
                            Label(locText, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if exam.isCustom {
                            Button("删除自定义考试", role: .destructive) {
                                Task { await environment.deleteCustomExam(id: exam.id) }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(16)
                    .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
                }
            }
        }
    }
}

private struct AddCustomExamSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var courseName = ""
    @State private var examDate = Date()
    @State private var location = ""
    @State private var seat = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("考试科目", text: $courseName)
                DatePicker("考试时间", selection: $examDate)
                TextField("考场地点（可选）", text: $location)
                TextField("座位号（可选）", text: $seat)
            }
            .navigationTitle("添加自定义考试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let fmt = DateFormatter()
                        fmt.locale = Locale(identifier: "en_US_POSIX")
                        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
                        fmt.dateFormat = "yyyy-MM-dd(HH:mm)"
                        let exam = ExamItem(
                            id: "custom-exam-\(UUID().uuidString)",
                            courseName: courseName.trimmingCharacters(in: .whitespacesAndNewlines),
                            examTime: fmt.string(from: examDate),
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                            seatNumber: seat.trimmingCharacters(in: .whitespacesAndNewlines),
                            examName: "自定义考试",
                            isCustom: true
                        )
                        Task {
                            await environment.addCustomExam(exam)
                            dismiss()
                        }
                    }
                    .disabled(courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
