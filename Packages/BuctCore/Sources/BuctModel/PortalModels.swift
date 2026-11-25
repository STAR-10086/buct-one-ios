import Foundation

public enum PortalNewsColumn: String, Codable, Sendable, CaseIterable, Identifiable {
    case notice = "100011560"
    case activity = "100011559"
    case career = "100011558"
    case news = "100011562"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notice: return "通知公告"
        case .activity: return "活动公告"
        case .career: return "招聘信息"
        case .news: return "北化新闻"
        }
    }

    public var sourceHint: String {
        switch self {
        case .notice: return "学工办 / 资助网"
        case .activity: return "校团委"
        case .career: return "就业信息网"
        case .news: return "学校新闻网"
        }
    }
}

public struct PortalNewsArticle: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let columnId: String
    public let title: String
    public let sourceOrg: String
    public let publishTimestampMs: Int64
    public let summary: String
    public let content: String
    public let publicUrl: String
    public let isTop: Bool
    public let isHot: Bool
    public let isNewest: Bool
    public let visitCount: Int

    public init(
        id: String,
        columnId: String,
        title: String,
        sourceOrg: String,
        publishTimestampMs: Int64,
        summary: String,
        content: String,
        publicUrl: String,
        isTop: Bool = false,
        isHot: Bool = false,
        isNewest: Bool = false,
        visitCount: Int = 0
    ) {
        self.id = id
        self.columnId = columnId
        self.title = title
        self.sourceOrg = sourceOrg
        self.publishTimestampMs = publishTimestampMs
        self.summary = summary
        self.content = content
        self.publicUrl = publicUrl
        self.isTop = isTop
        self.isHot = isHot
        self.isNewest = isNewest
        self.visitCount = visitCount
    }

    public var formattedDate: String {
        guard publishTimestampMs > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(publishTimestampMs) / 1000.0)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        return fmt.string(from: date)
    }
}

public struct PortalNewsColumnPage: Codable, Sendable, Equatable {
    public let columnId: String
    public let totalCount: Int
    public var articles: [PortalNewsArticle]

    public init(columnId: String, totalCount: Int, articles: [PortalNewsArticle]) {
        self.columnId = columnId
        self.totalCount = totalCount
        self.articles = articles
    }
}

public struct PortalNewsSnapshot: Codable, Sendable, Equatable {
    public var columns: [String: PortalNewsColumnPage]

    public init(columns: [String: PortalNewsColumnPage] = [:]) {
        self.columns = columns
    }
}

public struct PortalBookItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let barcode: String
    public let borrowDate: String
    public let dueDate: String

    public init(
        id: String? = nil,
        title: String,
        barcode: String,
        borrowDate: String,
        dueDate: String
    ) {
        self.id = id ?? "\(barcode):\(title)"
        self.title = title
        self.barcode = barcode
        self.borrowDate = borrowDate
        self.dueDate = dueDate
    }

    public func daysRemaining(now: Date = Date()) -> Int? {
        let normalized = dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard normalized.count >= 10,
              let due = ScheduleDates.parseUTCDate(String(normalized.prefix(10))) else {
            return nil
        }
        var bjCal = Calendar(identifier: .gregorian)
        bjCal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let comps = bjCal.dateComponents([.year, .month, .day], from: now)
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let today = utcCal.date(from: comps) else { return nil }
        return Int(due.timeIntervalSince(today) / 86_400)
    }
}

public struct PortalLibrarySnapshot: Codable, Sendable, Equatable {
    public let totalCount: Int
    public let books: [PortalBookItem]

    public init(totalCount: Int = 0, books: [PortalBookItem] = []) {
        self.totalCount = totalCount
        self.books = books
    }
}
