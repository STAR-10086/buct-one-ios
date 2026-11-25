import Foundation
import Security

/// 北化统一身份认证 WebAuthn / 通行密钥登录与注册客户端。
public actor BuctWebAuthnClient {
    private static let pixel7UA =
        "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    private static let webAuthnRsaPublicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAjVr1zKwohU3xA0afprWL\
    SQvIymaSH/V27MedFc+CecXSnORIFMAp4uEIb4taDq/2X4eMeTI66Mu/rB5GKSFD\
    bExF2Gu4NaO/CNDpf1gHMScUrIFCh4CDqzBnx17kclvezLkIK0T8FVa4cRsINvzj\
    bnA6jUSMaf6Fm1n9wTAtW6QYBjssGOEtCj+c38PTBdFMmJbXp3brt1tEBesz6lb3\
    Fjp76FGvDZ08xtYG8fxYPuiMwKU04eS+mcX/BunwgpU3zwekHYB+PWRIvq0lBry9\
    Wms25sJE5T/RAv5fEuMLbBkfcZK3+7ivSZthTmPpr2Ap/ji70ZZ6u2jvR5VJq+LJ\
    HQIDAQAB
    -----END PUBLIC KEY-----
    """

    private let transport: BuctHttpTransport

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func authenticate(username: String) async -> BuctSsoAuthOutcome {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty else { return .invalidCredentials }

        let jar = MatchingMemoryCookieJar()
        let serviceEncoded = BuctSsoAuthClient.teachingServiceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? BuctSsoAuthClient.teachingServiceURL
        let loginEntryURL = URL(string: "\(BuctSsoAuthClient.authPortalBase)/login?service=\(serviceEncoded)")!

        var entryReq = URLRequest(url: loginEntryURL)
        entryReq.httpMethod = "GET"
        entryReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")

        guard let entryResp = try? await transport.send(entryReq, cookieJar: jar, timeout: 20),
              entryResp.isSuccessful,
              let execution = BuctSsoAuthClient.extractHtmlParagraphField(entryResp.bodyString, id: "login-page-flowkey") else {
            return .failure(message: "无法获取统一认证会话参数")
        }

        // 生成 16 字节随机 AES 密钥，RSA 加密 Base64(aesKey) 放入 privateKey 头
        var rawAesBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, rawAesBytes.count, &rawAesBytes)
        let aesKey = Data(rawAesBytes)
        let aesKeyB64 = aesKey.base64EncodedString()

        guard let bodyPlain = try? JSONSerialization.data(withJSONObject: ["username": cleanUser]),
              let encBodyB64 = try? BuctCrypto.aesECBEncrypt(plaintext: bodyPlain, key: aesKey).base64EncodedString(),
              let rsaPrivateHeader = try? BuctCrypto.rsaEncryptPKCS1(
                plaintext: Data(aesKeyB64.utf8),
                spkiBase64: Self.webAuthnRsaPublicKeyPEM
              ).base64EncodedString() else {
            return .failure(message: "通行密钥请求加密失败")
        }

        var authReq = URLRequest(url: URL(string: "\(BuctSsoAuthClient.authPortalBase)/webauthn/authenticate")!)
        authReq.httpMethod = "POST"
        authReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
        authReq.setValue("csrfToken", forHTTPHeaderField: "X-CSRF-TOKEN")
        authReq.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        authReq.setValue("true", forHTTPHeaderField: "hasCrypto")
        authReq.setValue(rsaPrivateHeader, forHTTPHeaderField: "privateKey")
        authReq.setValue("*/*", forHTTPHeaderField: "Accept")
        authReq.setValue(BuctSsoAuthClient.authPortalBase, forHTTPHeaderField: "Origin")
        authReq.setValue("\(BuctSsoAuthClient.authPortalBase)/login", forHTTPHeaderField: "Referer")
        authReq.httpBody = Data(encBodyB64.utf8)

        guard let authResp = try? await transport.send(authReq, cookieJar: jar, timeout: 20) else {
            return .failure(message: "请求通行密钥质询失败")
        }

        let decryptedText = Self.decryptWebAuthnBody(authResp.bodyString, aesKey: aesKey)
        let authObj = (try? JSONSerialization.jsonObject(with: Data(decryptedText.utf8))) as? [String: Any]

        guard authResp.isSuccessful,
              let requestObj = authObj?["request"] as? [String: Any],
              let requestId = requestObj["requestId"] as? String,
              let options = requestObj["publicKeyCredentialRequestOptions"] as? [String: Any],
              let actions = authObj?["actions"] as? [String: Any],
              let finishPath = actions["finish"] as? String else {
            let messages = authObj?["messages"] as? [String] ?? []
            if messages.contains(where: { $0.contains("username.not.registered") }) {
                return .failure(message: "当前账号尚未注册本机通行密钥，请先使用密码登录后在「我的」中开启")
            }
            return .failure(message: messages.first ?? "无法发起通行密钥登录")
        }

        let assertion: [String: Any]
        do {
            assertion = try await BuctSoftwarePasskey.authenticate(username: cleanUser, requestJSON: options)
        } catch {
            return .failure(message: error.localizedDescription)
        }

        let finishURL = URL(string: finishPath, relativeTo: URL(string: BuctSsoAuthClient.authPortalBase)!)!
        let finishPayload: [String: Any] = [
            "requestId": requestId,
            "credential": assertion,
            "sessionToken": requestObj["sessionToken"] ?? NSNull()
        ]
        var finishReq = URLRequest(url: finishURL)
        finishReq.httpMethod = "POST"
        finishReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
        finishReq.setValue("csrfToken", forHTTPHeaderField: "X-CSRF-TOKEN")
        finishReq.setValue("*/*", forHTTPHeaderField: "Accept")
        finishReq.setValue(BuctSsoAuthClient.authPortalBase, forHTTPHeaderField: "Origin")
        finishReq.setValue("\(BuctSsoAuthClient.authPortalBase)/login", forHTTPHeaderField: "Referer")
        finishReq.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        finishReq.httpBody = try? JSONSerialization.data(withJSONObject: finishPayload)

        guard let finishResp = try? await transport.send(finishReq, cookieJar: jar, timeout: 20),
              finishResp.isSuccessful,
              let finishObj = (try? JSONSerialization.jsonObject(with: finishResp.body)) as? [String: Any],
              (finishObj["success"] as? Bool) == true,
              let authSessionToken = finishObj["sessionToken"] as? String, !authSessionToken.isEmpty else {
            return .failure(message: "通行密钥校验失败")
        }

        var casReq = URLRequest(url: URL(string: "\(BuctSsoAuthClient.authPortalBase)/login")!)
        casReq.httpMethod = "POST"
        casReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
        casReq.setValue(BuctSsoAuthClient.authPortalBase, forHTTPHeaderField: "Origin")
        casReq.setValue("\(BuctSsoAuthClient.authPortalBase)/login", forHTTPHeaderField: "Referer")
        casReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        casReq.httpBody = Self.formEncode([
            ("username", cleanUser),
            ("_eventId", "validateWebAuthn"),
            ("geolocation", ""),
            ("execution", execution),
            ("token", authSessionToken)
        ])

        guard let casResp = try? await transport.send(casReq, cookieJar: jar, timeout: 20),
              casResp.isRedirect,
              let loc = casResp.header("Location"),
              let nextURL = URL(string: loc, relativeTo: casReq.url)?.absoluteURL else {
            return .failure(message: "通行密钥登录票据换取失败")
        }

        var current = nextURL
        for _ in 0..<12 {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
            guard let resp = try? await transport.send(req, cookieJar: jar, timeout: 25) else {
                return .failure(message: "连接教务系统失败")
            }
            if resp.isRedirect {
                guard let nLoc = resp.header("Location"),
                      let nUrl = URL(string: nLoc, relativeTo: current)?.absoluteURL else {
                    return .failure(message: "教务跳转地址无效")
                }
                current = nUrl
                continue
            }
            let body = resp.bodyString
            if current.host?.caseInsensitiveCompare("jwglxt.buct.edu.cn") == .orderedSame &&
                current.path.contains("/xtgl/index_initMenu.html") &&
                !body.contains("用户登录") && !body.contains("login_slogin") {
                let jwCookie = BuctSsoAuthClient.stripRememberMe(
                    jar.cookieHeaderFor(
                        url: URL(string: "https://jwglxt.buct.edu.cn/jwglxt/")!,
                        setByHost: "jwglxt.buct.edu.cn"
                    )
                )
                let sidCookie = BuctSsoAuthClient.stripRememberMe(
                    jar.cookieHeaderFor(
                        url: URL(string: "\(BuctSsoAuthClient.authPortalBase)/login")!,
                        setByHost: "sidportal.buct.edu.cn"
                    )
                )
                return .success(jwglxtCookie: jwCookie, sidCookie: sidCookie, vpnTicket: nil)
            }
            return .failure(message: "通行密钥进入教务系统失败")
        }
        return .failure(message: "通行密钥跳转次数过多")
    }

    public func registerPasskey(username: String, sidCookie: String, nickname: String = "BUCT One iOS") async -> Result<Void, Error> {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty, !sidCookie.isEmpty else {
            return .failure(NSError(domain: "BuctWebAuthn", code: -1, userInfo: [NSLocalizedDescriptionKey: "缺少统一身份认证会话"]))
        }

        // 1. 探测 /account 建立安全设置会话上下文
        var accReq = URLRequest(url: URL(string: "\(BuctSsoAuthClient.authPortalBase)/account")!)
        accReq.httpMethod = "GET"
        accReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
        accReq.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        accReq.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        accReq.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        accReq.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        accReq.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        accReq.setValue("\(BuctSsoAuthClient.authPortalBase)/login", forHTTPHeaderField: "Referer")
        accReq.setValue(sidCookie, forHTTPHeaderField: "Cookie")
        _ = try? await transport.send(accReq, timeout: 15)

        // 2. 发起注册
        var startReq = URLRequest(url: URL(string: "\(BuctSsoAuthClient.authPortalBase)/webauthn/register")!)
        startReq.httpMethod = "POST"
        startReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
        startReq.setValue("csrfToken", forHTTPHeaderField: "X-CSRF-TOKEN")
        startReq.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        startReq.setValue("*/*", forHTTPHeaderField: "Accept")
        startReq.setValue(BuctSsoAuthClient.authPortalBase, forHTTPHeaderField: "Origin")
        startReq.setValue("\(BuctSsoAuthClient.authPortalBase)/account", forHTTPHeaderField: "Referer")
        startReq.setValue(sidCookie, forHTTPHeaderField: "Cookie")
        startReq.httpBody = Self.formEncode([
            ("username", cleanUser),
            ("displayName", cleanUser),
            ("credentialNickname", nickname),
            ("requireResidentKey", "false"),
            ("sessionToken", "null")
        ])

        guard let startResp = try? await transport.send(startReq, timeout: 20),
              let startObj = (try? JSONSerialization.jsonObject(with: startResp.body)) as? [String: Any],
              startResp.isSuccessful,
              let requestObj = startObj["request"] as? [String: Any],
              let requestId = requestObj["requestId"] as? String,
              let creationOptions = requestObj["publicKeyCredentialCreationOptions"] as? [String: Any],
              let actions = startObj["actions"] as? [String: Any],
              let finishPath = actions["finish"] as? String else {
            return .failure(NSError(domain: "BuctWebAuthn", code: -1, userInfo: [NSLocalizedDescriptionKey: "统一身份认证拒绝创建通行密钥"]))
        }

        let creationPayload: [String: Any]
        do {
            creationPayload = try await BuctSoftwarePasskey.createCredential(username: cleanUser, creationJSON: creationOptions)
        } catch {
            return .failure(error)
        }

        let finishURL = URL(string: finishPath, relativeTo: URL(string: BuctSsoAuthClient.authPortalBase)!)!
        var finishReq = URLRequest(url: finishURL)
        finishReq.httpMethod = "POST"
        finishReq.setValue(Self.pixel7UA, forHTTPHeaderField: "User-Agent")
        finishReq.setValue("csrfToken", forHTTPHeaderField: "X-CSRF-TOKEN")
        finishReq.setValue("*/*", forHTTPHeaderField: "Accept")
        finishReq.setValue(BuctSsoAuthClient.authPortalBase, forHTTPHeaderField: "Origin")
        finishReq.setValue("\(BuctSsoAuthClient.authPortalBase)/account", forHTTPHeaderField: "Referer")
        finishReq.setValue(sidCookie, forHTTPHeaderField: "Cookie")
        finishReq.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        finishReq.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requestId": requestId,
            "credential": creationPayload,
            "sessionToken": requestObj["sessionToken"] ?? NSNull()
        ])

        guard let finishResp = try? await transport.send(finishReq, timeout: 20),
              finishResp.isSuccessful,
              let finishObj = (try? JSONSerialization.jsonObject(with: finishResp.body)) as? [String: Any],
              (finishObj["success"] as? Bool) == true else {
            BuctSoftwarePasskey.clearCredential(username: cleanUser)
            return .failure(NSError(domain: "BuctWebAuthn", code: -1, userInfo: [NSLocalizedDescriptionKey: "通行密钥注册确认失败"]))
        }
        return .success(())
    }

    private static func decryptWebAuthnBody(_ raw: String, aesKey: Data) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        guard let cipher = Data(base64Encoded: trimmed),
              let plain = try? BuctCrypto.aesECBDecrypt(ciphertext: cipher, key: aesKey),
              let str = String(data: plain, encoding: .utf8) else {
            return trimmed
        }
        return str
    }

    private static func formEncode(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let body = pairs.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}
