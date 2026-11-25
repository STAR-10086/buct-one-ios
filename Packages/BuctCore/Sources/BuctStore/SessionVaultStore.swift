import BuctModel
import Foundation

public struct SsoSessionBundle: Codable, Sendable, Equatable {
    public var sidCookies: String
    public var jwglxtCookies: String
    public var gmisCookies: String
    public var meolCookies: String
    public var vpnTicket: String

    public init(
        sidCookies: String = "",
        jwglxtCookies: String = "",
        gmisCookies: String = "",
        meolCookies: String = "",
        vpnTicket: String = ""
    ) {
        self.sidCookies = sidCookies
        self.jwglxtCookies = jwglxtCookies
        self.gmisCookies = gmisCookies
        self.meolCookies = meolCookies
        self.vpnTicket = vpnTicket
    }
}

public struct SavedLoginCredential: Codable, Sendable, Equatable {
    public let username: String
    public let password: String
    public let systemType: AcademicSystemType

    public init(username: String, password: String, systemType: AcademicSystemType) {
        self.username = username
        self.password = password
        self.systemType = systemType
    }
}

public actor SessionVaultStore {
    private static let sessionAccount = "sso_session_bundle"
    private static let credAccount = "saved_login_credential"

    private let vault = KeychainVault(namespace: .sidportal)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func loadSession() -> SsoSessionBundle {
        guard let data = try? vault.load(for: Self.sessionAccount),
              let bundle = try? decoder.decode(SsoSessionBundle.self, from: data) else {
            return SsoSessionBundle()
        }
        return bundle
    }

    public func saveSidPortalCookies(_ rawCookies: String) {
        let trimmed = rawCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.localizedCaseInsensitiveContains("SOURCEID_TGC=") else {
            return
        }
        var bundle = loadSession()
        bundle.sidCookies = trimmed
        persistSession(bundle)
    }

    public func saveJwglxtCookies(_ rawCookies: String) {
        let trimmed = rawCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var bundle = loadSession()
        bundle.jwglxtCookies = trimmed
        persistSession(bundle)
    }

    public func saveGmisCookies(_ rawCookies: String) {
        let trimmed = rawCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var bundle = loadSession()
        bundle.gmisCookies = trimmed
        persistSession(bundle)
    }

    public func saveMeolCookies(_ rawCookies: String) {
        let trimmed = rawCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var bundle = loadSession()
        bundle.meolCookies = trimmed
        persistSession(bundle)
    }

    public func saveVpnTicket(_ ticket: String) {
        let trimmed = ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.caseInsensitiveCompare("deleteMe") != .orderedSame else {
            return
        }
        var bundle = loadSession()
        guard bundle.vpnTicket != trimmed else { return }
        bundle.vpnTicket = trimmed
        persistSession(bundle)
    }

    public func clearVpnTicket() {
        var bundle = loadSession()
        bundle.vpnTicket = ""
        persistSession(bundle)
    }

    public func clearSession() {
        try? vault.delete(for: Self.sessionAccount)
    }

    public func loadCredential() -> SavedLoginCredential? {
        guard let data = try? vault.load(for: Self.credAccount),
              let cred = try? decoder.decode(SavedLoginCredential.self, from: data) else {
            return nil
        }
        return cred
    }

    public func saveCredential(_ credential: SavedLoginCredential) {
        guard let data = try? encoder.encode(credential) else { return }
        try? vault.save(data, for: Self.credAccount)
    }

    public func clearCredential() {
        try? vault.delete(for: Self.credAccount)
    }

    private func persistSession(_ bundle: SsoSessionBundle) {
        guard let data = try? encoder.encode(bundle) else { return }
        try? vault.save(data, for: Self.sessionAccount)
    }
}
