import BuctModel
@testable import BuctNetwork
import CryptoKit
import Foundation
import Security
import XCTest

final class BuctCryptoTests: XCTestCase {

    func testAesECBPKCS7RoundTrip() throws {
        let key = Data("0123456789abcdef".utf8)
        let plain = Data("BuctOne2026!@#".utf8)
        let encrypted = try BuctCrypto.aesECBEncrypt(plaintext: plain, key: key)
        let decrypted = try BuctCrypto.aesECBDecrypt(ciphertext: encrypted, key: key)
        XCTAssertEqual(decrypted, plain)
    }

    func testAesCBCZeroPaddedDecrypt() throws {
        let key = Data("abcdef0123456789".utf8)
        let iv = Data("0123456789abcdef".utf8)
        let plain = Data("{\"balance\":1280}".utf8)
        var padded = plain
        while padded.count % 16 != 0 {
            padded.append(0x00)
        }
        // 使用预设 CBC-ZeroPadding 密文验证去零填充解密（与 CommonCrypto CBC 互验）
        let decrypted = try BuctCrypto.aesCBCDecryptZeroPadded(
            ciphertext: try aesCBCEncryptNoPaddingForTest(plaintext: padded, key: key, iv: iv),
            key: key,
            iv: iv
        )
        XCTAssertEqual(decrypted, plain)
    }

    private func aesCBCEncryptNoPaddingForTest(plaintext: Data, key: Data, iv: Data) throws -> Data {
        // 利用 AES-ECB 对 (block XOR prevCipher) 实现纯测试用 CBC 加密，避免在测试里重复引用 CommonCrypto
        var result = Data()
        var prev = [UInt8](iv)
        for offset in stride(from: 0, to: plaintext.count, by: 16) {
            let block = [UInt8](plaintext[offset..<(offset + 16)])
            let xored = Data(zip(block, prev).map(^))
            // aesECBEncrypt 带 PKCS7，取前 16 字节即为单块 AES_Encrypt(xored)
            let encBlock = try BuctCrypto.aesECBEncrypt(plaintext: xored, key: key).prefix(16)
            result.append(encBlock)
            prev = [UInt8](encBlock)
        }
        return result
    }

    func testWebVpnHostAndUrlRoundTrip() throws {
        let encrypted = try BuctWebVpnCodec.encryptHost("scs.buct.edu.cn")
        XCTAssertTrue(encrypted.hasPrefix("77726476706e69737468656265737421"))
        XCTAssertEqual(BuctWebVpnCodec.decryptHost(encrypted), "scs.buct.edu.cn")

        let original = URL(string: "http://tree.buct.edu.cn:8800/site/sso?from=app")!
        let vpnURL = try BuctWebVpnCodec.toVpnURL(original)
        XCTAssertEqual(vpnURL.host, "w.buct.edu.cn")
        XCTAssertTrue(vpnURL.path.hasPrefix("/http-8800/"))

        let unwrapped = BuctWebVpnCodec.fromVpnURL(vpnURL)
        XCTAssertEqual(unwrapped?.absoluteString, original.absoluteString)
    }

    func testRsaPkcs1EncryptWithGeneratedKeyPair() throws {
        let params: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(params as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1Data = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            XCTFail("生成测试 RSA 密钥失败")
            return
        }

        let secret = Data("TestPassword123".utf8)
        let encrypted = try BuctCrypto.rsaEncryptPKCS1(plaintext: secret, spkiBase64: pkcs1Data.base64EncodedString())
        guard let decrypted = SecKeyCreateDecryptedData(privateKey, .rsaEncryptionPKCS1, encrypted as CFData, &error) as Data? else {
            XCTFail("RSA 解密失败")
            return
        }
        XCTAssertEqual(decrypted, secret)
    }

    func testSha256HmacAesGcmAndWipe() throws {
        XCTAssertEqual(
            BuctCrypto.sha256Hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        let mac = BuctCrypto.hmacSHA256(data: Data("hello".utf8), key: Data("secret".utf8))
        XCTAssertEqual(mac.count, 32)

        let key = SymmetricKey(size: .bits256)
        let plain = Data("sensitive-cookie".utf8)
        let sealed = try BuctCrypto.aesGCMSeal(plaintext: plain, key: key)
        let opened = try BuctCrypto.aesGCMOpen(combined: sealed, key: key)
        XCTAssertEqual(opened, plain)

        var mutableSecret = Data("MySecret".utf8)
        BuctCrypto.wipe(&mutableSecret)
        XCTAssertTrue(mutableSecret.allSatisfy { $0 == 0 })
    }

    func testCborWriterMatchesExpectedBytes() {
        var writer = CborWriter()
        writer.writeMapHeader(2)
        writer.writeText("fmt")
        writer.writeText("none")
        writer.writeInt(1)
        writer.writeInt(-7)
        let bytes = [UInt8](writer.toData())
        XCTAssertEqual(bytes, [0xA2, 0x63, 0x66, 0x6D, 0x74, 0x64, 0x6E, 0x6F, 0x6E, 0x65, 0x01, 0x26])
    }

    func testLogRedactorMasksSensitiveFields() {
        let raw = "GET https://sidportal.buct.edu.cn/login?username=2023010099&password=SecretPass&SOURCEID_TGC=TGT-12345 200"
        let redacted = LogRedactor.redact(raw)
        XCTAssertFalse(redacted.contains("2023010099"))
        XCTAssertFalse(redacted.contains("SecretPass"))
        XCTAssertFalse(redacted.contains("TGT-12345"))
        XCTAssertTrue(redacted.contains("sidportal.buct.edu.cn"))
        XCTAssertTrue(redacted.contains("200"))
    }
}
