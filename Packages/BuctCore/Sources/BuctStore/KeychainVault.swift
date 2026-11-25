import Foundation
import Security

public enum KeychainVaultNamespace: String, Sendable {
    case sidportal = "com.buct.one.vault.sidportal"
    case card = "com.buct.one.vault.card"
    case passkey = "com.buct.one.vault.passkey"
}

public enum KeychainVaultError: Error, LocalizedError, Sendable, Equatable {
    case itemNotFound
    case missingEntitlement
    case unexpectedData
    case osStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: return "未找到本地凭据"
        case .missingEntitlement: return "当前自签环境缺少 Keychain 权限"
        case .unexpectedData: return "凭据数据格式异常"
        case .osStatus(let status): return "Keychain 错误 (\(status))"
        }
    }
}

/// 隔离式 Keychain 封装：
/// - 严禁显式设置 kSecAttrAccessGroup（避免免费签与 LiveContainer 报 -34018）
/// - 统一使用 kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly 排除 iCloud 备份与换机迁移
public struct KeychainVault: Sendable {
    public let namespace: KeychainVaultNamespace

    public init(namespace: KeychainVaultNamespace) {
        self.namespace = namespace
    }

    public func save(_ data: Data, for account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.rawValue,
            kSecAttrAccount: account
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw mapStatus(addStatus)
            }
            return
        }
        throw mapStatus(updateStatus)
    }

    public func load(for account: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.rawValue,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw mapStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainVaultError.unexpectedData
        }
        return data
    }

    public func delete(for account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace.rawValue,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw mapStatus(status)
        }
    }

    private func mapStatus(_ status: OSStatus) -> KeychainVaultError {
        switch status {
        case errSecItemNotFound:
            return .itemNotFound
        case errSecMissingEntitlement:
            return .missingEntitlement
        default:
            return .osStatus(status)
        }
    }
}
