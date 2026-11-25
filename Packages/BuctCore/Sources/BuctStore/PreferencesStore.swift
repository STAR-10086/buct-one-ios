import BuctModel
import Foundation

public actor PreferencesStore {
    private let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory ?? AppContainerResolver.resolveRootDirectory().url
    }

    public func loadDashboardLayout() -> DashboardLayout {
        let url = rootDirectory.appendingPathComponent("dashboard_layout.json")
        guard let data = try? Data(contentsOf: url),
              let layout = try? decoder.decode(DashboardLayout.self, from: data) else {
            return .default
        }
        return layout
    }

    public func saveDashboardLayout(_ layout: DashboardLayout) throws {
        let url = rootDirectory.appendingPathComponent("dashboard_layout.json")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(layout)
        try data.write(to: url, options: [.atomic])
    }

    public func loadAppearanceConfig() -> AppearanceConfig {
        let url = rootDirectory.appendingPathComponent("appearance_config.json")
        guard let data = try? Data(contentsOf: url),
              let config = try? decoder.decode(AppearanceConfig.self, from: data) else {
            return AppearanceConfig()
        }
        return config
    }

    public func saveAppearanceConfig(_ config: AppearanceConfig) throws {
        let url = rootDirectory.appendingPathComponent("appearance_config.json")
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: url, options: [.atomic])
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
}
