import BuctModel
import BuctNetwork
import BuctSources
import BuctStore
import Foundation

public enum LoginFlowState: Sendable {
    case authenticated(UserAccountProfile)
    case captchaRequired(imageData: Data, message: String)
    case secondarySmsRequired(maskedPhone: String)
    case invalidCredentials
    case failure(message: String)
}

public actor AcademicSyncService {
    private let preferences: PreferencesStore
    private let sessionVault: SessionVaultStore
    private let dataStore: AcademicDataStore
    private let ssoClient: BuctSsoAuthClient
    private let webAuthnClient: BuctWebAuthnClient
    private let jwglxtClient: JwglxtClient
    private let gmisClient: GmisClient
    private let portalClient: PortalCalendarClient
    private let silentRelogin: SsoSilentRelogin
    public nonisolated let sharedSilentRelogin: SsoSilentRelogin
    private let singleFlight = SingleFlightCoordinator()

    private var didConfigureWebVpn = false

    public init(
        preferences: PreferencesStore,
        sessionVault: SessionVaultStore = SessionVaultStore(),
        dataStore: AcademicDataStore? = nil,
        silentRelogin: SsoSilentRelogin? = nil
    ) {
        self.preferences = preferences
        self.sessionVault = sessionVault
        self.dataStore = dataStore ?? AcademicDataStore()
        let auth = BuctSsoAuthClient()
        self.ssoClient = auth
        self.webAuthnClient = BuctWebAuthnClient()
        self.jwglxtClient = JwglxtClient()
        self.gmisClient = GmisClient()
        self.portalClient = PortalCalendarClient()
        let relogin = silentRelogin ?? SsoSilentRelogin(sessionVault: sessionVault, authClient: auth)
        self.silentRelogin = relogin
        self.sharedSilentRelogin = relogin
    }

    public func ensureConfigured() async {
        guard !didConfigureWebVpn else { return }
        didConfigureWebVpn = true
        let vault = self.sessionVault
        let prefs = self.preferences
        await BuctWebVpnManager.shared.configure(
            readSidCookies: { await vault.loadSession().sidCookies },
            saveSidCookies: { raw in await vault.saveSidPortalCookies(raw) },
            readSavedCredentials: {
                let profile = await prefs.loadProfile()
                if profile?.isDemoMode == true { return nil }
                guard let cred = await vault.loadCredential(),
                      cred.systemType == .undergradJwglxt else {
                    return nil
                }
                return (cred.username, cred.password)
            },
            readVpnTicket: { await vault.loadSession().vpnTicket },
            saveVpnTicket: { ticket in await vault.saveVpnTicket(ticket) }
        )
    }

    // MARK: - 会话与登录

    public func restoreActiveProfile() async -> UserAccountProfile? {
        await ensureConfigured()
        return await preferences.loadProfile()
    }

    public func startDemoMode() async -> UserAccountProfile {
        await ensureConfigured()
        let profile = DemoData.profile
        try? await preferences.saveProfile(profile)
        return profile
    }

    public func logout(clearSavedCredential: Bool = false) async {
        await ensureConfigured()
        await ssoClient.clearSensitiveState()
        await sessionVault.clearSession()
        if clearSavedCredential {
            await sessionVault.clearCredential()
        }
        await BuctWebVpnManager.shared.clearSession()
        await preferences.clearProfile()
    }

    public func hasPasskey(username: String) -> Bool {
        BuctSoftwarePasskey.hasCredential(username: username)
    }

    public func clearPasskey(username: String) {
        BuctSoftwarePasskey.clearCredential(username: username)
    }

    public func loadSavedCredential() async -> SavedLoginCredential? {
        await sessionVault.loadCredential()
    }

    public func loginUndergrad(
        username: String,
        password: String,
        saveCredential: Bool
    ) async -> LoginFlowState {
        await ensureConfigured()
        let outcome = await ssoClient.login(username: username, password: password, mode: .teaching)
        return await handleUndergradAuthOutcome(
            outcome,
            username: username,
            password: password,
            saveCredential: saveCredential
        )
    }

    public func submitUndergradCaptcha(
        _ code: String,
        username: String,
        password: String,
        saveCredential: Bool
    ) async -> LoginFlowState {
        let outcome = await ssoClient.submitCaptcha(code)
        return await handleUndergradAuthOutcome(
            outcome,
            username: username,
            password: password,
            saveCredential: saveCredential
        )
    }

    public func refreshUndergradCaptcha() async -> Data? {
        await ssoClient.refreshCaptcha()
    }

    public func prepareSecondarySmsCaptcha() async -> Result<Data, Error> {
        await ssoClient.prepareSecondarySmsCaptcha()
    }

    public func sendSecondarySmsCode(captchaCode: String) async -> Result<Int, Error> {
        await ssoClient.sendSecondarySmsCode(captchaCode: captchaCode)
    }

    public func submitSecondarySmsCode(
        smsCode: String,
        rememberDevice: Bool,
        username: String,
        password: String,
        saveCredential: Bool
    ) async -> LoginFlowState {
        let outcome = await ssoClient.submitSecondarySmsCode(smsCode: smsCode, rememberDevice: rememberDevice)
        return await handleUndergradAuthOutcome(
            outcome,
            username: username,
            password: password,
            saveCredential: saveCredential
        )
    }

    public func loginWithPasskey(username: String) async -> LoginFlowState {
        await ensureConfigured()
        let outcome = await webAuthnClient.authenticate(username: username)
        return await handleUndergradAuthOutcome(
            outcome,
            username: username,
            password: "",
            saveCredential: false
        )
    }

    public func registerPasskey(username: String, password: String) async -> Result<Void, Error> {
        await ensureConfigured()
        let outcome = await ssoClient.login(username: username, password: password, mode: .sidPortalOnly)
        switch outcome {
        case .success(_, let sidCookie, _):
            guard !sidCookie.isEmpty else {
                return .failure(NSError(domain: "AcademicSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "未获取到统一身份认证会话"]))
            }
            await sessionVault.saveSidPortalCookies(sidCookie)
            return await webAuthnClient.registerPasskey(username: username, sidCookie: sidCookie)
        case .invalidCredentials:
            return .failure(NSError(domain: "AcademicSync", code: 401, userInfo: [NSLocalizedDescriptionKey: "学号或密码错误"]))
        case .captchaRequired:
            return .failure(NSError(domain: "AcademicSync", code: -2, userInfo: [NSLocalizedDescriptionKey: "当前需要验证码，请先退出后通过密码登录一次再注册通行密钥"]))
        case .secondarySmsRequired:
            return .failure(NSError(domain: "AcademicSync", code: -3, userInfo: [NSLocalizedDescriptionKey: "当前需要短信二次验证，请先完成一次登录"]))
        case .failure(let msg):
            return .failure(NSError(domain: "AcademicSync", code: -4, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
    }

    private func handleUndergradAuthOutcome(
        _ outcome: BuctSsoAuthOutcome,
        username: String,
        password: String,
        saveCredential: Bool
    ) async -> LoginFlowState {
        switch outcome {
        case .success(let jwCookie, let sidCookie, _):
            await sessionVault.saveJwglxtCookies(jwCookie)
            await sessionVault.saveSidPortalCookies(sidCookie)
            if saveCredential && !password.isEmpty {
                await sessionVault.saveCredential(
                    SavedLoginCredential(username: username, password: password, systemType: .undergradJwglxt)
                )
            }
            await silentRelogin.resetCooldown()
            let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let fetched = try? await jwglxtClient.validateAndFetchProfile(cookie: jwCookie, fallbackId: cleanUser)
            let profile = UserAccountProfile(
                studentId: fetched?.studentId ?? cleanUser,
                studentName: fetched?.name ?? cleanUser,
                systemType: .undergradJwglxt
            )
            try? await preferences.saveProfile(profile)
            return .authenticated(profile)

        case .captchaRequired(let data, let msg):
            return .captchaRequired(imageData: data, message: msg)
        case .secondarySmsRequired(let phone):
            return .secondarySmsRequired(maskedPhone: phone)
        case .invalidCredentials:
            return .invalidCredentials
        case .failure(let msg):
            return .failure(message: msg)
        }
    }

    // MARK: - 研究生登录

    public func fetchGmisChallenge() async throws -> Data {
        await ensureConfigured()
        return try await gmisClient.fetchLoginChallenge().captchaImageData
    }

    public func loginGraduate(
        username: String,
        password: String,
        captcha: String
    ) async -> Result<UserAccountProfile, Error> {
        await ensureConfigured()
        do {
            let (cookie, profile) = try await gmisClient.submitLogin(
                username: username,
                password: password,
                captcha: captcha
            )
            await sessionVault.saveGmisCookies(cookie)
            try? await preferences.saveProfile(profile)
            return .success(profile)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - WebVPN 状态

    public func webVpnStatus() async -> BuctWebVpnStatus {
        await ensureConfigured()
        return await BuctWebVpnManager.shared.statusSnapshot()
    }

    public func resetWebVpnSession() async {
        await BuctWebVpnManager.shared.clearSession()
        await sessionVault.clearVpnTicket()
    }

    // MARK: - 课表（本地切片 + 网络同步 + 自定义课程）

    public func loadCachedSchedule(profile: UserAccountProfile, term: AcademicTerm) async -> DomainSlice<[ScheduleCourse]> {
        if profile.isDemoMode {
            return DomainSlice(
                data: DemoData.scheduleCourses(),
                provenance: Provenance(source: "demo", capturedAt: Int64(Date().timeIntervalSince1970 * 1000), parserVersion: 1, refreshState: .fresh)
            )
        }
        let store = await dataStore.scheduleStore(accountKey: profile.accountKey, termId: term.id)
        return await store.load()
    }

    public func loadCustomCourses(profile: UserAccountProfile, term: AcademicTerm) async -> [ScheduleCourse] {
        if profile.isDemoMode { return [] }
        return await dataStore.loadCustomCourses(accountKey: profile.accountKey, termId: term.id)
    }

    public func saveCustomCourses(_ courses: [ScheduleCourse], profile: UserAccountProfile, term: AcademicTerm) async throws {
        guard !profile.isDemoMode else { return }
        try await dataStore.saveCustomCourses(courses, accountKey: profile.accountKey, termId: term.id)
    }

    public func syncSchedule(profile: UserAccountProfile, term: AcademicTerm, userInitiated: Bool = true) async -> DomainSlice<[ScheduleCourse]> {
        if profile.isDemoMode {
            return await loadCachedSchedule(profile: profile, term: term)
        }
        await ensureConfigured()
        let store = await dataStore.scheduleStore(accountKey: profile.accountKey, termId: term.id)
        let key = "schedule::\(profile.accountKey)::\(term.id)"

        do {
            try await singleFlight.run(key: key) { [self] in
                let courses = try await performWithRelogin(profile: profile, userInitiated: userInitiated) {
                    switch profile.systemType {
                    case .undergradJwglxt:
                        let cookie = await sessionVault.loadSession().jwglxtCookies
                        return try await jwglxtClient.fetchSchedule(term: term, cookie: cookie)
                    case .graduateGmis:
                        let cookie = await sessionVault.loadSession().gmisCookies
                        let termCode: String
                        if let sc = term.serverCode, !sc.isEmpty {
                            termCode = sc
                        } else {
                            let terms = try await gmisClient.fetchTerms(cookie: cookie)
                            termCode = terms.first(where: { $0.id == term.id })?.serverCode ?? terms.first?.serverCode ?? ""
                        }
                        return try await gmisClient.fetchSchedule(termCode: termCode, cookie: cookie)
                    case .demo:
                        return DemoData.scheduleCourses()
                    }
                }
                try await store.saveSuccess(data: courses, isEmpty: courses.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func fetchGraduateTerms(profile: UserAccountProfile) async -> [AcademicTerm] {
        guard profile.systemType == .graduateGmis else {
            return AcademicTerm.undergradPickerTerms()
        }
        let cookie = await sessionVault.loadSession().gmisCookies
        return (try? await gmisClient.fetchTerms(cookie: cookie)) ?? [AcademicTerm.calendarDefault()]
    }

    // MARK: - 成绩与培养方案

    public func loadCachedSemesterGrades(profile: UserAccountProfile, term: AcademicTerm) async -> DomainSlice<[GradeItem]> {
        if profile.isDemoMode {
            let demo = DemoData.overallBundle().grades.filter { $0.year == term.xnm && $0.term == term.xqm }
            return DomainSlice(
                data: demo,
                provenance: Provenance(source: "demo", capturedAt: Int64(Date().timeIntervalSince1970 * 1000), parserVersion: 1, refreshState: demo.isEmpty ? .emptyConfirmed : .fresh)
            )
        }
        let store = await dataStore.semesterGradesStore(accountKey: profile.accountKey, termId: term.id)
        return await store.load()
    }

    public func syncSemesterGrades(profile: UserAccountProfile, term: AcademicTerm, userInitiated: Bool = true) async -> DomainSlice<[GradeItem]> {
        if profile.isDemoMode {
            return await loadCachedSemesterGrades(profile: profile, term: term)
        }
        await ensureConfigured()
        let store = await dataStore.semesterGradesStore(accountKey: profile.accountKey, termId: term.id)
        let key = "grades::\(profile.accountKey)::\(term.id)"

        do {
            try await singleFlight.run(key: key) { [self] in
                let items = try await performWithRelogin(profile: profile, userInitiated: userInitiated) {
                    switch profile.systemType {
                    case .undergradJwglxt:
                        let cookie = await sessionVault.loadSession().jwglxtCookies
                        return try await jwglxtClient.fetchSemesterGrades(term: term, cookie: cookie)
                    case .graduateGmis:
                        let cookie = await sessionVault.loadSession().gmisCookies
                        return try await gmisClient.fetchGrades(cookie: cookie, currentTerm: term).grades
                    case .demo:
                        return DemoData.overallBundle().grades
                    }
                }
                try await store.saveSuccess(data: items, isEmpty: items.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    public func loadCachedOverallAcademic(profile: UserAccountProfile) async -> DomainSlice<OverallAcademicBundle> {
        if profile.isDemoMode {
            return DomainSlice(
                data: DemoData.overallBundle(),
                provenance: Provenance(source: "demo", capturedAt: Int64(Date().timeIntervalSince1970 * 1000), parserVersion: 1, refreshState: .fresh)
            )
        }
        let store = await dataStore.overallAcademicStore(accountKey: profile.accountKey)
        return await store.load()
    }

    public func syncOverallAcademic(profile: UserAccountProfile, userInitiated: Bool = true) async -> DomainSlice<OverallAcademicBundle> {
        if profile.isDemoMode {
            return await loadCachedOverallAcademic(profile: profile)
        }
        await ensureConfigured()
        let store = await dataStore.overallAcademicStore(accountKey: profile.accountKey)
        let key = "overall::\(profile.accountKey)"

        do {
            try await singleFlight.run(key: key) { [self] in
                let bundle = try await performWithRelogin(profile: profile, userInitiated: userInitiated) {
                    switch profile.systemType {
                    case .undergradJwglxt:
                        let cookie = await sessionVault.loadSession().jwglxtCookies
                        return try await jwglxtClient.fetchOverallAndCurriculum(cookie: cookie)
                    case .graduateGmis:
                        let cookie = await sessionVault.loadSession().gmisCookies
                        return try await gmisClient.fetchGrades(cookie: cookie, currentTerm: AcademicTerm.calendarDefault())
                    case .demo:
                        return DemoData.overallBundle()
                    }
                }
                try await store.saveSuccess(data: bundle, isEmpty: bundle.grades.isEmpty && bundle.curriculumNodes.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - 考试安排

    public func loadCachedExams(profile: UserAccountProfile, term: AcademicTerm) async -> DomainSlice<[ExamItem]> {
        if profile.isDemoMode {
            return DomainSlice(
                data: DemoData.exams(),
                provenance: Provenance(source: "demo", capturedAt: Int64(Date().timeIntervalSince1970 * 1000), parserVersion: 1, refreshState: .fresh)
            )
        }
        let store = await dataStore.examsStore(accountKey: profile.accountKey, termId: term.id)
        return await store.load()
    }

    public func loadCustomExams(profile: UserAccountProfile) async -> [ExamItem] {
        if profile.isDemoMode { return [] }
        return await dataStore.loadCustomExams(accountKey: profile.accountKey)
    }

    public func saveCustomExams(_ exams: [ExamItem], profile: UserAccountProfile) async throws {
        guard !profile.isDemoMode else { return }
        try await dataStore.saveCustomExams(exams, accountKey: profile.accountKey)
    }

    public func syncExams(profile: UserAccountProfile, term: AcademicTerm, userInitiated: Bool = true) async -> DomainSlice<[ExamItem]> {
        if profile.isDemoMode {
            return await loadCachedExams(profile: profile, term: term)
        }
        if profile.systemType == .graduateGmis {
            let store = await dataStore.examsStore(accountKey: profile.accountKey, termId: term.id)
            if let saved = try? await store.saveSuccess(data: [], isEmpty: true) {
                return saved
            }
            return await store.load()
        }
        await ensureConfigured()
        let store = await dataStore.examsStore(accountKey: profile.accountKey, termId: term.id)
        let key = "exams::\(profile.accountKey)::\(term.id)"

        do {
            try await singleFlight.run(key: key) { [self] in
                let items = try await performWithRelogin(profile: profile, userInitiated: userInitiated) {
                    let cookie = await sessionVault.loadSession().jwglxtCookies
                    return try await jwglxtClient.fetchExams(term: term, cookie: cookie)
                }
                try await store.saveSuccess(data: items, isEmpty: items.isEmpty)
            }
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
        }
        return await store.load()
    }

    // MARK: - 空闲教室

    public func queryEmptyClassrooms(
        profile: UserAccountProfile?,
        term: AcademicTerm,
        campus: EmptyClassroomCampus,
        week: Int,
        day: Int,
        period: Int
    ) async throws -> [EmptyClassroom] {
        if profile?.isDemoMode == true {
            return DemoData.emptyClassrooms(campus: campus)
        }
        guard let profile, profile.systemType == .undergradJwglxt else {
            throw NSError(domain: "AcademicSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "空闲教室查询需先登录本科教务账号"])
        }
        await ensureConfigured()
        return try await performWithRelogin(profile: profile, userInitiated: true) {
            let cookie = await sessionVault.loadSession().jwglxtCookies
            return try await jwglxtClient.fetchEmptyClassrooms(
                term: term,
                campus: campus,
                week: week,
                day: day,
                period: period,
                cookie: cookie
            )
        }
    }

    // MARK: - 官方校历自动校准

    public func loadCachedCalendar(profile: UserAccountProfile?) async -> DomainSlice<OfficialCalendarSnapshot> {
        if profile?.isDemoMode == true {
            return DomainSlice(
                data: DemoData.calendar(),
                provenance: Provenance(source: "demo", capturedAt: Int64(Date().timeIntervalSince1970 * 1000), parserVersion: 2, refreshState: .fresh)
            )
        }
        let store = await dataStore.officialCalendarStore()
        return await store.load()
    }

    public func syncOfficialCalendar(
        profile: UserAccountProfile,
        forceOverrideManual: Bool = false
    ) async -> DomainSlice<OfficialCalendarSnapshot> {
        if profile.isDemoMode {
            return await loadCachedCalendar(profile: profile)
        }
        await ensureConfigured()
        let store = await dataStore.officialCalendarStore()
        let existing = await store.load()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // 12 小时缓存保护
        if !forceOverrideManual,
           existing.provenance.refreshState == .fresh,
           nowMs - existing.provenance.capturedAt < 12 * 3600 * 1000,
           existing.data != nil {
            await applyOfficialCalendar(existing.data!, accountKey: profile.accountKey, forceOverrideManual: false)
            return existing
        }

        do {
            let snapshot = try await performWithRelogin(profile: profile, userInitiated: forceOverrideManual) {
                let sidCookies = await sessionVault.loadSession().sidCookies
                return try await portalClient.fetchOfficialCalendar(sidCookies: sidCookies)
            }
            let saved = try await store.saveSuccess(data: snapshot, isEmpty: snapshot.terms.isEmpty)
            await applyOfficialCalendar(snapshot, accountKey: profile.accountKey, forceOverrideManual: forceOverrideManual)
            return saved
        } catch {
            _ = try? await store.recordFailure(error: error.localizedDescription)
            return await store.load()
        }
    }

    public func applyOfficialCalendar(
        _ snapshot: OfficialCalendarSnapshot,
        accountKey: String,
        forceOverrideManual: Bool
    ) async {
        var prefs = await preferences.loadCalendarPrefs(accountKey: accountKey)
        let termsToApply: [OfficialTermDate]
        if snapshot.terms.isEmpty && !snapshot.beginDate.isEmpty {
            let parsed = AcademicTerm(termId: snapshot.currentTermId) ?? AcademicTerm.calendarDefault()
            termsToApply = [
                OfficialTermDate(
                    wid: "",
                    academicYear: parsed.year,
                    semester: parsed.semester,
                    termId: parsed.id,
                    beginDate: snapshot.beginDate,
                    endDate: snapshot.endDate,
                    isCurrent: true
                )
            ]
        } else {
            termsToApply = snapshot.terms
        }

        for term in termsToApply {
            if forceOverrideManual {
                prefs.manualOverrideTerms.remove(term.termId)
            } else if prefs.manualOverrideTerms.contains(term.termId) {
                continue
            }
            if let normalizedMonday = ScheduleDates.normalizeFirstWeekMonday(term.beginDate) {
                prefs.semesterStartMondays[term.termId] = normalizedMonday
            }
        }
        try? await preferences.saveCalendarPrefs(prefs, accountKey: accountKey)
    }

    public func updateTodayWidgetSnapshot(
        courses: [ScheduleCourse],
        term: AcademicTerm,
        firstWeekMonday: String
    ) async {
        let currentWeek = ScheduleDates.weekAt(firstWeekMonday: firstWeekMonday)
        let dow = ScheduleDates.todayDayOfWeek()
        let dayLabels = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let todayCourses = courses
            .filter { course in
                course.dayOfWeek == dow && (currentWeek == nil || course.weeks.contains(currentWeek!))
            }
            .sorted { $0.startPeriod < $1.startPeriod }
            .map { course in
                TodayWidgetCourseItem(
                    id: course.id,
                    name: course.name,
                    location: course.location,
                    timeRange: BuctTimeSlots.timeRangeText(startPeriod: course.startPeriod, endPeriod: course.endPeriod),
                    startPeriod: course.startPeriod,
                    endPeriod: course.endPeriod
                )
            }

        let snapshot = TodayWidgetSnapshot(
            termDisplay: term.shortLabel,
            currentWeek: currentWeek,
            dayLabel: dayLabels[dow],
            courses: todayCourses,
            updatedAtMillis: Int64(Date().timeIntervalSince1970 * 1000)
        )
        try? await preferences.saveTodayWidgetSnapshot(snapshot)
    }

    private func performWithRelogin<T: Sendable>(
        profile: UserAccountProfile,
        userInitiated: Bool,
        operation: () async throws -> T
    ) async throws -> T {
        let sidBefore = await sessionVault.loadSession().sidCookies
        do {
            return try await operation()
        } catch {
            guard profile.systemType == .undergradJwglxt,
                  SsoSilentRelogin.isAuthFailureMessage(error.localizedDescription) else {
                throw error
            }
            let relogged = await silentRelogin.attemptRelogin(
                sidSnapshotBefore: sidBefore,
                bypassCooldown: userInitiated
            )
            guard relogged else { throw error }
            return try await operation()
        }
    }
}
