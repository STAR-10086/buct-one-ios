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

    public let containerMode: ContainerMode
    public let edition: String
    public let appVersion: String
    public let buildNumber: String

    private let preferences: PreferencesStore
    private let umamiTracker: UmamiTracker
    private var didBootstrap = false

    public init() {
        let resolved = AppContainerResolver.resolveRootDirectory()
        self.containerMode = resolved.mode
        self.preferences = PreferencesStore(rootDirectory: resolved.url)
        self.umamiTracker = UmamiTracker(preferences: self.preferences)

        let info = Bundle.main.infoDictionary ?? [:]
        self.edition = (info["BUCTEdition"] as? String) ?? "standard"
        self.appVersion = (info["CFBundleShortVersionString"] as? String) ?? "0.1.0"
        self.buildNumber = (info["CFBundleVersion"] as? String) ?? "1"
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

    public func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        appearance = await preferences.loadAppearanceConfig()
        dashboardLayout = await preferences.loadDashboardLayout()
        await umamiTracker.trackDailyLaunchIfNeeded(
            appVersion: appVersion,
            buildNumber: buildNumber,
            screenSize: screenSizeText
        )
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
