import BuctModel
import SwiftUI

struct WorkbenchView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isEditing = false
    @State private var draftLayout: DashboardLayout = .default
    @State private var undoStack: [DashboardLayout] = []
    @State private var selectedModule: DashboardModule?

    @State private var draggingModule: DashboardModule?
    @State private var dragOffset: CGSize = .zero

    private var activeLayout: DashboardLayout {
        isEditing ? draftLayout : environment.dashboardLayout
    }

    private var maxRowEnd: Int {
        activeLayout.slots.map { $0.row + $0.size.rowSpan }.max() ?? 4
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BuctBackdropBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if isEditing {
                            editToolbar
                        } else {
                            headerBanner
                        }

                        GeometryReader { geo in
                            let cellW = WorkbenchGridLayout.cellWidth(for: geo.size.width)
                            let stepX = cellW + WorkbenchGridLayout.spacing
                            let stepY = WorkbenchGridLayout.cellHeight + WorkbenchGridLayout.spacing
                            let gridRows = isEditing ? max(maxRowEnd + 2, 8) : maxRowEnd

                            ZStack(alignment: .topLeading) {
                                if isEditing {
                                    gridSkeletonCanvas(rows: gridRows, cellW: cellW)
                                }

                                // 关键：不将所有卡片包裹在 GlassEffectContainer 内，避免 iOS 26 液态玻璃邻近融合导致卡片粘连
                                WorkbenchGridLayout(minRows: gridRows) {
                                    ForEach(activeLayout.slots) { slot in
                                        cardSlotView(slot: slot, stepX: stepX, stepY: stepY)
                                            .workbenchSlot(slot)
                                    }
                                }
                            }
                        }
                        .frame(
                            height: {
                                let rows = isEditing ? max(maxRowEnd + 2, 8) : maxRowEnd
                                return CGFloat(rows) * WorkbenchGridLayout.cellHeight
                                    + CGFloat(max(0, rows - 1)) * WorkbenchGridLayout.spacing
                            }()
                        )

                        if isEditing && !draftLayout.hiddenModules.isEmpty {
                            hiddenModulesDock
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("北化一站")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !isEditing {
                        Button("自定义") {
                            draftLayout = environment.dashboardLayout
                            undoStack.removeAll()
                            withAnimation(.snappy) {
                                isEditing = true
                            }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .navigationDestination(item: $selectedModule) { module in
                switch module {
                case .emptyClassroom:
                    EmptyClassroomView()
                case .theolCourse:
                    TheolCourseView()
                case .jwNotice:
                    JwNoticeView()
                case .iBuct:
                    IBuctPortalView()
                case .campusMail:
                    CampusMailView()
                case .electricity:
                    ElectricityView()
                case .campusNet:
                    CampusNetView()
                case .campusCard:
                    CampusCardView()
                case .secondClass:
                    SecondClassView()
                case .practiceTeaching:
                    PracticeTeachingView()
                case .physicalFitness:
                    PhysicalFitnessView()
                case .courseSelection:
                    CourseSelectionView()
                default:
                    ModulePlaceholderView(module: module)
                }
            }
        }
    }

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(greetingTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if environment.currentProfile == nil {
                    Button("登录") {
                        environment.showLoginSheet = true
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                } else {
                    Button {
                        Task { await environment.refreshAllData(userInitiated: true) }
                    } label: {
                        if environment.isSyncingSchedule || environment.isSyncingGrades {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            }

            if environment.currentProfile != nil {
                HStack(spacing: 8) {
                    summaryChip(
                        icon: "calendar",
                        text: "今日 \(todayCoursesCount) 节课"
                    ) {
                        environment.selectedTab = .schedule
                    }
                    summaryChip(
                        icon: "flag.fill",
                        text: "待考 \(environment.allExams.count) 门"
                    ) {
                        environment.selectedTab = .grades
                    }
                }
            }
        }
        .padding(14)
        .buctGlassCard(cornerRadius: 22, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private func summaryChip(icon: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(text)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var editToolbar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let prev = undoStack.popLast() {
                        withAnimation(.snappy) {
                            draftLayout = prev
                        }
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.glass)
                .disabled(undoStack.isEmpty)

                Button {
                    pushUndo()
                    withAnimation(.snappy) {
                        draftLayout = .default
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)

                Spacer()

                Button("取消") {
                    withAnimation(.snappy) {
                        isEditing = false
                        undoStack.removeAll()
                    }
                }
                .buttonStyle(.glass)

                Button("保存") {
                    environment.saveDashboardLayout(draftLayout)
                    withAnimation(.snappy) {
                        isEditing = false
                        undoStack.removeAll()
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private func gridSkeletonCanvas(rows: Int, cellW: CGFloat) -> some View {
        Canvas { context, _ in
            let gap = WorkbenchGridLayout.spacing
            let cellH = WorkbenchGridLayout.cellHeight
            for r in 0..<rows {
                for c in 0..<DashboardLayout.totalCols {
                    let rect = CGRect(
                        x: CGFloat(c) * (cellW + gap),
                        y: CGFloat(r) * (cellH + gap),
                        width: cellW,
                        height: cellH
                    )
                    let path = RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
                    context.stroke(
                        path,
                        with: .color(Color.secondary.opacity(0.22)),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func cardSlotView(slot: DashboardCardSlot, stepX: CGFloat, stepY: CGFloat) -> some View {
        let isDragging = draggingModule == slot.module
        let cornerRadius: CGFloat = slot.size == .miniHalf ? 20 : 26

        ZStack(alignment: .topTrailing) {
            Button {
                if !isEditing {
                    environment.trackVisit(path: slot.module.umamiPath, title: slot.module.title)
                    if slot.module == .homeworkTodo {
                        environment.selectedTab = .homework
                    } else {
                        selectedModule = slot.module
                    }
                }
            } label: {
                cardBody(for: slot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .buctGlassCard(
                cornerRadius: cornerRadius,
                interactive: !isEditing,
                enabled: environment.appearance.liquidGlassEnabled
            )
            .overlay {
                if isDragging {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                }
            }

            if isEditing {
                HStack {
                    Button {
                        pushUndo()
                        withAnimation(.snappy) {
                            draftLayout.removeModule(slot.module)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.secondary.opacity(0.85))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        pushUndo()
                        withAnimation(.snappy) {
                            draftLayout.cycleSize(for: slot.module)
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
            }
        }
        .scaleEffect(isDragging ? 1.04 : 1.0)
        .offset(isDragging ? dragOffset : .zero)
        .zIndex(isDragging ? 30 : 0)
        .gesture(
            LongPressGesture(minimumDuration: 0.25)
                .sequenced(before: DragGesture(minimumDistance: 2))
                .onChanged { value in
                    guard isEditing else { return }
                    switch value {
                    case .second(true, let drag?):
                        if draggingModule == nil {
                            pushUndo()
                            draggingModule = slot.module
                        }
                        dragOffset = drag.translation
                    default:
                        break
                    }
                }
                .onEnded { value in
                    guard isEditing else { return }
                    if case .second(true, let drag?) = value {
                        let dCol = Int((drag.translation.width / stepX).rounded())
                        let dRow = Int((drag.translation.height / stepY).rounded())
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            draftLayout.resolvePlacement(
                                moving: slot.module,
                                toCol: slot.col + dCol,
                                row: slot.row + dRow
                            )
                        }
                    }
                    draggingModule = nil
                    dragOffset = .zero
                }
        )
    }

    @ViewBuilder
    private func cardBody(for slot: DashboardCardSlot) -> some View {
        switch slot.size {
        case .miniHalf:
            VStack(spacing: 4) {
                Image(systemName: slot.module.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                Text(slot.module.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(6)

        case .medium1x1:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(slot.module.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: slot.module.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                }
                Spacer(minLength: 0)
                Text(slot.module.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(isEditing ? "尺寸 \(slot.size.label)" : moduleStatusText(slot.module))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(slot.module == .emptyClassroom ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            .padding(13)

        case .large2x1:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: slot.module.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    Text(slot.module.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(isEditing ? slot.size.label : moduleStatusText(slot.module))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(slot.module == .emptyClassroom ? Color.accentColor : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                Spacer(minLength: 0)
                Text(slot.module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("域名：\(slot.module.domainHost)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(15)
        }
    }

    private var hiddenModulesDock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("点击加回工作台")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(draftLayout.hiddenModules) { module in
                        Button {
                            pushUndo()
                            withAnimation(.snappy) {
                                draftLayout.addModule(module)
                            }
                        } label: {
                            Label(module.title, systemImage: "plus.circle.fill")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .padding(12)
        .buctGlassCard(cornerRadius: 18, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let greet: String
        switch hour {
        case 5..<12: greet = "早上好"
        case 12..<14: greet = "中午好"
        case 14..<18: greet = "下午好"
        default: greet = "晚上好"
        }
        if let profile = environment.currentProfile {
            return "\(greet)，\(profile.studentName)"
        }
        return "\(greet)，北化人"
    }

    private var statusSubtitle: String {
        if let profile = environment.currentProfile {
            let weekStr = environment.currentTeachingWeek.map { "第 \($0) 周" } ?? "假期/非教学周"
            return "\(profile.systemType.shortBadge) · \(environment.selectedTerm.shortLabel) · \(weekStr)"
        }
        return "点击右侧「登录」同步课表、成绩与官方校历"
    }

    private var todayCoursesCount: Int {
        let dow = ScheduleDates.todayDayOfWeek()
        let week = environment.currentTeachingWeek
        return environment.allScheduleCourses.filter { course in
            course.dayOfWeek == dow && (week == nil || course.weeks.contains(week!))
        }.count
    }

    private func moduleStatusText(_ module: DashboardModule) -> String {
        switch module {
        case .emptyClassroom:
            return "可用"
        case .homeworkTodo:
            let count = environment.visiblePendingTodoCount
            return environment.theolSlice.provenance.refreshState == .never && count == 0 ? "未同步" : "待办 \(count) 项"
        case .theolCourse:
            let count = environment.theolSlice.data?.courses.count ?? 0
            return count > 0 ? "\(count) 门课程" : "在线课程"
        case .jwNotice:
            let unread = environment.jwNoticeSlice.data?.unreadCount ?? 0
            return unread > 0 ? "未读 \(unread) 条" : (environment.jwNoticeSlice.provenance.refreshState == .never ? "未同步" : "已同步")
        case .iBuct:
            let books = environment.portalLibrarySlice.data?.books.count ?? 0
            if books > 0 { return "在借 \(books) 本" }
            if let week = environment.currentTeachingWeek { return "第 \(week) 周" }
            return "校历与资讯"
        case .campusMail:
            let unread = environment.mailSlice.data?.inboxUnreadCount ?? 0
            if unread > 0 { return "未读 \(unread) 封" }
            return environment.mailSlice.provenance.refreshState == .never ? "未同步" : "已同步"
        case .electricity:
            if let first = environment.electricitySlice.data?.readings.first {
                return first.balanceText
            }
            return (environment.electricitySlice.data?.targets.isEmpty ?? true) ? "未绑定宿舍" : "未查询"
        case .campusNet:
            if let snap = environment.campusNetSlice.data {
                if let bal = snap.userBalance ?? snap.walletBalance {
                    return String(format: "¥%.1f · %@", bal, snap.isOnline ? "在线" : "离线")
                }
                return snap.isOnline ? "在线" : "离线"
            }
            return "未同步"
        case .campusCard:
            if let acc = environment.cardSlice.data?.account, !acc.idSerial.isEmpty {
                return "¥\(acc.balanceYuanText)"
            }
            return environment.hasCardCredential ? "未同步" : "需独立登录"
        case .secondClass:
            if let top = environment.scsSlice.data?.terms.first {
                return String(format: "%.1f 分", top.totalScore)
            }
            return "未同步"
        case .practiceTeaching:
            if let snap = environment.sjcxSlice.data {
                let pending = snap.reports.filter { !$0.isSubmitted }.count
                return pending > 0 ? "待交 \(pending) 份" : String(format: "%.1f 学分", snap.totalCredit)
            }
            return "未同步"
        case .physicalFitness:
            if let latest = environment.tyglSlice.data?.fitnessRecords.first, !latest.totalScore.isEmpty {
                return "\(latest.totalScore) · \(latest.level)"
            }
            return "体测与算分"
        case .courseSelection:
            if !environment.courseWishlist.isEmpty {
                return "志愿 \(environment.courseWishlist.count) 门"
            }
            if let snap = environment.courseSelectionSlice.data {
                return snap.isOpen ? "已选 \(snap.selectedCourses.count) 门" : "非选课期"
            }
            return "选课与志愿"
        default:
            return module.targetMilestone
        }
    }

    private func pushUndo() {
        undoStack.append(draftLayout)
        if undoStack.count > 30 {
            undoStack.removeFirst()
        }
    }
}

struct ModulePlaceholderView: View {
    @Environment(AppEnvironment.self) private var environment
    let module: DashboardModule

    var body: some View {
        ZStack {
            BuctBackdropBackground()

            VStack(spacing: 16) {
                Image(systemName: module.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .padding(20)
                    .buctGlassCard(cornerRadius: 24, interactive: false, enabled: environment.appearance.liquidGlassEnabled)

                Text(module.title)
                    .font(.title2.weight(.bold))

                Text(module.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("接入域名", value: module.domainHost)
                    LabeledContent("当前状态", value: RefreshState.never.displayLabel)
                    LabeledContent("计划阶段", value: module.targetMilestone)
                }
                .font(.footnote)
                .padding(16)
                .buctGlassCard(cornerRadius: 20, interactive: false, enabled: environment.appearance.liquidGlassEnabled)
            }
            .padding(20)
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
