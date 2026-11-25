import BuctModel
import BuctStore
import BuctSync
import Observation
import SwiftUI

public enum AppTab: String, Hashable, CaseIterable {
    case schedule
    case grades
    case workbench
    case homework
    case settings
}

@Observable
@MainActor
public final class AppEnvironment {
    public var selectedTab: AppTab = .workbench
    public var appearance: AppearanceConfig = AppearanceConfig()
    public var dashboardLayout: DashboardLayout = .default
    public var screenSizeText: String = "393x852"

    public var currentProfile: UserAccountProfile?
    public var showLoginSheet: Bool = false

    public var selectedTerm: AcademicTerm = AcademicTerm.calendarDefault()
    public var availableTerms: [AcademicTerm] = AcademicTerm.undergradPickerTerms()
    public var selectedWeek: Int = 1
    public var calendarPrefs: OfficialCalendarPrefs = OfficialCalendarPrefs()

    public var scheduleSlice: DomainSlice<[ScheduleCourse]> = .never(source: "academic_schedule", parserVersion: 1)
    public var customCourses: [ScheduleCourse] = []
    public var semesterGradesSlice: DomainSlice<[GradeItem]> = .never(source: "academic_grades", parserVersion: 1)
    public var overallAcademicSlice: DomainSlice<OverallAcademicBundle> = .never(source: "academic_overall", parserVersion: 1)
    public var examsSlice: DomainSlice<[ExamItem]> = .never(source: "academic_exams", parserVersion: 1)
    public var customExams: [ExamItem] = []
    public var calendarSlice: DomainSlice<OfficialCalendarSnapshot> = .never(source: "portal_calendar", parserVersion: 2)
    public var reminderConfig: ReminderConfig = ReminderConfig()

    // M2-1 Slices
    public var jwNoticeSlice: DomainSlice<JwNoticeSnapshot> = .never(source: "jwglxt.buct.edu.cn", parserVersion: 1)
    public var portalNewsSlice: DomainSlice<PortalNewsSnapshot> = .never(source: "mnews.buct.edu.cn", parserVersion: 2)
    public var portalLibrarySlice: DomainSlice<PortalLibrarySnapshot> = .never(source: "i.buct.edu.cn", parserVersion: 2)
    public var theolSlice: DomainSlice<TheolSnapshot> = .never(source: "theol.homework", parserVersion: 7)
    public var localTodos: [LocalTodoItem] = []
    public var theolFilterPrefs: TheolFilterPrefs = TheolFilterPrefs()
    public var mailSlice: DomainSlice<MailSnapshot> = .never(source: "mail.buct.edu.cn", parserVersion: 2)
    public var electricitySlice: DomainSlice<ElectricitySnapshot> = .never(source: "ele.buct.one", parserVersion: 1)
    public var electricityConsentGranted = false
    public var campusNetSlice: DomainSlice<CampusNetSnapshot> = .never(source: "tree.buct.edu.cn", parserVersion: 2)
    public var cardSlice: DomainSlice<CardSnapshot> = .never(source: "ecard.buct.edu.cn", parserVersion: 3)
    public var hasCardCredential = false
    public var scsSlice: DomainSlice<ScsSnapshot> = .never(source: "scs.buct.edu.cn", parserVersion: 2)
    public var sjcxSlice: DomainSlice<SjcxSnapshot> = .never(source: "sjcx.buct.edu.cn", parserVersion: 2)
    public var tyglSlice: DomainSlice<TyglSnapshot> = .never(source: "tygl.buct.edu.cn", parserVersion: 1)
    public var courseSelectionSlice: DomainSlice<CourseSelectionSnapshot> = .never(source: "jwglxt.xsxk", parserVersion: 1)
    public var courseWishlist: [CourseSelectionWishlistItem] = []

    public var isSyncingSchedule = false
    public var isSyncingGrades = false
    public var isSyncingExams = false
    public var isSyncingCalendar = false
    public var isSyncingJwNotice = false
    public var isSyncingPortal = false
    public var isSyncingTheol = false
    public var isSyncingMail = false
    public var isSyncingElectricity = false
    public var isSyncingCampusNet = false
    public var isSyncingCard = false
    public var isSyncingScs = false
    public var isSyncingSjcx = false
    public var isSyncingTygl = false
    public var isSyncingCourseSelection = false

    public let containerMode: ContainerMode
    public let edition: String
    public let appVersion: String
    public let buildNumber: String
    public let electricitySignSecret: String

    public let syncService: AcademicSyncService
    public let campusSync: CampusDomainSyncService
    public let reminderService = LocalReminderService()
    private let preferences: PreferencesStore
    private let umamiTracker: UmamiTracker
    private var didBootstrap = false

    public init() {
        let resolved = AppContainerResolver.resolveRootDirectory()
        self.containerMode = resolved.mode
        let prefs = PreferencesStore(rootDirectory: resolved.url)
        self.preferences = prefs
        self.umamiTracker = UmamiTracker(preferences: prefs)
        let vault = SessionVaultStore()
        let academic = AcademicSyncService(
            preferences: prefs,
            sessionVault: vault,
            dataStore: AcademicDataStore(rootDirectory: resolved.url)
        )
        self.syncService = academic
        self.campusSync = CampusDomainSyncService(
            sessionVault: vault,
            dataStore: CampusDomainDataStore(rootDirectory: resolved.url),
            silentRelogin: academic.sharedSilentRelogin
        )

        let info = Bundle.main.infoDictionary ?? [:]
        self.edition = (info["BUCTEdition"] as? String) ?? "standard"
        self.appVersion = (info["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        self.buildNumber = (info["CFBundleVersion"] as? String) ?? "5"
        let rawSecret = (info["BUCTElectricitySignSecret"] as? String) ?? ""
        self.electricitySignSecret = rawSecret.hasPrefix("$(") ? "" : rawSecret
    }

    public var preferredColorScheme: ColorScheme? {
        switch appearance.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    public var editionLabel: String {
        edition == "widgets" ? "完整小组件版 (com.buct.one.full)" : "标准无扩展版 (com.buct.one)"
    }

    public var firstWeekMonday: String {
        calendarPrefs.semesterStartMondays[selectedTerm.id]
            ?? ScheduleDates.defaultSemesterStartMonday(for: selectedTerm)
    }

    public var currentTeachingWeek: Int? {
        ScheduleDates.weekAt(firstWeekMonday: firstWeekMonday)
    }

    public var allScheduleCourses: [ScheduleCourse] {
        (scheduleSlice.data ?? []) + customCourses
    }

    public var allExams: [ExamItem] {
        ((examsSlice.data ?? []) + customExams).sorted { a, b in
            if a.examTime.isEmpty != b.examTime.isEmpty { return !a.examTime.isEmpty }
            return a.examTime < b.examTime
        }
    }

    public func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        appearance = await preferences.loadAppearanceConfig()
        dashboardLayout = await preferences.loadDashboardLayout()
        reminderConfig = await preferences.loadReminderConfig()
        currentProfile = await syncService.restoreActiveProfile()

        if let profile = currentProfile {
            await loadLocalData(for: profile)
            if !profile.isDemoMode {
                await umamiTracker.trackDailyLaunchIfNeeded(
                    appVersion: appVersion,
                    buildNumber: buildNumber,
                    screenSize: screenSizeText
                )
            }
        } else {
            await umamiTracker.trackDailyLaunchIfNeeded(
                appVersion: appVersion,
                buildNumber: buildNumber,
                screenSize: screenSizeText
            )
        }
    }

    public func completeLogin(profile: UserAccountProfile) async {
        currentProfile = profile
        showLoginSheet = false
        if profile.systemType == .graduateGmis {
            availableTerms = await syncService.fetchGraduateTerms(profile: profile)
            selectedTerm = availableTerms.first ?? AcademicTerm.calendarDefault()
        } else {
            availableTerms = AcademicTerm.undergradPickerTerms()
            selectedTerm = AcademicTerm.calendarDefault()
        }
        await loadLocalData(for: profile)
        await refreshAllData(userInitiated: true)
    }

    public func enterDemoMode() async {
        let profile = await syncService.startDemoMode()
        currentProfile = profile
        showLoginSheet = false
        availableTerms = AcademicTerm.undergradPickerTerms()
        selectedTerm = DemoData.currentTerm
        await loadLocalData(for: profile)
        selectedWeek = 13
    }

    public func logout(clearSavedCredential: Bool = false) async {
        await syncService.logout(clearSavedCredential: clearSavedCredential)
        await reminderService.clearAllReminders()
        currentProfile = nil
        scheduleSlice = .never(source: "academic_schedule", parserVersion: 1)
        customCourses = []
        semesterGradesSlice = .never(source: "academic_grades", parserVersion: 1)
        overallAcademicSlice = .never(source: "academic_overall", parserVersion: 1)
        examsSlice = .never(source: "academic_exams", parserVersion: 1)
        customExams = []
        calendarSlice = .never(source: "portal_calendar", parserVersion: 2)
        jwNoticeSlice = .never(source: "jwglxt.buct.edu.cn", parserVersion: 1)
        portalNewsSlice = .never(source: "mnews.buct.edu.cn", parserVersion: 2)
        portalLibrarySlice = .never(source: "i.buct.edu.cn", parserVersion: 2)
        theolSlice = .never(source: "theol.homework", parserVersion: 7)
        localTodos = []
        theolFilterPrefs = TheolFilterPrefs()
        mailSlice = .never(source: "mail.buct.edu.cn", parserVersion: 2)
        electricitySlice = .never(source: "ele.buct.one", parserVersion: 1)
        electricityConsentGranted = false
        campusNetSlice = .never(source: "tree.buct.edu.cn", parserVersion: 2)
        cardSlice = .never(source: "ecard.buct.edu.cn", parserVersion: 3)
        hasCardCredential = false
        scsSlice = .never(source: "scs.buct.edu.cn", parserVersion: 2)
        sjcxSlice = .never(source: "sjcx.buct.edu.cn", parserVersion: 2)
        tyglSlice = .never(source: "tygl.buct.edu.cn", parserVersion: 1)
        courseSelectionSlice = .never(source: "jwglxt.xsxk", parserVersion: 1)
        courseWishlist = []
    }

    public func loadLocalData(for profile: UserAccountProfile) async {
        calendarPrefs = await preferences.loadCalendarPrefs(accountKey: profile.accountKey)
        if let savedTermId = calendarPrefs.selectedTermId,
           let matched = availableTerms.first(where: { $0.id == savedTermId }) ?? AcademicTerm(termId: savedTermId) {
            selectedTerm = matched
        } else if profile.isDemoMode {
            selectedTerm = DemoData.currentTerm
        }

        scheduleSlice = await syncService.loadCachedSchedule(profile: profile, term: selectedTerm)
        customCourses = await syncService.loadCustomCourses(profile: profile, term: selectedTerm)
        semesterGradesSlice = await syncService.loadCachedSemesterGrades(profile: profile, term: selectedTerm)
        overallAcademicSlice = await syncService.loadCachedOverallAcademic(profile: profile)
        examsSlice = await syncService.loadCachedExams(profile: profile, term: selectedTerm)
        customExams = await syncService.loadCustomExams(profile: profile)
        calendarSlice = await syncService.loadCachedCalendar(profile: profile)
        jwNoticeSlice = await campusSync.loadCachedJwNotice(profile: profile)
        portalNewsSlice = await campusSync.loadCachedPortalNews(profile: profile)
        portalLibrarySlice = await campusSync.loadCachedPortalLibrary(profile: profile)
        theolSlice = await campusSync.loadCachedTheol(profile: profile)
        localTodos = await campusSync.loadLocalTodos(profile: profile)
        theolFilterPrefs = await campusSync.loadTheolFilterPrefs(profile: profile)
        mailSlice = await campusSync.loadCachedMail(profile: profile)
        electricityConsentGranted = await campusSync.loadElectricityConsent(profile: profile)
        electricitySlice = await campusSync.loadCachedElectricity(profile: profile)
        campusNetSlice = await campusSync.loadCachedCampusNet(profile: profile)
        cardSlice = await campusSync.loadCachedCard(profile: profile)
        hasCardCredential = await campusSync.hasSavedCardCredential(profile: profile)
        scsSlice = await campusSync.loadCachedScs(profile: profile)
        sjcxSlice = await campusSync.loadCachedSjcx(profile: profile)
        tyglSlice = await campusSync.loadCachedTygl(profile: profile)
        courseSelectionSlice = await campusSync.loadCachedCourseSelection(profile: profile)
        courseWishlist = await campusSync.loadCourseWishlist(profile: profile)

        selectedWeek = currentTeachingWeek ?? 1
        await syncService.updateTodayWidgetSnapshot(
            courses: allScheduleCourses,
            term: selectedTerm,
            firstWeekMonday: firstWeekMonday
        )
    }

    public func refreshAllData(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshSchedule(userInitiated: userInitiated) }
            group.addTask { await self.refreshGrades(userInitiated: userInitiated) }
            group.addTask { await self.refreshExams(userInitiated: userInitiated) }
            if profile.systemType == .undergradJwglxt {
                group.addTask { await self.calibrateOfficialCalendar(forceOverrideManual: false) }
            }
        }
    }

    public func refreshSchedule(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingSchedule = true
        defer { isSyncingSchedule = false }

        scheduleSlice = await syncService.syncSchedule(profile: profile, term: selectedTerm, userInitiated: userInitiated)
        await syncService.updateTodayWidgetSnapshot(
            courses: allScheduleCourses,
            term: selectedTerm,
            firstWeekMonday: firstWeekMonday
        )
        await rescheduleReminders()
    }

    public func refreshGrades(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingGrades = true
        defer { isSyncingGrades = false }

        async let semTask = syncService.syncSemesterGrades(profile: profile, term: selectedTerm, userInitiated: userInitiated)
        async let overallTask = syncService.syncOverallAcademic(profile: profile, userInitiated: userInitiated)
        semesterGradesSlice = await semTask
        overallAcademicSlice = await overallTask
    }

    public func refreshExams(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingExams = true
        defer { isSyncingExams = false }

        examsSlice = await syncService.syncExams(profile: profile, term: selectedTerm, userInitiated: userInitiated)
        await rescheduleReminders()
    }

    public func calibrateOfficialCalendar(forceOverrideManual: Bool) async {
        guard let profile = currentProfile else { return }
        isSyncingCalendar = true
        defer { isSyncingCalendar = false }

        calendarSlice = await syncService.syncOfficialCalendar(
            profile: profile,
            forceOverrideManual: forceOverrideManual
        )
        calendarPrefs = await preferences.loadCalendarPrefs(accountKey: profile.accountKey)
        if let cw = currentTeachingWeek {
            selectedWeek = cw
        }
        await syncService.updateTodayWidgetSnapshot(
            courses: allScheduleCourses,
            term: selectedTerm,
            firstWeekMonday: firstWeekMonday
        )
        await rescheduleReminders()
    }

    public func setManualSemesterStart(_ date: Date) async {
        guard let profile = currentProfile else { return }
        let formatted = ScheduleDates.formatUTCDate(date)
        guard let monday = ScheduleDates.normalizeFirstWeekMonday(formatted) else { return }
        var prefs = calendarPrefs
        prefs.manualOverrideTerms.insert(selectedTerm.id)
        prefs.semesterStartMondays[selectedTerm.id] = monday
        calendarPrefs = prefs
        try? await preferences.saveCalendarPrefs(prefs, accountKey: profile.accountKey)
        selectedWeek = currentTeachingWeek ?? 1
        await syncService.updateTodayWidgetSnapshot(
            courses: allScheduleCourses,
            term: selectedTerm,
            firstWeekMonday: firstWeekMonday
        )
        await rescheduleReminders()
    }

    public func selectTerm(_ term: AcademicTerm) async {
        selectedTerm = term
        guard let profile = currentProfile else { return }
        var prefs = calendarPrefs
        prefs.selectedTermId = term.id
        calendarPrefs = prefs
        try? await preferences.saveCalendarPrefs(prefs, accountKey: profile.accountKey)
        await loadLocalData(for: profile)
    }

    public func addCustomCourse(_ course: ScheduleCourse) async {
        guard let profile = currentProfile else { return }
        customCourses.append(course)
        try? await syncService.saveCustomCourses(customCourses, profile: profile, term: selectedTerm)
        await syncService.updateTodayWidgetSnapshot(
            courses: allScheduleCourses,
            term: selectedTerm,
            firstWeekMonday: firstWeekMonday
        )
        await rescheduleReminders()
    }

    public func deleteCustomCourse(id: String) async {
        guard let profile = currentProfile else { return }
        customCourses.removeAll { $0.id == id }
        try? await syncService.saveCustomCourses(customCourses, profile: profile, term: selectedTerm)
        await syncService.updateTodayWidgetSnapshot(
            courses: allScheduleCourses,
            term: selectedTerm,
            firstWeekMonday: firstWeekMonday
        )
        await rescheduleReminders()
    }

    public func addCustomExam(_ exam: ExamItem) async {
        guard let profile = currentProfile else { return }
        customExams.append(exam)
        try? await syncService.saveCustomExams(customExams, profile: profile)
        await rescheduleReminders()
    }

    public func deleteCustomExam(id: String) async {
        guard let profile = currentProfile else { return }
        customExams.removeAll { $0.id == id }
        try? await syncService.saveCustomExams(customExams, profile: profile)
        await rescheduleReminders()
    }

    public func updateReminderConfig(_ config: ReminderConfig) async {
        reminderConfig = config
        try? await preferences.saveReminderConfig(config)
        await rescheduleReminders()
    }

    public func rescheduleReminders() async {
        await reminderService.reschedule(
            courses: allScheduleCourses,
            exams: allExams,
            books: portalLibrarySlice.data?.books ?? [],
            homeworks: theolSlice.data?.homeworks ?? [],
            firstWeekMonday: firstWeekMonday,
            config: reminderConfig,
            isDemoMode: currentProfile?.isDemoMode ?? true
        )
    }

    // MARK: - M2-1 同步与操作

    public var visiblePendingTodoCount: Int {
        let hwCount = (theolSlice.data?.homeworks ?? []).filter {
            $0.canSubmit && !theolFilterPrefs.hiddenHomeworkIds.contains($0.id)
        }.count
        let testCount = (theolSlice.data?.tests ?? []).filter {
            $0.canStart && !theolFilterPrefs.hiddenTestKeys.contains($0.id)
        }.count
        let localCount = localTodos.filter { !$0.completed }.count
        return hwCount + testCount + localCount
    }

    public func refreshJwNotice(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingJwNotice = true
        defer { isSyncingJwNotice = false }
        jwNoticeSlice = await campusSync.syncJwNotice(profile: profile, userInitiated: userInitiated)
    }

    public func markJwReminderRead(id: String) async {
        guard let profile = currentProfile else { return }
        await campusSync.markJwReminderRead(profile: profile, id: id)
        if var snap = jwNoticeSlice.data {
            snap.reminders = snap.reminders.map { item in
                var copy = item
                if copy.id == id { copy.isRead = true }
                return copy
            }
            jwNoticeSlice = DomainSlice(data: snap, provenance: jwNoticeSlice.provenance)
        }
    }

    public func markJwAnnouncementRead(id: String) async {
        guard let profile = currentProfile else { return }
        await campusSync.markJwAnnouncementRead(profile: profile, id: id)
        if var snap = jwNoticeSlice.data {
            snap.announcements = snap.announcements.map { item in
                var copy = item
                if copy.id == id { copy.isRead = true }
                return copy
            }
            jwNoticeSlice = DomainSlice(data: snap, provenance: jwNoticeSlice.provenance)
        }
    }

    public func refreshPortal(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingPortal = true
        defer { isSyncingPortal = false }
        async let newsTask = campusSync.syncPortalNews(profile: profile, userInitiated: userInitiated)
        async let libTask = campusSync.syncPortalLibrary(profile: profile, userInitiated: userInitiated)
        portalNewsSlice = await newsTask
        portalLibrarySlice = await libTask
        await rescheduleReminders()
    }

    public func refreshTheol(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingTheol = true
        theolSlice = await campusSync.syncTheolPhase1(profile: profile, userInitiated: userInitiated)
        isSyncingTheol = false
        await rescheduleReminders()

        if !profile.isDemoMode && profile.systemType == .undergradJwglxt {
            Task {
                let updated = await campusSync.syncTheolPhase2Courses(profile: profile)
                self.theolSlice = updated
                await self.rescheduleReminders()
            }
        }
    }

    public func addLocalTodo(_ todo: LocalTodoItem) async {
        guard let profile = currentProfile else { return }
        localTodos.insert(todo, at: 0)
        await campusSync.saveLocalTodos(localTodos, profile: profile)
    }

    public func toggleLocalTodo(id: String) async {
        guard let profile = currentProfile,
              let idx = localTodos.firstIndex(where: { $0.id == id }) else { return }
        localTodos[idx].completed.toggle()
        await campusSync.saveLocalTodos(localTodos, profile: profile)
    }

    public func deleteLocalTodo(id: String) async {
        guard let profile = currentProfile else { return }
        localTodos.removeAll { $0.id == id }
        await campusSync.saveLocalTodos(localTodos, profile: profile)
    }

    public func hideTheolHomework(id: String) async {
        guard let profile = currentProfile else { return }
        theolFilterPrefs.hiddenHomeworkIds.insert(id)
        await campusSync.saveTheolFilterPrefs(theolFilterPrefs, profile: profile)
    }

    public func hideTheolTest(key: String) async {
        guard let profile = currentProfile else { return }
        theolFilterPrefs.hiddenTestKeys.insert(key)
        await campusSync.saveTheolFilterPrefs(theolFilterPrefs, profile: profile)
    }

    public func refreshMail(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingMail = true
        defer { isSyncingMail = false }
        mailSlice = await campusSync.syncMail(profile: profile, userInitiated: userInitiated)
    }

    public func setElectricityConsent(_ granted: Bool) async {
        guard let profile = currentProfile else { return }
        await campusSync.setElectricityConsent(granted, profile: profile)
        electricityConsentGranted = granted
        electricitySlice = await campusSync.loadCachedElectricity(profile: profile)
    }

    public func saveElectricityTargets(_ targets: [ElectricityRoomTarget], threshold: Double? = nil) async {
        guard let profile = currentProfile else { return }
        electricitySlice = await campusSync.updateElectricityTargets(targets, threshold: threshold, profile: profile)
        if !targets.isEmpty && electricityConsentGranted {
            await refreshElectricity()
        }
    }

    public func refreshElectricity() async {
        guard let profile = currentProfile else { return }
        isSyncingElectricity = true
        defer { isSyncingElectricity = false }
        electricitySlice = await campusSync.syncElectricity(
            profile: profile,
            signSecret: electricitySignSecret,
            appVersion: appVersion
        )
    }

    public func refreshCampusNet(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingCampusNet = true
        defer { isSyncingCampusNet = false }
        campusNetSlice = await campusSync.syncCampusNet(
            profile: profile,
            appVersion: appVersion,
            userInitiated: userInitiated
        )
    }

    public func loginAndSyncCard(idSerial: String, password: String, startDate: String, endDate: String) async throws {
        guard let profile = currentProfile else { return }
        isSyncingCard = true
        defer { isSyncingCard = false }
        cardSlice = try await campusSync.loginAndSyncCard(
            profile: profile,
            idSerial: idSerial,
            password: password,
            startDate: startDate,
            endDate: endDate
        )
        hasCardCredential = await campusSync.hasSavedCardCredential(profile: profile)
    }

    public func refreshCard(startDate: String, endDate: String) async {
        guard let profile = currentProfile else { return }
        isSyncingCard = true
        defer { isSyncingCard = false }
        cardSlice = await campusSync.syncCard(profile: profile, startDate: startDate, endDate: endDate)
        hasCardCredential = await campusSync.hasSavedCardCredential(profile: profile)
    }

    public func logoutCard() async {
        guard let profile = currentProfile else { return }
        await campusSync.logoutCard(profile: profile)
        hasCardCredential = false
    }

    public func refreshScs(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingScs = true
        defer { isSyncingScs = false }
        scsSlice = await campusSync.syncScs(profile: profile, userInitiated: userInitiated)
    }

    public func refreshSjcx(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingSjcx = true
        defer { isSyncingSjcx = false }
        sjcxSlice = await campusSync.syncSjcx(profile: profile, userInitiated: userInitiated)
    }

    public func refreshTygl(userInitiated: Bool = true) async {
        guard let profile = currentProfile else { return }
        isSyncingTygl = true
        defer { isSyncingTygl = false }
        tyglSlice = await campusSync.syncTygl(profile: profile, userInitiated: userInitiated)
    }

    public func refreshCourseSelection(onlyWithSeats: Bool = false, keyword: String = "") async {
        guard let profile = currentProfile else { return }
        isSyncingCourseSelection = true
        defer { isSyncingCourseSelection = false }
        courseSelectionSlice = await campusSync.syncCourseSelection(
            profile: profile,
            onlyWithSeats: onlyWithSeats,
            keyword: keyword
        )
    }

    public func addToCourseWishlist(_ item: CourseSelectionWishlistItem) async {
        guard let profile = currentProfile else { return }
        if !courseWishlist.contains(where: { $0.courseId == item.courseId && $0.classId == item.classId }) {
            courseWishlist.append(item)
            await campusSync.saveCourseWishlist(courseWishlist, profile: profile)
        }
    }

    public func removeFromCourseWishlist(id: String) async {
        guard let profile = currentProfile else { return }
        courseWishlist.removeAll { $0.id == id }
        await campusSync.saveCourseWishlist(courseWishlist, profile: profile)
    }

    public func moveCourseWishlist(from offsets: IndexSet, to destination: Int) async {
        guard let profile = currentProfile else { return }
        courseWishlist.move(fromOffsets: offsets, toOffset: destination)
        await campusSync.saveCourseWishlist(courseWishlist, profile: profile)
    }

    public func updateAppearance(_ newConfig: AppearanceConfig) {
        let previousUmami = appearance.umamiEnabled
        appearance = newConfig
        Task {
            try? await preferences.saveAppearanceConfig(newConfig)
            if previousUmami && !newConfig.umamiEnabled {
                await umamiTracker.resetSessionCache()
            }
        }
    }

    public func saveDashboardLayout(_ layout: DashboardLayout) {
        dashboardLayout = layout
        Task {
            try? await preferences.saveDashboardLayout(layout)
        }
    }

    public func trackVisit(path: String, title: String) {
        guard currentProfile?.isDemoMode != true else { return }
        Task {
            await umamiTracker.trackPageVisit(
                urlPath: path,
                title: title,
                appVersion: appVersion,
                buildNumber: buildNumber,
                screenSize: screenSizeText
            )
        }
    }
}
