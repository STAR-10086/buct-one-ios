import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum BuctPasskeyError: Error, LocalizedError, Sendable {
    case notRegistered
    case biometricCancelled
    case keyGenerationFailed
    case signingFailed
    case invalidChallenge

    public var errorDescription: String? {
        switch self {
        case .notRegistered: return "该学号在当前设备上未创建通行密钥"
        case .biometricCancelled: return "已取消面容 / 密码验证"
        case .keyGenerationFailed: return "生成通行密钥失败"
        case .signingFailed: return "通行密钥签名失败"
        case .invalidChallenge: return "服务端返回了无效的通行密钥请求"
        }
    }
}

/// App 内置 WebAuthn/FIDO2 软件认证器（EC P-256 + Face ID / 设备密码验证）。
/// 所有 Keychain 读写严禁传入 AccessGroup，保证免费自签与 LiveContainer 可用。
public enum BuctSoftwarePasskey {
    public static let rpID = "sidportal.buct.edu.cn"
    public static let origin = "https://sidportal.buct.edu.cn"
    private static let metadataService = "com.buct.one.vault.passkey"
    private static let keyTagPrefix = "com.buct.one.passkey."

    private struct StoredCredential: Codable {
        let credentialIDBase64Url: String
        let keyTag: String
        var signCount: Int
        let rpID: String
    }

    public static func hasCredential(username: String) -> Bool {
        loadStoredCredential(username: username) != nil
    }

    public static func clearCredential(username: String) {
        if let stored = loadStoredCredential(username: username) {
            deletePrivateKey(tag: stored.keyTag)
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: metadataService,
            kSecAttrAccount: username
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func createCredential(username: String, creationJSON: [String: Any]) async throws -> [String: Any] {
        guard let challenge = creationJSON["challenge"] as? String, !challenge.isEmpty else {
            throw BuctPasskeyError.invalidChallenge
        }
        try await evaluateDeviceOwnerAuthentication(reason: "验证身份以创建北化一站通行密钥")

        let rpDict = creationJSON["rp"] as? [String: Any]
        let effectiveRpID = (rpDict?["id"] as? String)?.isEmpty == false ? (rpDict?["id"] as! String) : rpID

        var credBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, credBytes.count, &credBytes)
        let credentialID = Data(credBytes)

        let keyTag = keyTagPrefix + UUID().uuidString
        let privateKey = try generateECP256Key(tag: keyTag)
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let x963Data = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              x963Data.count == 65, x963Data[0] == 0x04 else {
            throw BuctPasskeyError.keyGenerationFailed
        }
        let xCoord = x963Data.subdata(in: 1..<33)
        let yCoord = x963Data.subdata(in: 33..<65)

        var coseWriter = CborWriter()
        coseWriter.writeMapHeader(5)
        coseWriter.writeInt(1); coseWriter.writeInt(2)
        coseWriter.writeInt(3); coseWriter.writeInt(-7)
        coseWriter.writeInt(-1); coseWriter.writeInt(1)
        coseWriter.writeInt(-2); coseWriter.writeBytes(xCoord)
        coseWriter.writeInt(-3); coseWriter.writeBytes(yCoord)
        let coseKey = coseWriter.toData()

        var authData = Data()
        authData.append(Data(SHA256.hash(data: Data(effectiveRpID.utf8))))
        authData.append(0x45) // UP + UV + AT
        authData.append(contentsOf: [0, 0, 0, 0])
        authData.append(contentsOf: [UInt8](repeating: 0, count: 16))
        authData.append(UInt8((credentialID.count >> 8) & 0xFF))
        authData.append(UInt8(credentialID.count & 0xFF))
        authData.append(credentialID)
        authData.append(coseKey)

        var attWriter = CborWriter()
        attWriter.writeMapHeader(3)
        attWriter.writeText("fmt"); attWriter.writeText("none")
        attWriter.writeText("attStmt"); attWriter.writeMapHeader(0)
        attWriter.writeText("authData"); attWriter.writeBytes(authData)
        let attestationObject = attWriter.toData()

        let clientDataString = "{\"type\":\"webauthn.create\",\"challenge\":\"\(challenge)\",\"origin\":\"\(origin)\",\"crossOrigin\":false}"
        let clientDataJSON = Data(clientDataString.utf8)

        let credIdB64Url = base64UrlEncode(credentialID)
        let stored = StoredCredential(
            credentialIDBase64Url: credIdB64Url,
            keyTag: keyTag,
            signCount: 0,
            rpID: effectiveRpID
        )
        try saveStoredCredential(stored, username: username)

        return [
            "type": "public-key",
            "id": credIdB64Url,
            "response": [
                "attestationObject": base64UrlEncode(attestationObject),
                "clientDataJSON": base64UrlEncode(clientDataJSON)
            ],
            "clientExtensionResults": [String: Any]()
        ]
    }

    public static func authenticate(username: String, requestJSON: [String: Any]) async throws -> [String: Any] {
        guard var stored = loadStoredCredential(username: username),
              let credentialID = base64UrlDecode(stored.credentialIDBase64Url) else {
            throw BuctPasskeyError.notRegistered
        }
        guard let challenge = requestJSON["challenge"] as? String, !challenge.isEmpty else {
            throw BuctPasskeyError.invalidChallenge
        }

        if let allow = requestJSON["allowCredentials"] as? [[String: Any]] {
            let matched = allow.contains { ($0["id"] as? String) == stored.credentialIDBase64Url }
            if !matched {
                throw BuctPasskeyError.notRegistered
            }
        }

        guard let privateKey = loadPrivateKey(tag: stored.keyTag) else {
            throw BuctPasskeyError.notRegistered
        }

        try await evaluateDeviceOwnerAuthentication(reason: "验证面容或密码以登录北化一站")

        let effectiveRpID = (requestJSON["rpId"] as? String)?.isEmpty == false ? (requestJSON["rpId"] as! String) : stored.rpID
        let clientDataString = "{\"type\":\"webauthn.get\",\"challenge\":\"\(challenge)\",\"origin\":\"\(origin)\",\"crossOrigin\":false}"
        let clientDataJSON = Data(clientDataString.utf8)

        stored.signCount += 1
        let sc = stored.signCount
        var authenticatorData = Data()
        authenticatorData.append(Data(SHA256.hash(data: Data(effectiveRpID.utf8))))
        authenticatorData.append(0x05) // UP + UV
        authenticatorData.append(UInt8((sc >> 24) & 0xFF))
        authenticatorData.append(UInt8((sc >> 16) & 0xFF))
        authenticatorData.append(UInt8((sc >> 8) & 0xFF))
        authenticatorData.append(UInt8(sc & 0xFF))

        var signedPayload = authenticatorData
        signedPayload.append(Data(SHA256.hash(data: clientDataJSON)))

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            signedPayload as CFData,
            &error
        ) as Data? else {
            throw BuctPasskeyError.signingFailed
        }

        try? saveStoredCredential(stored, username: username)

        return [
            "type": "public-key",
            "id": base64UrlEncode(credentialID),
            "response": [
                "authenticatorData": base64UrlEncode(authenticatorData),
                "clientDataJSON": base64UrlEncode(clientDataJSON),
                "signature": base64UrlEncode(signature),
                "userHandle": NSNull()
            ],
            "clientExtensionResults": [String: Any]()
        ]
    }

    private static func evaluateDeviceOwnerAuthentication(reason: String) async throws {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if !ok {
                throw BuctPasskeyError.biometricCancelled
            }
        } catch {
            throw BuctPasskeyError.biometricCancelled
        }
    }

    private static func generateECP256Key(tag: String) throws -> SecKey {
        deletePrivateKey(tag: tag)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: Data(tag.utf8),
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw BuctPasskeyError.keyGenerationFailed
        }
        return key
    }

    private static func loadPrivateKey(tag: String) -> SecKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data(tag.utf8),
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let item else { return nil }
        return (item as! SecKey)
    }

    private static func deletePrivateKey(tag: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: Data(tag.utf8),
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func saveStoredCredential(_ stored: StoredCredential, username: String) throws {
        let data = try JSONEncoder().encode(stored)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: metadataService,
            kSecAttrAccount: username
        ]
        let attrs: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func loadStoredCredential(username: String) -> StoredCredential? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: metadataService,
            kSecAttrAccount: username,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredCredential.self, from: data)
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64UrlDecode(_ str: String) -> Data? {
        var b64 = str.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 {
            b64.append(String(repeating: "=", count: 4 - rem))
        }
        return Data(base64Encoded: b64)
    }
}
