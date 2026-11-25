import Foundation

public enum ContainerMode: Sendable, Equatable {
    case appGroup(identifier: String)
    case appSandbox

    public var displayName: String {
        switch self {
        case .appGroup(let identifier):
            return "App Group 共享容器 (\(identifier))"
        case .appSandbox:
            return "独立沙盒存储"
        }
    }
}

public enum AppContainerResolver {
    public static func configuredAppGroupIdentifier(bundle: Bundle = .main) -> String? {
        guard let raw = bundle.object(forInfoDictionaryKey: "BUCTAppGroupIdentifier") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func resolveRootDirectory(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> (url: URL, mode: ContainerMode) {
        if let groupID = configuredAppGroupIdentifier(bundle: bundle),
           let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            let dataDir = groupURL.appendingPathComponent("BuctOneData", isDirectory: true)
            if ensureWritableDirectory(at: dataDir, fileManager: fileManager) {
                return (dataDir, .appGroup(identifier: groupID))
            }
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let fallbackDir = appSupport.appendingPathComponent("BuctOne", isDirectory: true)
        _ = ensureWritableDirectory(at: fallbackDir, fileManager: fileManager)
        return (fallbackDir, .appSandbox)
    }

    @discardableResult
    private static func ensureWritableDirectory(at url: URL, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try? mutableURL.setResourceValues(values)

            let probeURL = url.appendingPathComponent(".write_probe_\(UUID().uuidString)")
            try Data([0x01]).write(to: probeURL, options: [.atomic])
            try? fileManager.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }
}
