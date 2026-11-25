import BuctModel
import Foundation

public struct OfficialCalendarPrefs: Codable, Sendable, Equatable {
    public var manualOverrideTerms: Set<String>
    public var semesterStartMondays: [String: String]
    public var selectedTermId: String?

    public init(
        manualOverrideTerms: Set<String> = [],
        semesterStartMondays: [String: String] = [:],
        selectedTermId: String? = nil
    ) {
        self.manualOverrideTerms = manualOverrideTerms
        self.semesterStartMondays = semesterStartMondays
        self.selectedTermId = selectedTermId
    }
}

public actor PreferencesStore {
    private let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AppContainerResolver.resolveRootDirectory().url
    }

    public func loadDashboardLayout() -> DashboardLayout {
        let url = rootDirectory.appendingPathComponent("dashboard_layout_v2.json")
        guard let data = try? Data(contentsOf: url),
              let layout = try? decoder.decode(DashboardLayout.self, from: data) else {
            return .default
        }
        return layout
    }

    public func saveDashboardLayout(_ layout: DashboardLayout) throws {
        try saveJSON(layout, filename: "dashboard_layout_v2.json")
    }

    public func loadAppearanceConfig() -> AppearanceConfig {
        loadJSON(AppearanceConfig.self, filename: "appearance_config.json") ?? AppearanceConfig()
    }

    public func saveAppearanceConfig(_ config: AppearanceConfig) throws {
        try saveJSON(config, filename: "appearance_config.json")
    }

    public func loadProfile() -> UserAccountProfile? {
        loadJSON(UserAccountProfile.self, filename: "active_profile.json")
    }

    public func saveProfile(_ profile: UserAccountProfile) throws {
        try saveJSON(profile, filename: "active_profile.json")
    }

    public func clearProfile() {
        let url = rootDirectory.appendingPathComponent("active_profile.json")
        try? FileManager.default.removeItem(at: url)
    }

    public func loadReminderConfig() -> ReminderConfig {
        loadJSON(ReminderConfig.self, filename: "reminder_config.json") ?? ReminderConfig()
    }

    public func saveReminderConfig(_ config: ReminderConfig) throws {
        try saveJSON(config, filename: "reminder_config.json")
    }

    public func loadCalendarPrefs(accountKey: String) -> OfficialCalendarPrefs {
        let safeKey = Self.sanitizeKey(accountKey)
        return loadJSON(OfficialCalendarPrefs.self, filename: "calendar_prefs_\(safeKey).json") ?? OfficialCalendarPrefs()
    }

    public func saveCalendarPrefs(_ prefs: OfficialCalendarPrefs, accountKey: String) throws {
        let safeKey = Self.sanitizeKey(accountKey)
        try saveJSON(prefs, filename: "calendar_prefs_\(safeKey).json")
    }

    public func loadTodayWidgetSnapshot() -> TodayWidgetSnapshot? {
        loadJSON(TodayWidgetSnapshot.self, filename: "today_widget_snapshot.json")
    }

    public func saveTodayWidgetSnapshot(_ snapshot: TodayWidgetSnapshot) throws {
        try saveJSON(snapshot, filename: "today_widget_snapshot.json")
    }

    public func getOrCreateInstallID() -> String {
        let url = rootDirectory.appendingPathComponent("umami_install_id")
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: trimmed) != nil {
                return trimmed
            }
        }
        let generated = UUID().uuidString.lowercased()
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? generated.data(using: .utf8)?.write(to: url, options: [.atomic])
        return generated
    }

    public func lastUmamiLaunchDay() -> String? {
        let url = rootDirectory.appendingPathComponent("umami_last_launch_day")
        return try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func saveLastUmamiLaunchDay(_ day: String) {
        let url = rootDirectory.appendingPathComponent("umami_last_launch_day")
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try? day.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, filename: String) -> T? {
        let url = rootDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, filename: String) throws {
        let url = rootDirectory.appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    private static func sanitizeKey(_ key: String) -> String {
        key.replacingOccurrences(of: "[^A-Za-z0-9_\\-]", with: "_", options: .regularExpression)
    }
}
