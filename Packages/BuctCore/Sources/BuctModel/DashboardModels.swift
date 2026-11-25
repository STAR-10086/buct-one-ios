import Foundation

public enum DashboardModule: String, Codable, Sendable, CaseIterable, Identifiable {
    case homeworkTodo = "homework_todo"
    case theolCourse = "theol_course"
    case secondClass = "second_class"
    case campusCard = "campus_card"
    case practiceTeaching = "practice_teaching"
    case physicalFitness = "physical_fitness"
    case campusMail = "campus_mail"
    case iBuct = "i_buct"
    case jwNotice = "jw_notice"
    case emptyClassroom = "empty_classroom"
    case courseSelection = "course_selection"
    case electricity = "electricity"
    case campusNet = "campus_net"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .homeworkTodo: return "作业待办"
        case .theolCourse: return "北化在线"
        case .secondClass: return "第二课堂"
        case .campusCard: return "校园卡"
        case .practiceTeaching: return "实践教学"
        case .physicalFitness: return "体测与体育"
        case .campusMail: return "校园邮箱"
        case .iBuct: return "i北化"
        case .jwNotice: return "教务消息"
        case .emptyClassroom: return "空闲教室"
        case .courseSelection: return "选课抢课"
        case .electricity: return "宿舍电费"
        case .campusNet: return "校园网费"
        }
    }

    public var subtitle: String {
        switch self {
        case .homeworkTodo: return "待交作业与测验 DDL"
        case .theolCourse: return "课程资源与单元学习"
        case .secondClass: return "五育综测与二课活动"
        case .campusCard: return "实时余额与消费洞察"
        case .practiceTeaching: return "实验课表与讲座抢报"
        case .physicalFitness: return "体测明细与国标算分"
        case .campusMail: return "CAS 免密收件箱"
        case .iBuct: return "校历、资讯与图书在借"
        case .jwNotice: return "调停补课与教务通知"
        case .emptyClassroom: return "实时教学楼空教室"
        case .courseSelection: return "可选列表与队列抢课"
        case .electricity: return "昌平 / 东区 / 西区宿舍"
        case .campusNet: return "深澜余额与流量账单"
        }
    }

    public var systemImage: String {
        switch self {
        case .homeworkTodo: return "checklist"
        case .theolCourse: return "books.vertical.fill"
        case .secondClass: return "sparkles"
        case .campusCard: return "creditcard.fill"
        case .practiceTeaching: return "flask.fill"
        case .physicalFitness: return "figure.run"
        case .campusMail: return "envelope.fill"
        case .iBuct: return "newspaper.fill"
        case .jwNotice: return "bell.badge.fill"
        case .emptyClassroom: return "building.2.fill"
        case .courseSelection: return "bolt.badge.clock.fill"
        case .electricity: return "bolt.fill"
        case .campusNet: return "wifi"
        }
    }

    public var domainHost: String {
        switch self {
        case .homeworkTodo, .theolCourse: return "course.buct.edu.cn"
        case .secondClass: return "scs.buct.edu.cn"
        case .campusCard: return "ecard.buct.edu.cn"
        case .practiceTeaching: return "sjcx.buct.edu.cn"
        case .physicalFitness: return "tygl.buct.edu.cn"
        case .campusMail: return "mail.buct.edu.cn"
        case .iBuct: return "i.buct.edu.cn"
        case .jwNotice, .emptyClassroom, .courseSelection: return "jwglxt.buct.edu.cn"
        case .electricity: return "ele.buct.one"
        case .campusNet: return "tree.buct.edu.cn"
        }
    }

    public var umamiPath: String {
        "/module/\(rawValue)"
    }

    public var targetMilestone: String {
        switch self {
        case .emptyClassroom:
            return "M1 · 已上线"
        case .homeworkTodo, .theolCourse, .jwNotice, .iBuct, .campusMail, .electricity, .campusNet:
            return "M2 · 已上线"
        case .campusCard, .secondClass, .practiceTeaching, .physicalFitness, .courseSelection:
            return "M3 · 已上线"
        }
    }
}

public enum CardSize: String, Codable, Sendable, CaseIterable {
    case miniHalf
    case medium1x1
    case large2x1

    /// 基于 4 列栅格的列跨度：MINI = 1, MEDIUM = 2, LARGE = 4
    public var colSpan: Int {
        switch self {
        case .miniHalf: return 1
        case .medium1x1: return 2
        case .large2x1: return 4
        }
    }

    /// 基于 76pt 行单位的行跨度：MINI = 1, MEDIUM = 2, LARGE = 2
    public var rowSpan: Int {
        switch self {
        case .miniHalf: return 1
        case .medium1x1: return 2
        case .large2x1: return 2
        }
    }

    public var next: CardSize {
        switch self {
        case .large2x1: return .medium1x1
        case .medium1x1: return .miniHalf
        case .miniHalf: return .large2x1
        }
    }

    public var label: String {
        switch self {
        case .large2x1: return "2×1"
        case .medium1x1: return "1×1"
        case .miniHalf: return "0.5×0.5"
        }
    }
}

public struct DashboardCardSlot: Codable, Sendable, Equatable, Identifiable {
    public let module: DashboardModule
    public var size: CardSize
    public var col: Int
    public var row: Int

    public var id: String { module.rawValue }

    public init(module: DashboardModule, size: CardSize, col: Int, row: Int) {
        self.module = module
        self.size = size
        self.col = col
        self.row = row
    }
}

public struct DashboardLayout: Codable, Sendable, Equatable {
    public static let totalCols = 4
    public var slots: [DashboardCardSlot]

    public init(slots: [DashboardCardSlot]) {
        self.slots = slots
    }

    public var hiddenModules: [DashboardModule] {
        let visible = Set(slots.map(\.module))
        return DashboardModule.allCases.filter { !visible.contains($0) }
    }

    public static let `default`: DashboardLayout = DashboardLayout(slots: [
        DashboardCardSlot(module: .homeworkTodo, size: .large2x1, col: 0, row: 0),
        DashboardCardSlot(module: .secondClass, size: .medium1x1, col: 0, row: 2),
        DashboardCardSlot(module: .campusCard, size: .medium1x1, col: 2, row: 2),
        DashboardCardSlot(module: .practiceTeaching, size: .large2x1, col: 0, row: 4),
        DashboardCardSlot(module: .emptyClassroom, size: .medium1x1, col: 0, row: 6),
        DashboardCardSlot(module: .courseSelection, size: .medium1x1, col: 2, row: 6),
        DashboardCardSlot(module: .physicalFitness, size: .medium1x1, col: 0, row: 8),
        DashboardCardSlot(module: .campusMail, size: .medium1x1, col: 2, row: 8),
        DashboardCardSlot(module: .iBuct, size: .medium1x1, col: 0, row: 10),
        DashboardCardSlot(module: .jwNotice, size: .medium1x1, col: 2, row: 10),
        DashboardCardSlot(module: .electricity, size: .medium1x1, col: 0, row: 12),
        DashboardCardSlot(module: .campusNet, size: .medium1x1, col: 2, row: 12),
        DashboardCardSlot(module: .theolCourse, size: .large2x1, col: 0, row: 14)
    ])

    /// 寻找可容纳指定尺寸的第一个空位并追加模块
    public mutating func addModule(_ module: DashboardModule, size: CardSize = .medium1x1) {
        guard !slots.contains(where: { $0.module == module }) else { return }
        let placement = Self.firstAvailablePosition(for: size, against: slots)
        slots.append(DashboardCardSlot(module: module, size: size, col: placement.col, row: placement.row))
    }

    /// 切换指定卡片尺寸；若原位或边界冲突则自动执行碰撞重排
    public mutating func cycleSize(for module: DashboardModule) {
        guard let index = slots.firstIndex(where: { $0.module == module }) else { return }
        let nextSize = slots[index].size.next
        let current = slots[index]
        let clampedCol = min(max(0, current.col), Self.totalCols - nextSize.colSpan)
        slots[index].size = nextSize
        slots[index].col = clampedCol
        resolvePlacement(moving: module, toCol: clampedCol, row: current.row)
    }

    public mutating func removeModule(_ module: DashboardModule) {
        slots.removeAll { $0.module == module }
    }

    /// 对应 Android resolveGridPlacement：支持单卡可逆互换与碰撞向下顺移
    public mutating func resolvePlacement(moving module: DashboardModule, toCol: Int, row toRow: Int) {
        guard let activeIndex = slots.firstIndex(where: { $0.module == module }) else { return }
        let prevSlot = slots[activeIndex]
        let clampedCol = min(max(0, toCol), Self.totalCols - prevSlot.size.colSpan)
        let clampedRow = max(0, toRow)

        var candidate = prevSlot
        candidate.col = clampedCol
        candidate.row = clampedRow
        slots[activeIndex] = candidate

        let others = slots.enumerated().filter { $0.offset != activeIndex }
        let colliding = others.filter { Self.overlaps(candidate, $0.element) }

        if colliding.isEmpty {
            return
        }

        // 若恰好仅与 1 张卡片碰撞且该卡片可无冲突放回原位置，则执行可逆互换
        if colliding.count == 1 {
            let targetIndex = colliding[0].offset
            var swappedTarget = colliding[0].element
            let swappedCol = min(max(0, prevSlot.col), Self.totalCols - swappedTarget.size.colSpan)
            swappedTarget.col = swappedCol
            swappedTarget.row = prevSlot.row

            let thirdParties = slots.enumerated()
                .filter { $0.offset != activeIndex && $0.offset != targetIndex }
                .map(\.element)
            if !Self.overlaps(candidate, swappedTarget) &&
                Self.canPlace(size: swappedTarget.size, atCol: swappedTarget.col, row: swappedTarget.row, against: thirdParties) {
                slots[targetIndex] = swappedTarget
                return
            }
        }

        // 否则仅将发生碰撞的卡片向下顺移，不扰动无关卡片
        var settled: [DashboardCardSlot] = [candidate]
        let remainingIndices = others.map(\.offset).sorted {
            let a = slots[$0]
            let b = slots[$1]
            return a.row != b.row ? a.row < b.row : a.col < b.col
        }

        for idx in remainingIndices {
            var item = slots[idx]
            var guardCount = 0
            while settled.contains(where: { Self.overlaps(item, $0) }) && guardCount < 200 {
                item.row += 1
                guardCount += 1
            }
            slots[idx] = item
            settled.append(item)
        }
    }

    private static func firstAvailablePosition(
        for size: CardSize,
        against existing: [DashboardCardSlot]
    ) -> (col: Int, row: Int) {
        let maxRow = (existing.map { $0.row + $0.size.rowSpan }.max() ?? 0) + 4
        for row in 0...maxRow {
            for col in 0...(totalCols - size.colSpan) {
                if canPlace(size: size, atCol: col, row: row, against: existing) {
                    return (col, row)
                }
            }
        }
        return (0, maxRow)
    }

    public static func canPlace(
        size: CardSize,
        atCol col: Int,
        row: Int,
        against existing: [DashboardCardSlot]
    ) -> Bool {
        guard col >= 0, row >= 0, col + size.colSpan <= totalCols else { return false }
        let probe = DashboardCardSlot(module: .homeworkTodo, size: size, col: col, row: row)
        return !existing.contains { overlaps(probe, $0) }
    }

    public static func overlaps(_ a: DashboardCardSlot, _ b: DashboardCardSlot) -> Bool {
        let overlapX = a.col < b.col + b.size.colSpan && a.col + a.size.colSpan > b.col
        let overlapY = a.row < b.row + b.size.rowSpan && a.row + a.size.rowSpan > b.row
        return overlapX && overlapY
    }
}

public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public struct AppearanceConfig: Codable, Sendable, Equatable {
    public var themeMode: ThemeMode
    public var liquidGlassEnabled: Bool
    public var umamiEnabled: Bool

    public init(
        themeMode: ThemeMode = .system,
        liquidGlassEnabled: Bool = true,
        umamiEnabled: Bool = true
    ) {
        self.themeMode = themeMode
        self.liquidGlassEnabled = liquidGlassEnabled
        self.umamiEnabled = umamiEnabled
    }
}
