import BuctModel
import BuctNetwork
import BuctSources
import BuctStore
import Foundation

/// 自托管 Umami（stats.buct.one）零 PII 匿名统计客户端。
/// 仅使用本地随机生成的 UUIDv4，绝不采集学号、姓名或硬件指纹。
public actor UmamiTracker {
    private static let endpointURL = URL(string: "https://stats.buct.one/api/send")!
    private static let websiteID = "f9d777c9-625a-4cc9-93f0-694c9c1cb57a"
    private static let hostname = "app.buct.one"

    private let preferences: PreferencesStore
    private let session: URLSession
    private var visitedPathsInSession: Set<String> = []
    private var inFlightLaunchDay: String?

    public init(preferences: PreferencesStore) {
        self.preferences = preferences
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config, delegate: BuctTlsDelegate.shared, delegateQueue: nil)
    }

    public func trackDailyLaunchIfNeeded(
        appVersion: String,
        buildNumber: String,
        screenSize: String
    ) async {
        let config = await preferences.loadAppearanceConfig()
        guard config.umamiEnabled else { return }

        let today = Self.beijingDayString()
        if await preferences.lastUmamiLaunchDay() == today || inFlightLaunchDay == today {
            return
        }
        inFlightLaunchDay = today
        defer {
            if inFlightLaunchDay == today {
                inFlightLaunchDay = nil
            }
        }

        let installID = await preferences.getOrCreateInstallID()
        let ok = await sendEvent(
            installID: installID,
            screen: screenSize,
            urlPath: "/app/launch",
            title: "应用日活",
            appVersion: appVersion,
            buildNumber: buildNumber,
            includeDeviceMeta: true
        )
        if ok {
            await preferences.saveLastUmamiLaunchDay(today)
        }
    }

    public func trackPageVisit(
        urlPath: String,
        title: String,
        appVersion: String,
        buildNumber: String,
        screenSize: String
    ) async {
        let config = await preferences.loadAppearanceConfig()
        guard config.umamiEnabled else { return }
        guard visitedPathsInSession.insert(urlPath).inserted else { return }

        let installID = await preferences.getOrCreateInstallID()
        let ok = await sendEvent(
            installID: installID,
            screen: screenSize,
            urlPath: urlPath,
            title: title,
            appVersion: appVersion,
            buildNumber: buildNumber,
            includeDeviceMeta: false
        )
        if !ok {
            visitedPathsInSession.remove(urlPath)
        }
    }

    public func resetSessionCache() {
        visitedPathsInSession.removeAll()
    }

    private func sendEvent(
        installID: String,
        screen: String,
        urlPath: String,
        title: String,
        appVersion: String,
        buildNumber: String,
        includeDeviceMeta: Bool
    ) async -> Bool {
        var eventData: [String: String] = [
            "app_version": appVersion,
            "platform": "ios",
            "school": "buct"
        ]
        if includeDeviceMeta {
            eventData["build_number"] = buildNumber
            eventData["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        }

        let payload: [String: Any] = [
            "website": Self.websiteID,
            "hostname": Self.hostname,
            "screen": screen,
            "language": Locale.current.identifier,
            "title": title,
            "url": urlPath,
            "id": installID,
            "data": eventData
        ]
        let root: [String: Any] = [
            "type": "event",
            "payload": payload
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: root) else {
            return false
        }

        var request = URLRequest(url: Self.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("BuctOne-iOS/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private static func beijingDayString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
