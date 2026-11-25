import Foundation

public struct EcardCredential: Codable, Sendable, Equatable {
    public let idSerial: String
    public let password: String

    public init(idSerial: String, password: String) {
        self.idSerial = idSerial
        self.password = password
    }
}

/// 校园卡独立 Keychain 保险箱（namespace = .card，与统一身份认证物理隔离，禁止 AccessGroup）。
public actor CardSessionVaultStore {
    private let vault = KeychainVault(namespace: .card)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func loadCredential(accountKey: String) -> EcardCredential? {
        let key = "ecard_cred_\(accountKey)"
        guard let data = try? vault.load(for: key),
              let cred = try? decoder.decode(EcardCredential.self, from: data) else {
            return nil
        }
        return cred
    }

    public func saveCredential(_ cred: EcardCredential, accountKey: String) {
        let key = "ecard_cred_\(accountKey)"
        guard let data = try? encoder.encode(cred) else { return }
        try? vault.save(data, for: key)
    }

    public func clearCredential(accountKey: String) {
        let key = "ecard_cred_\(accountKey)"
        try? vault.delete(for: key)
    }
}
