import Foundation

public enum JwReminderCategory: String, Codable, Sendable, CaseIterable {
    case reschedule
    case makeup
    case cancel
    case exam
    case other

    public var displayName: String {
        switch self {
        case .reschedule: return "调课"
        case .makeup: return "补课"
        case .cancel: return "停课"
        case .exam: return "考试"
        case .other: return "提醒"
        }
    }

    public var systemImage: String {
        switch self {
        case .reschedule: return "arrow.left.arrow.right.circle.fill"
        case .makeup: return "plus.circle.fill"
        case .cancel: return "xmark.octagon.fill"
        case .exam: return "pencil.and.list.clipboard"
        case .other: return "bell.fill"
        }
    }
}

public struct JwReminderItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let content: String
    public let createdAt: String
    public var isRead: Bool
    public let category: JwReminderCategory

    public init(
        id: String,
        title: String,
        content: String,
        createdAt: String,
        isRead: Bool,
        category: JwReminderCategory
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.isRead = isRead
        self.category = category
    }
}

public struct JwAnnouncementItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let publisher: String
    public let publishedAt: String
    public let isPinned: Bool
    public var isRead: Bool
    public let externalUrl: String
    public let inlineHtml: String

    public init(
        id: String,
        title: String,
        publisher: String,
        publishedAt: String,
        isPinned: Bool,
        isRead: Bool,
        externalUrl: String = "",
        inlineHtml: String = ""
    ) {
        self.id = id
        self.title = title
        self.publisher = publisher
        self.publishedAt = publishedAt
        self.isPinned = isPinned
        self.isRead = isRead
        self.externalUrl = externalUrl
        self.inlineHtml = inlineHtml
    }
}

public struct JwAnnouncementDetail: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let publisher: String
    public let publishedAt: String
    public let viewCount: String
    public let bodyHtml: String
    public let plainText: String

    public init(
        id: String,
        title: String,
        publisher: String,
        publishedAt: String,
        viewCount: String,
        bodyHtml: String,
        plainText: String
    ) {
        self.id = id
        self.title = title
        self.publisher = publisher
        self.publishedAt = publishedAt
        self.viewCount = viewCount
        self.bodyHtml = bodyHtml
        self.plainText = plainText
    }
}

public struct JwNoticeSnapshot: Codable, Sendable, Equatable {
    public var reminders: [JwReminderItem]
    public var reminderTotal: Int
    public var announcements: [JwAnnouncementItem]
    public var announcementTotal: Int

    public init(
        reminders: [JwReminderItem] = [],
        reminderTotal: Int = 0,
        announcements: [JwAnnouncementItem] = [],
        announcementTotal: Int = 0
    ) {
        self.reminders = reminders
        self.reminderTotal = reminderTotal
        self.announcements = announcements
        self.announcementTotal = announcementTotal
    }

    public var unreadCount: Int {
        reminders.filter { !$0.isRead }.count + announcements.filter { !$0.isRead }.count
    }
}
