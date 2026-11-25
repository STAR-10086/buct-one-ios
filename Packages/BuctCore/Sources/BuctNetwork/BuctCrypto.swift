import CommonCrypto
import CryptoKit
import Foundation
import Security

public enum BuctCryptoError: Error, LocalizedError, Sendable {
    case invalidKey
    case invalidInput
    case commonCryptoFailed(CCCryptorStatus)
    case rsaKeyInvalid
    case rsaEncryptFailed

    public var errorDescription: String? {
        switch self {
        case .invalidKey: return "加密密钥格式或长度无效"
        case .invalidInput: return "待加密数据格式无效"
        case .commonCryptoFailed(let status): return "底层加密失败 (\(status))"
        case .rsaKeyInvalid: return "RSA 公钥解析失败"
        case .rsaEncryptFailed: return "RSA 加密失败"
        }
    }
}

public enum BuctCrypto {

    // MARK: - 敏感内存清零

    public static func wipe(_ data: inout Data) {
        guard !data.isEmpty else { return }
        data.resetBytes(in: 0..<data.count)
    }

    // MARK: - AES-ECB-PKCS7 (sidportal / WebAuthn / Ecard / Southsoft)

    public static func aesECBEncrypt(plaintext: Data, key: Data) throws -> Data {
        try cryptECB(operation: CCOperation(kCCEncrypt), input: plaintext, key: key)
    }

    public static func aesECBDecrypt(ciphertext: Data, key: Data) throws -> Data {
        try cryptECB(operation: CCOperation(kCCDecrypt), input: ciphertext, key: key)
    }

    private static func cryptECB(operation: CCOperation, input: Data, key: Data) throws -> Data {
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count) else {
            throw BuctCryptoError.invalidKey
        }
        let bufferSize = input.count + kCCBlockSizeAES128
        var output = Data(count: bufferSize)
        var outLength = 0

        let status = output.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        inBytes.baseAddress,
                        input.count,
                        outBytes.baseAddress,
                        bufferSize,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw BuctCryptoError.commonCryptoFailed(status)
        }
        output.removeSubrange(outLength..<output.count)
        return output
    }

    // MARK: - AES-CBC-NoPadding + 去零填充 (Ecard 结果解密)

    public static func aesCBCDecryptZeroPadded(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count),
              iv.count == kCCBlockSizeAES128 else {
            throw BuctCryptoError.invalidKey
        }
        guard ciphertext.count % kCCBlockSizeAES128 == 0 else {
            throw BuctCryptoError.invalidInput
        }
        var output = Data(count: ciphertext.count)
        var outLength = 0

        let status = output.withUnsafeMutableBytes { outBytes in
            ciphertext.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            0,
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress,
                            ciphertext.count,
                            outBytes.baseAddress,
                            ciphertext.count,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw BuctCryptoError.commonCryptoFailed(status)
        }
        output.removeSubrange(outLength..<output.count)
        while output.last == 0 {
            output.removeLast()
        }
        return output
    }

    // MARK: - AES-128-CFB-128 (Wengine WebVPN 域名编解码)

    public static func aes128CFB128Encrypt(plaintext: Data, key: Data, iv: Data) throws -> Data {
        try cryptCFB128(operation: CCOperation(kCCEncrypt), input: plaintext, key: key, iv: iv)
    }

    public static func aes128CFB128Decrypt(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        try cryptCFB128(operation: CCOperation(kCCDecrypt), input: ciphertext, key: key, iv: iv)
    }

    private static func cryptCFB128(operation: CCOperation, input: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else {
            throw BuctCryptoError.invalidKey
        }
        var cryptor: CCCryptorRef?
        let createStatus = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    operation,
                    CCMode(kCCModeCFB),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    0,
                    &cryptor
                )
            }
        }
        guard createStatus == kCCSuccess, let cryptor else {
            throw BuctCryptoError.commonCryptoFailed(createStatus)
        }
        defer { CCCryptorRelease(cryptor) }

        let maxOut = CCCryptorGetOutputLength(cryptor, input.count, true)
        var output = Data(count: maxOut)
        var movedUpdate = 0

        let updateStatus = output.withUnsafeMutableBytes { outBytes in
            input.withUnsafeBytes { inBytes in
                CCCryptorUpdate(
                    cryptor,
                    inBytes.baseAddress,
                    input.count,
                    outBytes.baseAddress,
                    maxOut,
                    &movedUpdate
                )
            }
        }
        guard updateStatus == kCCSuccess else {
            throw BuctCryptoError.commonCryptoFailed(updateStatus)
        }

        var movedFinal = 0
        let finalStatus = output.withUnsafeMutableBytes { outBytes in
            let ptr = outBytes.baseAddress?.advanced(by: movedUpdate)
            return CCCryptorFinal(cryptor, ptr, maxOut - movedUpdate, &movedFinal)
        }
        guard finalStatus == kCCSuccess else {
            throw BuctCryptoError.commonCryptoFailed(finalStatus)
        }

        output.removeSubrange((movedUpdate + movedFinal)..<output.count)
        return output
    }

    // MARK: - RSA/ECB/PKCS1Padding

    public static func rsaEncryptPKCS1(plaintext: Data, spkiBase64: String) throws -> Data {
        var cleaned = spkiBase64
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\n", with: "")
            .replacingOccurrences(of: "\\r", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let rem = cleaned.count % 4
        if rem != 0 {
            cleaned += String(repeating: "=", count: 4 - rem)
        }
        guard let der = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]), !der.isEmpty else {
            throw BuctCryptoError.rsaKeyInvalid
        }
        if let pkcs1Data = extractPKCS1FromSPKI(der),
           let encrypted = try? rsaEncryptWithPKCS1Data(plaintext: plaintext, pkcs1Data: Data(pkcs1Data)) {
            return encrypted
        }
        return try rsaEncryptWithPKCS1Data(plaintext: plaintext, pkcs1Data: der)
    }

    public static func rsaEncryptPKCS1(plaintext: Data, modulus: Data, exponent: Data) throws -> Data {
        guard !modulus.isEmpty, !exponent.isEmpty else {
            throw BuctCryptoError.rsaKeyInvalid
        }
        let pkcs1Data = encodeDERSequence([
            encodeDERInteger(modulus),
            encodeDERInteger(exponent)
        ])
        return try rsaEncryptWithPKCS1Data(plaintext: plaintext, pkcs1Data: pkcs1Data)
    }

    private static func rsaEncryptWithPKCS1Data(plaintext: Data, pkcs1Data: Data) throws -> Data {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(pkcs1Data as CFData, attributes as CFDictionary, &error) else {
            throw BuctCryptoError.rsaKeyInvalid
        }
        guard SecKeyIsAlgorithmSupported(secKey, .encrypt, .rsaEncryptionPKCS1) else {
            throw BuctCryptoError.rsaEncryptFailed
        }
        guard let encrypted = SecKeyCreateEncryptedData(
            secKey,
            .rsaEncryptionPKCS1,
            plaintext as CFData,
            &error
        ) as Data? else {
            throw BuctCryptoError.rsaEncryptFailed
        }
        return encrypted
    }

    // MARK: - SHA-256 / MD5 / HMAC-SHA256 / AES-GCM

    public static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func hmacSHA256(data: Data, key: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    public static func aesGCMSeal(plaintext: Data, key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw BuctCryptoError.invalidInput
        }
        return combined
    }

    public static func aesGCMOpen(combined: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: - 轻量 ASN.1 DER 编解码（仅用于 RSA 公钥）

    private static func extractPKCS1FromSPKI(_ spki: Data) -> Data? {
        var idx = 0
        guard let (_, seqEnd) = readDERTagAndLength(spki, at: &idx, expectedTag: 0x30),
              seqEnd <= spki.count else {
            return nil
        }
        // 跳过 AlgorithmIdentifier SEQUENCE
        guard let (_, algEnd) = readDERTagAndLength(spki, at: &idx, expectedTag: 0x30) else {
            return nil
        }
        idx = algEnd
        // 读取 BIT STRING (0x03)
        guard let (_, bitEnd) = readDERTagAndLength(spki, at: &idx, expectedTag: 0x03),
              idx < bitEnd,
              spki[idx] == 0x00 else {
            return nil
        }
        idx += 1
        return spki[idx..<bitEnd]
    }

    private static func readDERTagAndLength(_ data: Data, at index: inout Int, expectedTag: UInt8) -> (Int, Int)? {
        guard index < data.count, data[index] == expectedTag else { return nil }
        index += 1
        guard index < data.count else { return nil }
        let firstLen = Int(data[index])
        index += 1
        let length: Int
        if firstLen < 0x80 {
            length = firstLen
        } else {
            let count = firstLen & 0x7F
            guard count > 0, count <= 4, index + count <= data.count else { return nil }
            var val = 0
            for _ in 0..<count {
                val = (val << 8) | Int(data[index])
                index += 1
            }
            length = val
        }
        guard index + length <= data.count else { return nil }
        return (length, index + length)
    }

    private static func encodeDERInteger(_ raw: Data) -> Data {
        var bytes = [UInt8](raw)
        while bytes.count > 1 && bytes.first == 0x00 {
            bytes.removeFirst()
        }
        if let first = bytes.first, (first & 0x80) != 0 {
            bytes.insert(0x00, at: 0)
        }
        var out = Data([0x02])
        out.append(encodeDERLength(bytes.count))
        out.append(contentsOf: bytes)
        return out
    }

    private static func encodeDERSequence(_ items: [Data]) -> Data {
        var body = Data()
        for item in items {
            body.append(item)
        }
        var out = Data([0x30])
        out.append(encodeDERLength(body.count))
        out.append(body)
        return out
    }

    private static func encodeDERLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        var temp = length
        var bytes: [UInt8] = []
        while temp > 0 {
            bytes.insert(UInt8(temp & 0xFF), at: 0)
            temp >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
}
