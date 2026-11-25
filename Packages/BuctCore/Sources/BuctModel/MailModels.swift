import Foundation

public struct MailAccountInfo: Codable, Sendable, Equatable {
    public let email: String
    public let displayName: String
    public let orgName: String

    public init(email: String = "", displayName: String = "", orgName: String = "") {
        self.email = email
        self.displayName = displayName
        self.orgName = orgName
    }
}

public struct MailFolder: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let totalCount: Int
    public let unreadCount: Int
    public let isSystem: Bool

    public init(id: Int, name: String, totalCount: Int = 0, unreadCount: Int = 0, isSystem: Bool = false) {
        self.id = id
        self.name = name
        self.totalCount = totalCount
        self.unreadCount = unreadCount
        self.isSystem = isSystem
    }

    public static let inboxId = 1
    public static let draftsId = 2
    public static let sentId = 3
    public static let trashId = 4
    public static let spamId = 5
}

public struct MailAttachment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { partId }
    public let partId: String
    public let filename: String
    public let contentType: String
    public let sizeBytes: Int64
    public let isInlined: Bool
    public let contentId: String

    public init(
        partId: String,
        filename: String,
        contentType: String = "application/octet-stream",
        sizeBytes: Int64 = 0,
        isInlined: Bool = false,
        contentId: String = ""
    ) {
        self.partId = partId
        self.filename = filename
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.isInlined = isInlined
        self.contentId = contentId
    }
}

public struct MailMessageSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var folderId: Int
    public let threadId: String
    public let subject: String
    public let fromName: String
    public let fromAddress: String
    public let to: [String]
    public let summary: String
    public let sentAt: String
    public let receivedAt: String
    public let sizeBytes: Int64
    public var isRead: Bool
    public let isFlagged: Bool
    public let hasAttachments: Bool
    public let attachments: [MailAttachment]

    public init(
        id: String,
        folderId: Int,
        threadId: String = "",
        subject: String,
        fromName: String,
        fromAddress: String,
        to: [String] = [],
        summary: String = "",
        sentAt: String = "",
        receivedAt: String = "",
        sizeBytes: Int64 = 0,
        isRead: Bool = false,
        isFlagged: Bool = false,
        hasAttachments: Bool = false,
        attachments: [MailAttachment] = []
    ) {
        self.id = id
        self.folderId = folderId
        self.threadId = threadId
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.to = to
        self.summary = summary
        self.sentAt = sentAt
        self.receivedAt = receivedAt
        self.sizeBytes = sizeBytes
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.hasAttachments = hasAttachments
        self.attachments = attachments
    }
}

public struct MailMessageDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let folderId: Int
    public let subject: String
    public let fromName: String
    public let fromAddress: String
    public let to: [String]
    public let sentAt: String
    public let htmlBody: String
    public let plainText: String
    public let attachments: [MailAttachment]
    public let fetchedAt: Int64

    public init(
        id: String,
        folderId: Int,
        subject: String,
        fromName: String,
        fromAddress: String,
        to: [String] = [],
        sentAt: String = "",
        htmlBody: String = "",
        plainText: String = "",
        attachments: [MailAttachment] = [],
        fetchedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.folderId = folderId
        self.subject = subject
        self.fromName = fromName
        self.fromAddress = fromAddress
        self.to = to
        self.sentAt = sentAt
        self.htmlBody = htmlBody
        self.plainText = plainText
        self.attachments = attachments
        self.fetchedAt = fetchedAt
    }
}

public struct MailSnapshot: Codable, Sendable, Equatable {
    public var account: MailAccountInfo
    public var folders: [MailFolder]
    public var inboxTotal: Int
    public var inboxMessages: [MailMessageSummary]

    public init(
        account: MailAccountInfo = MailAccountInfo(),
        folders: [MailFolder] = [],
        inboxTotal: Int = 0,
        inboxMessages: [MailMessageSummary] = []
    ) {
        self.account = account
        self.folders = folders
        self.inboxTotal = inboxTotal
        self.inboxMessages = inboxMessages
    }

    public var inboxUnreadCount: Int {
        if let inbox = folders.first(where: { $0.id == MailFolder.inboxId }) {
            return inbox.unreadCount
        }
        return inboxMessages.filter { !$0.isRead }.count
    }
}

public struct MailDownloadedFile: Codable, Sendable, Equatable {
    public let filePath: String
    public let fileName: String
    public let mimeType: String
    public let sizeBytes: Int64

    public init(filePath: String, fileName: String, mimeType: String, sizeBytes: Int64) {
        self.filePath = filePath
        self.fileName = fileName
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
    }
}
