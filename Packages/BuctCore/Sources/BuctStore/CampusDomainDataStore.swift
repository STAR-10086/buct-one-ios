import BuctModel
import Foundation

public struct JwNoticeReadIds: Codable, Sendable, Equatable {
    public var reminderIds: [String]
    public var announcementIds: [String]

    public init(reminderIds: [String] = [], announcementIds: [String] = []) {
        self.reminderIds = reminderIds
        self.announcementIds = announcementIds
    }
}

public actor CampusDomainDataStore {
    private let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let maxReadIds = 500
    private static let maxCachedDetails = 80
    private static let maxAttachmentCacheBytes: Int64 = 120 * 1024 * 1024
    private static let trimTargetBytes: Int64 = 96 * 1024 * 1024

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AppContainerResolver.resolveRootDirectory().url
    }

    // MARK: - 教务消息

    public func jwNoticeStore(accountKey: String) -> DomainSliceStore<JwNoticeSnapshot> {
        DomainSliceStore(
            source: "jwglxt.buct.edu.cn",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("jw_notice_snapshot.json")
        )
    }

    public func loadJwNoticeReadIds(accountKey: String) -> JwNoticeReadIds {
        loadJSON(JwNoticeReadIds.self, url: accountDirectory(accountKey).appendingPathComponent("jw_notice_read_ids.json"))
            ?? JwNoticeReadIds()
    }

    public func saveJwNoticeReadIds(_ ids: JwNoticeReadIds, accountKey: String) {
        var capped = ids
        if capped.reminderIds.count > Self.maxReadIds {
            capped.reminderIds = Array(capped.reminderIds.suffix(Self.maxReadIds))
        }
        if capped.announcementIds.count > Self.maxReadIds {
            capped.announcementIds = Array(capped.announcementIds.suffix(Self.maxReadIds))
        }
        saveJSON(capped, url: accountDirectory(accountKey).appendingPathComponent("jw_notice_read_ids.json"))
    }

    // MARK: - i北化资讯与图书馆

    public func portalNewsStore(accountKey: String) -> DomainSliceStore<PortalNewsSnapshot> {
        DomainSliceStore(
            source: "mnews.buct.edu.cn",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("portal_news_snapshot.json")
        )
    }

    public func portalLibraryStore(accountKey: String) -> DomainSliceStore<PortalLibrarySnapshot> {
        DomainSliceStore(
            source: "i.buct.edu.cn",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("portal_library_snapshot.json")
        )
    }

    // MARK: - 北化在线 (THEOL)

    public func theolSnapshotStore(accountKey: String) -> DomainSliceStore<TheolSnapshot> {
        DomainSliceStore(
            source: "theol.homework",
            parserVersion: 7,
            fileURL: accountDirectory(accountKey).appendingPathComponent("theol_snapshot.json")
        )
    }

    public func loadTheolHomeworkDetails(accountKey: String) -> [String: TheolHomeworkDetail] {
        loadJSON([String: TheolHomeworkDetail].self, url: accountDirectory(accountKey).appendingPathComponent("theol_hw_details.json"))
            ?? [:]
    }

    public func saveTheolHomeworkDetails(_ details: [String: TheolHomeworkDetail], accountKey: String) {
        let capped = Dictionary(
            uniqueKeysWithValues: details.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(Self.maxCachedDetails).map { ($0.key, $0.value) }
        )
        saveJSON(capped, url: accountDirectory(accountKey).appendingPathComponent("theol_hw_details.json"))
    }

    public func loadTheolTestDetails(accountKey: String) -> [String: TheolTestDetail] {
        loadJSON([String: TheolTestDetail].self, url: accountDirectory(accountKey).appendingPathComponent("theol_test_details.json"))
            ?? [:]
    }

    public func saveTheolTestDetails(_ details: [String: TheolTestDetail], accountKey: String) {
        let capped = Dictionary(
            uniqueKeysWithValues: details.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(Self.maxCachedDetails).map { ($0.key, $0.value) }
        )
        saveJSON(capped, url: accountDirectory(accountKey).appendingPathComponent("theol_test_details.json"))
    }

    public func loadTheolFilterPrefs(accountKey: String) -> TheolFilterPrefs {
        loadJSON(TheolFilterPrefs.self, url: accountDirectory(accountKey).appendingPathComponent("theol_filters.json"))
            ?? TheolFilterPrefs()
    }

    public func saveTheolFilterPrefs(_ prefs: TheolFilterPrefs, accountKey: String) {
        saveJSON(prefs, url: accountDirectory(accountKey).appendingPathComponent("theol_filters.json"))
    }

    public func loadLocalTodos(accountKey: String) -> [LocalTodoItem] {
        loadJSON([LocalTodoItem].self, url: accountDirectory(accountKey).appendingPathComponent("local_todos.json"))
            ?? []
    }

    public func saveLocalTodos(_ todos: [LocalTodoItem], accountKey: String) {
        saveJSON(todos, url: accountDirectory(accountKey).appendingPathComponent("local_todos.json"))
    }

    public func attachmentCacheDirectory() -> URL {
        let dir = rootDirectory.appendingPathComponent("theol_attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        trimAttachmentCacheIfNeeded(at: dir)
        return dir
    }

    // MARK: - 校园邮箱 (mail.buct.edu.cn)

    public func mailSnapshotStore(accountKey: String) -> DomainSliceStore<MailSnapshot> {
        DomainSliceStore(
            source: "mail.buct.edu.cn",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("mail_snapshot.json")
        )
    }

    public func loadMailDetails(accountKey: String) -> [String: MailMessageDetail] {
        loadJSON([String: MailMessageDetail].self, url: accountDirectory(accountKey).appendingPathComponent("mail_details.json"))
            ?? [:]
    }

    public func saveMailDetails(_ details: [String: MailMessageDetail], accountKey: String) {
        let capped = Dictionary(
            uniqueKeysWithValues: details.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(Self.maxCachedDetails).map { ($0.key, $0.value) }
        )
        saveJSON(capped, url: accountDirectory(accountKey).appendingPathComponent("mail_details.json"))
    }

    public func mailAttachmentCacheDirectory() -> URL {
        let dir = rootDirectory.appendingPathComponent("mail_attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        trimAttachmentCacheIfNeeded(at: dir)
        return dir
    }

    // MARK: - 宿舍电费 (ele.buct.one)

    public func electricitySnapshotStore(accountKey: String) -> DomainSliceStore<ElectricitySnapshot> {
        DomainSliceStore(
            source: "ele.buct.one",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("electricity_snapshot.json")
        )
    }

    public func clearElectricitySnapshot(accountKey: String) {
        let url = accountDirectory(accountKey).appendingPathComponent("electricity_snapshot.json")
        try? FileManager.default.removeItem(at: url)
    }

    public func loadElectricityConsent(accountKey: String) -> Bool {
        loadJSON(Bool.self, url: accountDirectory(accountKey).appendingPathComponent("electricity_consent.json")) ?? false
    }

    public func saveElectricityConsent(_ granted: Bool, accountKey: String) {
        saveJSON(granted, url: accountDirectory(accountKey).appendingPathComponent("electricity_consent.json"))
    }

    public func getOrCreateElectricityClientId() -> String {
        let url = rootDirectory.appendingPathComponent("electricity_client_id.txt")
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? fresh.write(to: url, atomically: true, encoding: .utf8)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        return fresh
    }

    // MARK: - 校园网网费 (tree.buct.edu.cn)

    public func campusNetSnapshotStore(accountKey: String) -> DomainSliceStore<CampusNetSnapshot> {
        DomainSliceStore(
            source: "tree.buct.edu.cn",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("campus_net_snapshot.json")
        )
    }

    // MARK: - M3-1 校内全域 (一卡通 / 第二课堂 / 实践教学 / 体测)

    public func cardSnapshotStore(accountKey: String) -> DomainSliceStore<CardSnapshot> {
        DomainSliceStore(
            source: "ecard.buct.edu.cn",
            parserVersion: 3,
            fileURL: accountDirectory(accountKey).appendingPathComponent("ecard_snapshot.json")
        )
    }

    public func scsSnapshotStore(accountKey: String) -> DomainSliceStore<ScsSnapshot> {
        DomainSliceStore(
            source: "scs.buct.edu.cn",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("scs_snapshot.json")
        )
    }

    public func sjcxSnapshotStore(accountKey: String) -> DomainSliceStore<SjcxSnapshot> {
        DomainSliceStore(
            source: "sjcx.buct.edu.cn",
            parserVersion: 2,
            fileURL: accountDirectory(accountKey).appendingPathComponent("sjcx_snapshot.json")
        )
    }

    public func tyglSnapshotStore(accountKey: String) -> DomainSliceStore<TyglSnapshot> {
        DomainSliceStore(
            source: "tygl.buct.edu.cn",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("tygl_snapshot.json")
        )
    }

    // MARK: - M3-2 选课中心 (jwglxt)

    public func courseSelectionSnapshotStore(accountKey: String) -> DomainSliceStore<CourseSelectionSnapshot> {
        DomainSliceStore(
            source: "jwglxt.xsxk",
            parserVersion: 1,
            fileURL: accountDirectory(accountKey).appendingPathComponent("course_selection_snapshot.json")
        )
    }

    public func loadCourseSelectionWishlist(accountKey: String) -> [CourseSelectionWishlistItem] {
        loadJSON([CourseSelectionWishlistItem].self, url: accountDirectory(accountKey).appendingPathComponent("course_selection_wishlist.json"))
            ?? []
    }

    public func saveCourseSelectionWishlist(_ items: [CourseSelectionWishlistItem], accountKey: String) {
        saveJSON(items, url: accountDirectory(accountKey).appendingPathComponent("course_selection_wishlist.json"))
    }

    private func trimAttachmentCacheIfNeeded(at dir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]) else {
            return
        }
        var files: [(url: URL, size: Int64, mtime: Date)] = []
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  vals.isRegularFile == true else { continue }
            let size = Int64(vals.fileSize ?? 0)
            totalSize += size
            files.append((fileURL, size, vals.contentModificationDate ?? .distantPast))
        }
        guard totalSize > Self.maxAttachmentCacheBytes else { return }
        for file in files.sorted(by: { $0.mtime < $1.mtime }) {
            guard totalSize > Self.trimTargetBytes else { break }
            try? fm.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    private func accountDirectory(_ accountKey: String) -> URL {
        rootDirectory
            .appendingPathComponent("campus", isDirectory: true)
            .appendingPathComponent(sanitize(accountKey), isDirectory: true)
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private func sanitize(_ raw: String) -> String {
        raw.replacingOccurrences(of: "[^A-Za-z0-9_\\-]", with: "_", options: .regularExpression)
    }
}
