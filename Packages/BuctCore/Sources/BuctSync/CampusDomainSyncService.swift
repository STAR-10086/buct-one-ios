import BuctModel
import BuctNetwork
import BuctSources
import BuctStore
import Foundation

public actor CampusDomainSyncService {
    private static let cacheTTLMs: Int64 = 30 * 60 * 1000

    private let sessionVault: SessionVaultStore
    private let dataStore: CampusDomainDataStore
    private let silentRelogin: SsoSilentRelogin
    private let singleFlight = SingleFlightCoordinator()

    private let jwNoticeClient = JwNoticeClient()
    private let portalClient = PortalCalendarClient()
    private let theolClient = TheolClient()
    private let mailClient = MailClient()
    private let electricityClient = ElectricityClient()
    private let campusNetClient = CampusNetClient()
    private let ecardClient = EcardClient()
    private let scsClient = ScsClient()
    private let sjcxClient = SjcxClient()
    private let tyglClient = TyglClient()
    private let courseSelectionClient = CourseSelectionClient()
    private let cardVault = CardSessionVaultStore()

    private var unitCache: [String: [TheolCourseUnit]] = [:]
    private var resourceCache: [String: TheolResourcePage] = [:]

    public init(
        sessionVault: SessionVaultStore = SessionVaultStore(),
        dataStore: CampusDomainDataStore? = nil,
        silentRelogin: SsoSilentRelogin? = nil
    ) {
        self.sessionVault = sessionVault
        self.dataStore = dataStore ?? CampusDomainDataStore()
        self.silentRelogin = silentRelogin ?? SsoSilentRelogin(sessionVault: sessionVault, authClient: BuctSsoAuthClient())
    }

    // MARK: - 教务消息 (jwNotice)

    public func loadCachedJwNotice(profile: UserAccountProfile) async -> DomainSlice<JwNoticeSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.jwNoticeSnapshot(), source: "demo", parserVersion: 1)
        }
        let store = await dataStore.jwNoticeStore(accountKey: profile.accountKey)
        let slice = await store.load()
        if let data = slice.data {
            let readIds = await dataStore.loadJwNoticeReadIds(accountKey: profile.accountKey)
            return DomainSlice(data: Self.applyReadIds(readIds, to: data), provenance: slice.provenance)
        }
        return slice
    }

    public func syncJwNotice(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<JwNoticeSnapshot> {
        if profile.isDemoMode {
            return await loadCachedJwNotice(profile: profile)
        }
        let store = await dataStore.jwNoticeStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if cached.provenance.refreshState == .fresh, cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return await loadCachedJwNotice(profile: profile)
            }
        }
        guard profile.systemType == .undergradJwglxt else {
            return await loadCachedJwNotice(profile: profile)
        }

        let key = "jwnotice::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snapshot = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    let snap = try await jwNoticeClient.fetchFullSnapshot(sidCookies: sess.sidCookies, jwCookies: sess.jwglxtCookies)
                    let updatedJw = await jwNoticeClient.exportJwCookies()
                    if !updatedJw.isEmpty {
                        await sessionVault.saveJwglxtCookies(updatedJw)
                    }
                    return snap
                }
                let readIds = await dataStore.loadJwNoticeReadIds(accountKey: profile.accountKey)
                let merged = Self.applyReadIds(readIds, to: snapshot)
                let isEmpty = merged.reminders.isEmpty && merged.announcements.isEmpty
                try await store.saveSuccess(data: merged, isEmpty: isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await loadCachedJwNotice(profile: profile)
    }

    public func loadMoreJwReminders(profile: UserAccountProfile, page: Int, keyword: String = "") async throws -> (total: Int, items: [JwReminderItem]) {
        guard !profile.isDemoMode else { return (0, []) }
        let res = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await jwNoticeClient.seedCookies(sidCookies: sess.sidCookies, jwCookies: sess.jwglxtCookies)
            return try await jwNoticeClient.fetchRemindersPage(page: page, pageSize: 30, keyword: keyword)
        }
        let readIds = await dataStore.loadJwNoticeReadIds(accountKey: profile.accountKey)
        let readSet = Set(readIds.reminderIds)
        return (res.total, res.items.map { item in
            var copy = item
            if readSet.contains(item.id) { copy.isRead = true }
            return copy
        })
    }

    public func loadMoreJwAnnouncements(profile: UserAccountProfile, page: Int, keyword: String = "") async throws -> (total: Int, items: [JwAnnouncementItem]) {
        guard !profile.isDemoMode else { return (0, []) }
        let res = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await jwNoticeClient.seedCookies(sidCookies: sess.sidCookies, jwCookies: sess.jwglxtCookies)
            return try await jwNoticeClient.fetchAnnouncementsPage(page: page, pageSize: 25, keyword: keyword)
        }
        let readIds = await dataStore.loadJwNoticeReadIds(accountKey: profile.accountKey)
        let readSet = Set(readIds.announcementIds)
        return (res.total, res.items.map { item in
            var copy = item
            if readSet.contains(item.id) { copy.isRead = true }
            return copy
        })
    }

    public func fetchJwAnnouncementDetail(profile: UserAccountProfile, item: JwAnnouncementItem) async throws -> JwAnnouncementDetail {
        if profile.isDemoMode {
            return JwAnnouncementDetail(
                id: item.id,
                title: item.title,
                publisher: item.publisher,
                publishedAt: item.publishedAt,
                viewCount: "128",
                bodyHtml: item.inlineHtml,
                plainText: item.inlineHtml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            )
        }
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await jwNoticeClient.seedCookies(sidCookies: sess.sidCookies, jwCookies: sess.jwglxtCookies)
            return try await jwNoticeClient.fetchAnnouncementDetail(item: item)
        }
    }

    public func markJwReminderRead(profile: UserAccountProfile, id: String) async {
        guard !profile.isDemoMode else { return }
        var readIds = await dataStore.loadJwNoticeReadIds(accountKey: profile.accountKey)
        if !readIds.reminderIds.contains(id) {
            readIds.reminderIds.append(id)
            await dataStore.saveJwNoticeReadIds(readIds, accountKey: profile.accountKey)
        }
    }

    public func markJwAnnouncementRead(profile: UserAccountProfile, id: String) async {
        guard !profile.isDemoMode else { return }
        var readIds = await dataStore.loadJwNoticeReadIds(accountKey: profile.accountKey)
        if !readIds.announcementIds.contains(id) {
            readIds.announcementIds.append(id)
            await dataStore.saveJwNoticeReadIds(readIds, accountKey: profile.accountKey)
        }
    }

    // MARK: - i北化 (校内资讯与图书馆)

    public func loadCachedPortalNews(profile: UserAccountProfile) async -> DomainSlice<PortalNewsSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.portalNewsSnapshot(), source: "demo", parserVersion: 2)
        }
        let store = await dataStore.portalNewsStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncPortalNews(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<PortalNewsSnapshot> {
        if profile.isDemoMode {
            return await loadCachedPortalNews(profile: profile)
        }
        let store = await dataStore.portalNewsStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if (cached.provenance.refreshState == .fresh || cached.provenance.refreshState == .emptyConfirmed),
               cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }

        let key = "portal_news::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snapshot = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    return try await portalClient.fetchAllNewsSnapshot(sidCookies: sess.sidCookies)
                }
                let isEmpty = snapshot.columns.values.allSatisfy { $0.articles.isEmpty }
                try await store.saveSuccess(data: snapshot, isEmpty: isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func loadMorePortalNews(profile: UserAccountProfile, column: PortalNewsColumn, beginIndex: Int) async throws -> PortalNewsColumnPage {
        guard !profile.isDemoMode else { return PortalNewsColumnPage(columnId: column.rawValue, totalCount: 0, articles: []) }
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await portalClient.fetchNewsColumn(column: column, beginIndex: beginIndex, pageSize: 15, sidCookies: sess.sidCookies)
        }
    }

    public func loadCachedPortalLibrary(profile: UserAccountProfile) async -> DomainSlice<PortalLibrarySnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.portalLibrarySnapshot(), source: "demo", parserVersion: 2)
        }
        let store = await dataStore.portalLibraryStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncPortalLibrary(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<PortalLibrarySnapshot> {
        if profile.isDemoMode {
            return await loadCachedPortalLibrary(profile: profile)
        }
        let store = await dataStore.portalLibraryStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if (cached.provenance.refreshState == .fresh || cached.provenance.refreshState == .emptyConfirmed),
               cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }

        let key = "portal_library::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snapshot = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    return try await portalClient.fetchBorrowedBooks(sidCookies: sess.sidCookies)
                }
                try await store.saveSuccess(data: snapshot, isEmpty: snapshot.books.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - 北化在线 (THEOL)

    public func loadCachedTheol(profile: UserAccountProfile) async -> DomainSlice<TheolSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.theolSnapshot(), source: "demo", parserVersion: 7)
        }
        let store = await dataStore.theolSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncTheolPhase1(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<TheolSnapshot> {
        if profile.isDemoMode {
            return await loadCachedTheol(profile: profile)
        }
        guard profile.systemType == .undergradJwglxt else {
            return await loadCachedTheol(profile: profile)
        }
        let store = await dataStore.theolSnapshotStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if cached.provenance.refreshState == .fresh, cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }

        let key = "theol_p1::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snapshot = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    let snap = try await theolClient.fetchPhase1Snapshot(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
                    let updatedMeol = await theolClient.exportMeolCookies()
                    if !updatedMeol.isEmpty {
                        await sessionVault.saveMeolCookies(updatedMeol)
                    }
                    return snap
                }
                let isEmpty = snapshot.homeworks.isEmpty && snapshot.tests.isEmpty && snapshot.courses.isEmpty
                try await store.saveSuccess(data: snapshot, isEmpty: isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func syncTheolPhase2Courses(profile: UserAccountProfile) async -> DomainSlice<TheolSnapshot> {
        guard !profile.isDemoMode, profile.systemType == .undergradJwglxt else {
            return await loadCachedTheol(profile: profile)
        }
        let store = await dataStore.theolSnapshotStore(accountKey: profile.accountKey)
        let current = await store.load()
        guard var snap = current.data, !snap.courses.isEmpty else {
            return current
        }

        var hwById = Dictionary(uniqueKeysWithValues: snap.homeworks.map { ($0.id, $0) })
        var testById = Dictionary(uniqueKeysWithValues: snap.tests.map { ($0.id, $0) })
        let activeCourses = snap.courses.prefix(24)

        for course in activeCourses {
            if let moreHw = try? await theolClient.fetchSingleCourseHomeworksFast(lid: course.lid, courseName: course.courseName) {
                for item in moreHw { hwById[item.id] = item }
            }
            if let moreTests = try? await theolClient.fetchCourseTests(lid: course.lid, courseName: course.courseName) {
                for item in moreTests { testById[item.id] = item }
            }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }

        snap.homeworks = TheolSorting.sortHomeworks(Array(hwById.values))
        snap.tests = TheolSorting.sortTests(Array(testById.values))
        try? await store.saveSuccess(data: snap, isEmpty: snap.homeworks.isEmpty && snap.tests.isEmpty && snap.courses.isEmpty)
        return await store.load()
    }

    public func fetchTheolHomeworkDetail(profile: UserAccountProfile, item: TheolHomeworkItem, forceRefresh: Bool = false) async throws -> TheolHomeworkDetail {
        if profile.isDemoMode {
            return TheolHomeworkDetail(
                hwtid: item.hwtid,
                title: item.title,
                deadline: item.deadline,
                score: item.score,
                publisher: item.publisher,
                contentText: "请按实验指导书完成实验并提交 PDF 实验报告（演示数据）。",
                attachments: []
            )
        }
        var cache = await dataStore.loadTheolHomeworkDetails(accountKey: profile.accountKey)
        if !forceRefresh, let cached = cache[item.hwtid] {
            return cached
        }
        let detail = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await theolClient.seedCookies(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
            return try await theolClient.fetchHomeworkDetail(item: item)
        }
        cache[item.hwtid] = detail
        await dataStore.saveTheolHomeworkDetails(cache, accountKey: profile.accountKey)
        return detail
    }

    public func fetchTheolTestDetail(profile: UserAccountProfile, item: TheolTestItem, forceRefresh: Bool = false) async throws -> TheolTestDetail {
        if profile.isDemoMode {
            return TheolTestDetail(
                testId: item.testId,
                title: item.title,
                description: "覆盖第 1-4 章核心知识点，限时作答（演示数据）。",
                startTime: item.startTime,
                endTime: item.endTime,
                duration: item.duration,
                totalScore: "100",
                questionCount: "20"
            )
        }
        var cache = await dataStore.loadTheolTestDetails(accountKey: profile.accountKey)
        if !forceRefresh, let cached = cache[item.testId] {
            return cached
        }
        let detail = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await theolClient.seedCookies(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
            return try await theolClient.fetchTestDetail(item: item)
        }
        cache[item.testId] = detail
        await dataStore.saveTheolTestDetails(cache, accountKey: profile.accountKey)
        return detail
    }

    public func fetchTheolCourseUnits(profile: UserAccountProfile, lid: String, forceRefresh: Bool = false) async throws -> [TheolCourseUnit] {
        if profile.isDemoMode {
            return [
                TheolCourseUnit(columnId: "u1", title: "第一章 绪论", url: "https://course.buct.edu.cn"),
                TheolCourseUnit(columnId: "u2", title: "第二章 核心原理", url: "https://course.buct.edu.cn")
            ]
        }
        if !forceRefresh, let cached = unitCache[lid] {
            return cached
        }
        let units = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await theolClient.seedCookies(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
            return try await theolClient.fetchCourseUnits(lid: lid)
        }
        unitCache[lid] = units
        return units
    }

    public func fetchTheolCourseResources(profile: UserAccountProfile, lid: String, courseName: String, folderUrl: String? = nil, forceRefresh: Bool = false) async throws -> TheolResourcePage {
        if profile.isDemoMode {
            return TheolResourcePage(
                lid: lid,
                courseName: courseName,
                currentUrl: folderUrl ?? "https://course.buct.edu.cn",
                folderTitle: "课程资源",
                items: [
                    TheolResourceItem(name: "第 1 讲 课程导论.pdf", isFolder: false, url: "https://course.buct.edu.cn/demo1.pdf", sizeText: "2.4 MB", updatedAt: "2026-03-05", fileExt: "pdf"),
                    TheolResourceItem(name: "实验指导书", isFolder: true, url: "https://course.buct.edu.cn/folder1", updatedAt: "2026-03-08")
                ]
            )
        }
        let cacheKey = "\(lid)::\(folderUrl ?? "root")"
        if !forceRefresh, let cached = resourceCache[cacheKey] {
            return cached
        }
        let page = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await theolClient.seedCookies(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
            return try await theolClient.fetchCourseResources(lid: lid, courseName: courseName, folderUrl: folderUrl)
        }
        resourceCache[cacheKey] = page
        return page
    }

    public func fetchTheolUnitResources(profile: UserAccountProfile, lid: String, courseName: String, unit: TheolCourseUnit, forceRefresh: Bool = false) async throws -> TheolResourcePage {
        if profile.isDemoMode {
            return TheolResourcePage(
                lid: lid,
                courseName: courseName,
                currentUrl: unit.url,
                folderTitle: unit.title,
                items: [
                    TheolResourceItem(name: "\(unit.title) 课件.pptx", isFolder: false, url: "https://course.buct.edu.cn/unit.pptx", sizeText: "5.1 MB", updatedAt: "2026-03-10", fileExt: "pptx")
                ]
            )
        }
        let cacheKey = "unit::\(lid)::\(unit.columnId)"
        if !forceRefresh, let cached = resourceCache[cacheKey] {
            return cached
        }
        let page = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await theolClient.seedCookies(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
            return try await theolClient.fetchUnitResources(lid: lid, courseName: courseName, unit: unit)
        }
        resourceCache[cacheKey] = page
        return page
    }

    public func downloadTheolFile(profile: UserAccountProfile, urlString: String, courseLid: String, referer: String) async throws -> TheolDownloadedFile {
        guard !profile.isDemoMode else {
            throw NSError(domain: "CampusDomainSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "演示模式不支持下载校内附件"])
        }
        let cacheDir = await dataStore.attachmentCacheDirectory()
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            await theolClient.seedCookies(sidCookies: sess.sidCookies, meolCookies: sess.meolCookies)
            return try await theolClient.downloadFile(urlString: urlString, courseLid: courseLid, referer: referer, cacheDirectory: cacheDir)
        }
    }

    public func prepareTheolWebLaunchContext(
        profile: UserAccountProfile,
        urlString: String,
        title: String,
        courseLid: String? = nil,
        touchHomework: Bool = false
    ) async throws -> TheolWebLaunchContext {
        if profile.isDemoMode {
            return TheolWebLaunchContext(urlString: urlString, title: title, cookies: [])
        }
        let cookies = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            let prepared = try await theolClient.prepareWebSessionCookies(
                sidCookies: sess.sidCookies,
                meolCookies: sess.meolCookies,
                courseLid: courseLid,
                touchHomework: touchHomework
            )
            let updatedMeol = await theolClient.exportMeolCookies()
            if !updatedMeol.isEmpty {
                await sessionVault.saveMeolCookies(updatedMeol)
            }
            return prepared
        }
        return TheolWebLaunchContext(urlString: urlString, title: title, cookies: cookies)
    }

    public func loadLocalTodos(profile: UserAccountProfile) async -> [LocalTodoItem] {
        guard !profile.isDemoMode else { return [] }
        return await dataStore.loadLocalTodos(accountKey: profile.accountKey)
    }

    public func saveLocalTodos(_ todos: [LocalTodoItem], profile: UserAccountProfile) async {
        guard !profile.isDemoMode else { return }
        await dataStore.saveLocalTodos(todos, accountKey: profile.accountKey)
    }

    public func loadTheolFilterPrefs(profile: UserAccountProfile) async -> TheolFilterPrefs {
        guard !profile.isDemoMode else { return TheolFilterPrefs() }
        return await dataStore.loadTheolFilterPrefs(accountKey: profile.accountKey)
    }

    public func saveTheolFilterPrefs(_ prefs: TheolFilterPrefs, profile: UserAccountProfile) async {
        guard !profile.isDemoMode else { return }
        await dataStore.saveTheolFilterPrefs(prefs, accountKey: profile.accountKey)
    }

    // MARK: - 校园邮箱 (mail.buct.edu.cn)

    public func loadCachedMail(profile: UserAccountProfile) async -> DomainSlice<MailSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.mailSnapshot(), source: "demo", parserVersion: MailParser.parserVersion)
        }
        let store = await dataStore.mailSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncMail(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<MailSnapshot> {
        if profile.isDemoMode {
            return await loadCachedMail(profile: profile)
        }
        let store = await dataStore.mailSnapshotStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if (cached.provenance.refreshState == .fresh || cached.provenance.refreshState == .emptyConfirmed),
               cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }
        let key = "mail::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snapshot = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    return try await mailClient.fetchInitialSnapshot(sidCookies: sess.sidCookies)
                }
                try await store.saveSuccess(data: snapshot, isEmpty: snapshot.inboxMessages.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func listMailMessages(
        profile: UserAccountProfile,
        folderId: Int,
        start: Int = 0,
        limit: Int = 30,
        unreadOnly: Bool = false
    ) async throws -> (total: Int, messages: [MailMessageSummary]) {
        if profile.isDemoMode {
            let demo = DemoData.mailSnapshot().inboxMessages.filter { !unreadOnly || !$0.isRead }
            return (demo.count, demo)
        }
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await mailClient.listMessages(
                sidCookies: sess.sidCookies,
                folderId: folderId,
                start: start,
                limit: limit,
                unreadOnly: unreadOnly
            )
        }
    }

    public func fetchMailDetail(profile: UserAccountProfile, message: MailMessageSummary) async throws -> MailMessageDetail {
        if profile.isDemoMode {
            return MailMessageDetail(
                id: message.id,
                folderId: message.folderId,
                subject: message.subject,
                fromName: message.fromName,
                fromAddress: message.fromAddress,
                to: ["demo@buct.edu.cn"],
                sentAt: message.sentAt,
                htmlBody: "<p>\(message.summary)</p>",
                plainText: message.summary,
                attachments: message.attachments
            )
        }
        var cache = await dataStore.loadMailDetails(accountKey: profile.accountKey)
        if let cached = cache[message.id] {
            return cached
        }
        let detail = try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await mailClient.readMessageDetail(sidCookies: sess.sidCookies, messageId: message.id, folderId: message.folderId)
        }
        cache[message.id] = detail
        await dataStore.saveMailDetails(cache, accountKey: profile.accountKey)
        return detail
    }

    public func setMailRead(profile: UserAccountProfile, messageId: String, isRead: Bool) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            try await mailClient.setMessageRead(sidCookies: sess.sidCookies, messageId: messageId, isRead: isRead)
        }
    }

    public func deleteMail(profile: UserAccountProfile, messageId: String, currentFolderId: Int, permanent: Bool = false) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            if permanent || currentFolderId == MailFolder.trashId {
                try await mailClient.deleteMessagePermanently(sidCookies: sess.sidCookies, messageId: messageId)
            } else {
                try await mailClient.moveMessage(sidCookies: sess.sidCookies, messageId: messageId, targetFolderId: MailFolder.trashId)
            }
        }
    }

    public func restoreMailToInbox(profile: UserAccountProfile, messageId: String) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            try await mailClient.moveMessage(sidCookies: sess.sidCookies, messageId: messageId, targetFolderId: MailFolder.inboxId)
        }
    }

    public func markMailFolderAllRead(profile: UserAccountProfile, folderId: Int) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            try await mailClient.markFolderAllRead(sidCookies: sess.sidCookies, folderId: folderId)
        }
    }

    public func downloadMailAttachment(profile: UserAccountProfile, messageId: String, attachment: MailAttachment) async throws -> MailDownloadedFile {
        guard !profile.isDemoMode else {
            throw NSError(domain: "CampusDomainSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "演示模式不支持下载邮件附件"])
        }
        let dir = await dataStore.mailAttachmentCacheDirectory()
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await mailClient.downloadAttachment(
                sidCookies: sess.sidCookies,
                messageId: messageId,
                attachment: attachment,
                cacheDirectory: dir
            )
        }
    }

    // MARK: - 宿舍电费 (ele.buct.one)

    public func loadElectricityCatalog(data: Data) throws -> ElectricityRoomCatalog {
        try ElectricityParser.parseCatalog(data: data)
    }

    public func loadElectricityConsent(profile: UserAccountProfile) async -> Bool {
        if profile.isDemoMode { return true }
        return await dataStore.loadElectricityConsent(accountKey: profile.accountKey)
    }

    public func setElectricityConsent(_ granted: Bool, profile: UserAccountProfile) async {
        guard !profile.isDemoMode else { return }
        await dataStore.saveElectricityConsent(granted, accountKey: profile.accountKey)
        if !granted {
            await dataStore.clearElectricitySnapshot(accountKey: profile.accountKey)
        }
    }

    public func loadCachedElectricity(profile: UserAccountProfile) async -> DomainSlice<ElectricitySnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.electricitySnapshot(), source: "demo", parserVersion: ElectricityParser.parserVersion)
        }
        let store = await dataStore.electricitySnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func updateElectricityTargets(_ targets: [ElectricityRoomTarget], threshold: Double? = nil, profile: UserAccountProfile) async -> DomainSlice<ElectricitySnapshot> {
        guard !profile.isDemoMode else { return await loadCachedElectricity(profile: profile) }
        let store = await dataStore.electricitySnapshotStore(accountKey: profile.accountKey)
        let current = await store.load().data ?? ElectricitySnapshot()
        let updated = ElectricitySnapshot(
            targets: targets,
            readings: current.readings.filter { r in targets.contains { $0.id == r.id } },
            lowBalanceThreshold: threshold ?? current.lowBalanceThreshold
        )
        try? await store.saveSuccess(data: updated, isEmpty: targets.isEmpty)
        return await store.load()
    }

    public func syncElectricity(
        profile: UserAccountProfile,
        signSecret: String,
        appVersion: String
    ) async -> DomainSlice<ElectricitySnapshot> {
        if profile.isDemoMode {
            return await loadCachedElectricity(profile: profile)
        }
        let store = await dataStore.electricitySnapshotStore(accountKey: profile.accountKey)
        let consent = await dataStore.loadElectricityConsent(accountKey: profile.accountKey)
        guard consent else {
            _ = try? await store.recordFailure(error: "请先同意宿舍电费查询隐私声明")
            return await store.load()
        }
        let current = await store.load().data ?? ElectricitySnapshot()
        guard !current.targets.isEmpty else {
            return await store.load()
        }

        let key = "electricity::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let clientId = await dataStore.getOrCreateElectricityClientId()
                let readings = try await electricityClient.fetchReadings(
                    targets: current.targets,
                    studentId: profile.studentId,
                    clientId: clientId,
                    signSecret: signSecret,
                    appVersion: appVersion
                )
                let updated = ElectricitySnapshot(
                    targets: current.targets,
                    readings: readings,
                    lowBalanceThreshold: current.lowBalanceThreshold
                )
                try await store.saveSuccess(data: updated, isEmpty: readings.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - 校园网网费 (tree.buct.edu.cn)

    public func loadCachedCampusNet(profile: UserAccountProfile) async -> DomainSlice<CampusNetSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.campusNetSnapshot(), source: "demo", parserVersion: CampusNetParser.parserVersion)
        }
        let store = await dataStore.campusNetSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncCampusNet(profile: UserAccountProfile, appVersion: String, userInitiated: Bool = true) async -> DomainSlice<CampusNetSnapshot> {
        if profile.isDemoMode {
            return await loadCachedCampusNet(profile: profile)
        }
        let store = await dataStore.campusNetSnapshotStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if (cached.provenance.refreshState == .fresh || cached.provenance.refreshState == .emptyConfirmed),
               cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }

        let key = "campus_net::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snapshot = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    try await campusNetClient.fetchSnapshot(fallbackStudentId: profile.studentId, appVersion: appVersion)
                }
                try await store.saveSuccess(data: snapshot, isEmpty: false)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - 校园一卡通 (ecard.buct.edu.cn)

    public func hasSavedCardCredential(profile: UserAccountProfile) async -> Bool {
        if profile.isDemoMode { return true }
        return await cardVault.loadCredential(accountKey: profile.accountKey) != nil
    }

    public func loadCachedCard(profile: UserAccountProfile) async -> DomainSlice<CardSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.cardSnapshot(), source: "demo", parserVersion: EcardParser.parserVersion)
        }
        let store = await dataStore.cardSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func loginAndSyncCard(
        profile: UserAccountProfile,
        idSerial: String,
        password: String,
        startDate: String,
        endDate: String
    ) async throws -> DomainSlice<CardSnapshot> {
        if profile.isDemoMode {
            return await loadCachedCard(profile: profile)
        }
        let store = await dataStore.cardSnapshotStore(accountKey: profile.accountKey)
        do {
            try await ecardClient.login(idSerial: idSerial, password: password)
            await cardVault.saveCredential(EcardCredential(idSerial: idSerial, password: password), accountKey: profile.accountKey)
            let snap = try await ecardClient.fetchSnapshot(idSerial: idSerial, password: password, startDate: startDate, endDate: endDate)
            try await store.saveSuccess(data: snap, isEmpty: false)
            return await store.load()
        } catch let err as EcardAuthError {
            if err.invalidCredentials {
                await cardVault.clearCredential(accountKey: profile.accountKey)
            }
            _ = try? await store.recordFailure(error: err.localizedDescription)
            throw err
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
            throw error
        }
    }

    public func syncCard(profile: UserAccountProfile, startDate: String, endDate: String) async -> DomainSlice<CardSnapshot> {
        if profile.isDemoMode {
            return await loadCachedCard(profile: profile)
        }
        let store = await dataStore.cardSnapshotStore(accountKey: profile.accountKey)
        guard let cred = await cardVault.loadCredential(accountKey: profile.accountKey) else {
            return await store.load()
        }
        let key = "ecard::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snap = try await ecardClient.fetchSnapshot(
                    idSerial: cred.idSerial,
                    password: cred.password,
                    startDate: startDate,
                    endDate: endDate
                )
                try await store.saveSuccess(data: snap, isEmpty: false)
            }
        } catch let err as EcardAuthError {
            if err.invalidCredentials {
                await cardVault.clearCredential(accountKey: profile.accountKey)
            }
            _ = try? await store.recordFailure(error: err.localizedDescription)
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func loadMoreCardTransactions(
        profile: UserAccountProfile,
        startDate: String,
        endDate: String,
        pageNumber: Int
    ) async throws -> (total: Int, rows: [CardTransaction]) {
        guard !profile.isDemoMode,
              let cred = await cardVault.loadCredential(accountKey: profile.accountKey) else {
            return (0, [])
        }
        return try await ecardClient.fetchTransactionsPage(
            idSerial: cred.idSerial,
            startDate: startDate,
            endDate: endDate,
            pageNumber: pageNumber
        )
    }

    public func logoutCard(profile: UserAccountProfile) async {
        await cardVault.clearCredential(accountKey: profile.accountKey)
        await ecardClient.clearSession()
    }

    // MARK: - 第二课堂 (scs.buct.edu.cn)

    public func loadCachedScs(profile: UserAccountProfile) async -> DomainSlice<ScsSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.scsSnapshot(), source: "demo", parserVersion: ScsParser.parserVersion)
        }
        let store = await dataStore.scsSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncScs(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<ScsSnapshot> {
        if profile.isDemoMode { return await loadCachedScs(profile: profile) }
        let store = await dataStore.scsSnapshotStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if cached.provenance.refreshState == .fresh, cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }
        let key = "scs::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snap = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    return try await scsClient.fetchSnapshot(sidCookies: sess.sidCookies, fallbackStudentId: profile.studentId)
                }
                try await store.saveSuccess(data: snap, isEmpty: snap.terms.isEmpty && snap.activities.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - 实践教学 (sjcx.buct.edu.cn)

    public func loadCachedSjcx(profile: UserAccountProfile) async -> DomainSlice<SjcxSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.sjcxSnapshot(), source: "demo", parserVersion: SjcxParser.parserVersion)
        }
        let store = await dataStore.sjcxSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncSjcx(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<SjcxSnapshot> {
        if profile.isDemoMode { return await loadCachedSjcx(profile: profile) }
        let store = await dataStore.sjcxSnapshotStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if cached.provenance.refreshState == .fresh, cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }
        let key = "sjcx::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snap = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    return try await sjcxClient.fetchSnapshot(sidCookies: sess.sidCookies)
                }
                let isEmpty = snap.reports.isEmpty && snap.schedules.isEmpty && snap.openLectures.isEmpty && snap.creditRecords.isEmpty
                try await store.saveSuccess(data: snap, isEmpty: isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func registerSjcxLecture(profile: UserAccountProfile, projectTimeId: String) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            try await sjcxClient.registerLecture(sidCookies: sess.sidCookies, projectTimeId: projectTimeId)
        }
    }

    public func cancelSjcxLecture(profile: UserAccountProfile, registrationId: String) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            try await sjcxClient.cancelLectureRegistration(sidCookies: sess.sidCookies, registrationId: registrationId)
        }
    }

    public func submitSjcxExperience(profile: UserAccountProfile, registrationId: String, experience: String) async throws {
        guard !profile.isDemoMode else { return }
        try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            try await sjcxClient.submitLectureExperience(sidCookies: sess.sidCookies, registrationId: registrationId, experience: experience)
        }
    }

    // MARK: - 体测与体育 (tygl.buct.edu.cn)

    public func loadCachedTygl(profile: UserAccountProfile) async -> DomainSlice<TyglSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.tyglSnapshot(), source: "demo", parserVersion: TyglParser.parserVersion)
        }
        let store = await dataStore.tyglSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncTygl(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<TyglSnapshot> {
        if profile.isDemoMode { return await loadCachedTygl(profile: profile) }
        let store = await dataStore.tyglSnapshotStore(accountKey: profile.accountKey)
        if !userInitiated {
            let cached = await store.load()
            let age = Int64(Date().timeIntervalSince1970 * 1000) - cached.provenance.capturedAt
            if cached.provenance.refreshState == .fresh, cached.data != nil, (0..<Self.cacheTTLMs).contains(age) {
                return cached
            }
        }
        let key = "tygl::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snap = try await performWithRelogin(profile: profile, bypassCooldown: userInitiated) {
                    let sess = await sessionVault.loadSession()
                    return try await tyglClient.fetchSnapshot(sidCookies: sess.sidCookies)
                }
                let isEmpty = snap.fitnessRecords.isEmpty && snap.peCourses.isEmpty && snap.exerciseTerms.isEmpty
                try await store.saveSuccess(data: snap, isEmpty: isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - M3-2 选课中心 (jwglxt)

    public func loadCachedCourseSelection(profile: UserAccountProfile) async -> DomainSlice<CourseSelectionSnapshot> {
        if profile.isDemoMode {
            return demoSlice(DemoData.courseSelectionSnapshot(), source: "demo", parserVersion: CourseSelectionParser.parserVersion)
        }
        let store = await dataStore.courseSelectionSnapshotStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncCourseSelection(
        profile: UserAccountProfile,
        onlyWithSeats: Bool = false,
        keyword: String = ""
    ) async -> DomainSlice<CourseSelectionSnapshot> {
        if profile.isDemoMode {
            return await loadCachedCourseSelection(profile: profile)
        }
        let store = await dataStore.courseSelectionSnapshotStore(accountKey: profile.accountKey)
        guard profile.systemType == .undergradJwglxt else {
            _ = try? await store.recordFailure(error: "选课中心当前仅支持本科正方教务系统")
            return await store.load()
        }
        let key = "xsxk::\(profile.accountKey)"
        do {
            try await singleFlight.run(key: key) { [self] in
                let snap = try await performWithRelogin(profile: profile, bypassCooldown: true) {
                    let sess = await sessionVault.loadSession()
                    let res = try await courseSelectionClient.fetchSnapshot(
                        sidCookies: sess.sidCookies,
                        jwCookies: sess.jwglxtCookies,
                        onlyWithSeats: onlyWithSeats,
                        keyword: keyword
                    )
                    let updatedJw = await courseSelectionClient.exportJwCookies()
                    if !updatedJw.isEmpty {
                        await sessionVault.saveJwglxtCookies(updatedJw)
                    }
                    return res
                }
                let isEmpty = snap.availableCourses.isEmpty && snap.selectedCourses.isEmpty
                try await store.saveSuccess(data: snap, isEmpty: isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func fetchCourseTeachingClasses(profile: UserAccountProfile, course: CourseSelectionCourse) async throws -> [CourseSelectionCourse] {
        if profile.isDemoMode {
            return DemoData.courseSelectionSnapshot().availableCourses.filter { $0.courseId == course.courseId }
        }
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await courseSelectionClient.fetchTeachingClasses(
                sidCookies: sess.sidCookies,
                jwCookies: sess.jwglxtCookies,
                course: course
            )
        }
    }

    public func selectCourse(profile: UserAccountProfile, course: CourseSelectionCourse) async throws -> CourseSelectionActionResult {
        if profile.isDemoMode {
            return CourseSelectionActionResult(success: true, message: "演示模式：已模拟选课成功")
        }
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await courseSelectionClient.selectCourse(
                sidCookies: sess.sidCookies,
                jwCookies: sess.jwglxtCookies,
                course: course
            )
        }
    }

    public func dropCourse(profile: UserAccountProfile, course: CourseSelectionCourse) async throws -> CourseSelectionActionResult {
        if profile.isDemoMode {
            return CourseSelectionActionResult(success: true, message: "演示模式：已模拟退课成功")
        }
        return try await performWithRelogin(profile: profile, bypassCooldown: true) {
            let sess = await sessionVault.loadSession()
            return try await courseSelectionClient.dropCourse(
                sidCookies: sess.sidCookies,
                jwCookies: sess.jwglxtCookies,
                course: course
            )
        }
    }

    public func loadCourseWishlist(profile: UserAccountProfile) async -> [CourseSelectionWishlistItem] {
        guard !profile.isDemoMode else { return [] }
        return await dataStore.loadCourseSelectionWishlist(accountKey: profile.accountKey)
    }

    public func saveCourseWishlist(_ items: [CourseSelectionWishlistItem], profile: UserAccountProfile) async {
        guard !profile.isDemoMode else { return }
        await dataStore.saveCourseSelectionWishlist(items, accountKey: profile.accountKey)
    }

    // MARK: - 内部辅助

    private func performWithRelogin<T: Sendable>(
        profile: UserAccountProfile,
        bypassCooldown: Bool,
        operation: () async throws -> T
    ) async throws -> T {
        let sidSnapshot = await sessionVault.loadSession().sidCookies
        do {
            return try await operation()
        } catch {
            let msg = error.localizedDescription
            let isAuth = (error is JwNoticeAuthExpiredError) ||
                (error is TheolAuthExpiredError) ||
                (error is MailSessionExpiredError) ||
                (error is ScsAuthExpiredError) ||
                (error is SjcxAuthExpiredError) ||
                (error is TyglAuthExpiredError) ||
                (error is CourseSelectionAuthExpiredError) ||
                (error is BuctWebVpnAuthRequiredError) ||
                SsoSilentRelogin.isAuthFailureMessage(msg)
            guard isAuth, profile.systemType == .undergradJwglxt else {
                throw error
            }
            let relogined = await silentRelogin.attemptRelogin(sidSnapshotBefore: sidSnapshot, bypassCooldown: bypassCooldown)
            guard relogined else { throw error }
            return try await operation()
        }
    }

    private static func applyReadIds(_ readIds: JwNoticeReadIds, to snapshot: JwNoticeSnapshot) -> JwNoticeSnapshot {
        let remSet = Set(readIds.reminderIds)
        let annSet = Set(readIds.announcementIds)
        var copy = snapshot
        copy.reminders = snapshot.reminders.map { r in
            var item = r
            if remSet.contains(r.id) { item.isRead = true }
            return item
        }
        copy.announcements = snapshot.announcements.map { a in
            var item = a
            if annSet.contains(a.id) { item.isRead = true }
            return item
        }
        return copy
    }

    private func demoSlice<T: Codable & Sendable>(_ data: T, source: String, parserVersion: Int) -> DomainSlice<T> {
        DomainSlice(
            data: data,
            provenance: Provenance(
                source: source,
                capturedAt: Int64(Date().timeIntervalSince1970 * 1000),
                parserVersion: parserVersion,
                refreshState: .fresh
            )
        )
    }
}
