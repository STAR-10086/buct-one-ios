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
            return "M1 · 核心学业"
        case .homeworkTodo, .theolCourse, .jwNotice, .iBuct, .campusMail, .electricity, .campusNet:
            return "M2 · 在线教学与高频域"
        case .campusCard, .secondClass, .practiceTeaching, .physicalFitness, .courseSelection:
            return "M3 · 校内全域与选课"
        }
    }
}

public enum CardSize: String, Codable, Sendable, CaseIterable {
    case large2x1
    case medium1x1
    case miniHalf

    /// 以 0.5 列为单位（4 大列 = 8 个半格单位）
    public var colUnits: Int {
        switch self {
        case .large2x1: return 4
        case .medium1x1: return 2
        case .miniHalf: return 1
        }
    }

    /// 以 0.5 行为单位（1 行 = 2 个半格单位）
    public var rowUnits: Int {
        switch self {
        case .large2x1: return 2
        case .medium1x1: return 2
        case .miniHalf: return 1
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
    public var colUnit: Int
    public var rowUnit: Int

    public var id: String { module.rawValue }

    public init(module: DashboardModule, size: CardSize, colUnit: Int, rowUnit: Int) {
        self.module = module
        self.size = size
        self.colUnit = colUnit
        self.rowUnit = rowUnit
    }
}

public struct DashboardLayout: Codable, Sendable, Equatable {
    public static let totalColUnits = 8
    public var slots: [DashboardCardSlot]

    public init(slots: [DashboardCardSlot]) {
        self.slots = slots
    }

    public var hiddenModules: [DashboardModule] {
        let visible = Set(slots.map(\.module))
        return DashboardModule.allCases.filter { !visible.contains($0) }
    }

    public static let `default`: DashboardLayout = DashboardLayout(slots: [
        DashboardCardSlot(module: .homeworkTodo, size: .large2x1, colUnit: 0, rowUnit: 0),
        DashboardCardSlot(module: .theolCourse, size: .large2x1, colUnit: 4, rowUnit: 0),
        DashboardCardSlot(module: .campusCard, size: .medium1x1, colUnit: 0, rowUnit: 2),
        DashboardCardSlot(module: .electricity, size: .medium1x1, colUnit: 2, rowUnit: 2),
        DashboardCardSlot(module: .campusNet, size: .medium1x1, colUnit: 4, rowUnit: 2),
        DashboardCardSlot(module: .iBuct, size: .medium1x1, colUnit: 6, rowUnit: 2),
        DashboardCardSlot(module: .jwNotice, size: .medium1x1, colUnit: 0, rowUnit: 4),
        DashboardCardSlot(module: .campusMail, size: .medium1x1, colUnit: 2, rowUnit: 4),
        DashboardCardSlot(module: .secondClass, size: .medium1x1, colUnit: 4, rowUnit: 4),
        DashboardCardSlot(module: .practiceTeaching, size: .medium1x1, colUnit: 6, rowUnit: 4),
        DashboardCardSlot(module: .physicalFitness, size: .medium1x1, colUnit: 0, rowUnit: 6),
        DashboardCardSlot(module: .emptyClassroom, size: .medium1x1, colUnit: 2, rowUnit: 6),
        DashboardCardSlot(module: .courseSelection, size: .large2x1, colUnit: 4, rowUnit: 6)
    ])

    /// 寻找可容纳指定尺寸的第一个空位并追加模块
    public mutating func addModule(_ module: DashboardModule, size: CardSize = .medium1x1) {
        guard !slots.contains(where: { $0.module == module }) else { return }
        let placement = firstAvailablePosition(for: size)
        slots.append(DashboardCardSlot(module: module, size: size, colUnit: placement.colUnit, rowUnit: placement.rowUnit))
    }

    /// 切换指定卡片尺寸；若原位放不下则自动就近顺移
    public mutating func cycleSize(for module: DashboardModule) {
        guard let index = slots.firstIndex(where: { $0.module == module }) else { return }
        let nextSize = slots[index].size.next
        let current = slots[index]
        let others = slots.enumerated().filter { $0.offset != index }.map(\.element)
        if Self.canPlace(size: nextSize, atCol: current.colUnit, row: current.rowUnit, against: others) {
            slots[index].size = nextSize
        } else {
            let fallback = Self.firstAvailablePosition(for: nextSize, against: others)
            slots[index] = DashboardCardSlot(
                module: module,
                size: nextSize,
                colUnit: fallback.colUnit,
                rowUnit: fallback.rowUnit
            )
        }
    }

    public mutating func removeModule(_ module: DashboardModule) {
        slots.removeAll { $0.module == module }
    }

    private func firstAvailablePosition(for size: CardSize) -> (colUnit: Int, rowUnit: Int) {
        Self.firstAvailablePosition(for: size, against: slots)
    }

    private static func firstAvailablePosition(
        for size: CardSize,
        against existing: [DashboardCardSlot]
    ) -> (colUnit: Int, rowUnit: Int) {
        let maxRow = (existing.map { $0.rowUnit + $0.size.rowUnits }.max() ?? 0) + 4
        let stepCol = size == .miniHalf ? 1 : 2
        let stepRow = size == .miniHalf ? 1 : 2
        for row in stride(from: 0, through: maxRow, by: stepRow) {
            for col in stride(from: 0, through: totalColUnits - size.colUnits, by: stepCol) {
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
        guard col >= 0, row >= 0, col + size.colUnits <= totalColUnits else { return false }
        for other in existing {
            let overlapX = col < other.colUnit + other.size.colUnits && col + size.colUnits > other.colUnit
            let overlapY = row < other.rowUnit + other.size.rowUnits && row + size.rowUnits > other.rowUnit
            if overlapX && overlapY {
                return false
            }
        }
        return true
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
