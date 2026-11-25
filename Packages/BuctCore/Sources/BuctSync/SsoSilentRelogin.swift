import BuctModel
import BuctNetwork
import BuctStore
import Foundation

/// 跨模块单飞静默续期协调器（30 秒失败冷却 + 快照防重登）。
public actor SsoSilentRelogin {
    private static let failureCooldown: TimeInterval = 30
    private let sessionVault: SessionVaultStore
    private let authClient: BuctSsoAuthClient
    private var lastFailureAt: Date?

    public init(sessionVault: SessionVaultStore, authClient: BuctSsoAuthClient) {
        self.sessionVault = sessionVault
        self.authClient = authClient
    }

    public func resetCooldown() {
        lastFailureAt = nil
    }

    public static func isAuthFailureMessage(_ message: String) -> Bool {
        let markers = ["登录", "过期", "失效", "会话", "未建立", "认证", "票据", "401", "403", "901"]
        return markers.contains { message.localizedCaseInsensitiveContains($0) }
    }

    public func attemptRelogin(
        sidSnapshotBefore: String,
        bypassCooldown: Bool = false
    ) async -> Bool {
        let latest = await sessionVault.loadSession()
        if !latest.sidCookies.isEmpty && latest.sidCookies != sidSnapshotBefore {
            lastFailureAt = nil
            return true
        }

        if !bypassCooldown, let lastFail = lastFailureAt,
           Date().timeIntervalSince(lastFail) < Self.failureCooldown {
            return false
        }

        guard let cred = await sessionVault.loadCredential(),
              cred.systemType == .undergradJwglxt,
              !cred.username.isEmpty,
              !cred.password.isEmpty else {
            return false
        }

        let outcome = await authClient.login(
            username: cred.username,
            password: cred.password,
            mode: .teaching
        )
        switch outcome {
        case .success(let jwCookie, let sidCookie, _):
            await sessionVault.saveJwglxtCookies(jwCookie)
            await sessionVault.saveSidPortalCookies(sidCookie)
            lastFailureAt = nil
            return true
        default:
            lastFailureAt = Date()
            return false
        }
    }
}
