import BuctModel
import BuctNetwork
import Foundation

public struct GmisLoginChallenge: Sendable {
    public let publicKeyPEM: String
    public let captchaImageData: Data
}

public actor GmisClient {
    private static let baseURL = "https://gmis.buct.edu.cn"
    private static let mobileUA =
        "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    private let webVpn: BuctWebVpnManager
    private let loginJar = MatchingMemoryCookieJar()
    private var cachedPubKeyPEM: String = ""

    public init(webVpn: BuctWebVpnManager = .shared) {
        self.webVpn = webVpn
    }

    public func fetchLoginChallenge() async throws -> GmisLoginChallenge {
        loginJar.clear()
        var pageReq = URLRequest(url: URL(string: "\(Self.baseURL)/home/stulogin")!)
        pageReq.httpMethod = "GET"
        pageReq.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")

        let pageResp = try await webVpn.execute(pageReq, cookieJar: loginJar, timeout: 20)
        guard pageResp.isSuccessful,
              let pem = GmisParser.extractPublicKeyPEM(fromLoginHtml: pageResp.bodyString) else {
            throw NSError(domain: "GmisClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法获取研究生系统登录公钥（请确认网络或统一认证状态）"])
        }
        cachedPubKeyPEM = pem

        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var capReq = URLRequest(url: URL(string: "\(Self.baseURL)/home/verificationcode?codetype=stucode&t=\(ts)")!)
        capReq.httpMethod = "GET"
        capReq.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        capReq.setValue("\(Self.baseURL)/home/stulogin", forHTTPHeaderField: "Referer")

        let capResp = try await webVpn.execute(capReq, cookieJar: loginJar, timeout: 15)
        guard capResp.isSuccessful, !capResp.body.isEmpty else {
            throw NSError(domain: "GmisClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "获取研究生系统验证码失败"])
        }
        return GmisLoginChallenge(publicKeyPEM: pem, captchaImageData: capResp.body)
    }

    public func submitLogin(
        username: String,
        password: String,
        captcha: String
    ) async throws -> (cookie: String, profile: UserAccountProfile) {
        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCap = captcha.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUser.isEmpty, !password.isEmpty, !cleanCap.isEmpty else {
            throw NSError(domain: "GmisClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "请完整填写学号、密码与验证码"])
        }
        guard !cachedPubKeyPEM.isEmpty else {
            throw NSError(domain: "GmisClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "登录挑战已失效，请刷新验证码"])
        }

        let encPwd = try BuctCrypto.rsaEncryptPKCS1(plaintext: Data(password.utf8), spkiBase64: cachedPubKeyPEM).base64EncodedString()
        let jsonDict: [String: String] = [
            "UserId": cleanUser,
            "Password": encPwd,
            "VeriCode": cleanCap,
            "url": "",
            "city": ""
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
        let jsonStr = String(data: jsonData, encoding: .utf8) ?? "{}"

        var postReq = URLRequest(url: URL(string: "\(Self.baseURL)/home/stulogin_do")!)
        postReq.httpMethod = "POST"
        postReq.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        postReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        postReq.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        postReq.setValue("\(Self.baseURL)/home/stulogin", forHTTPHeaderField: "Referer")
        postReq.httpBody = formEncode([("json", jsonStr)])

        let postResp = try await webVpn.execute(postReq, cookieJar: loginJar, timeout: 20)
        if !postResp.isRedirect {
            let decoded = GmisParser.decodePayload(postResp.bodyString)
            if let obj = (try? JSONSerialization.jsonObject(with: Data(decoded.utf8))) as? [String: Any] {
                let flag = "\(obj["jg"] ?? obj["success"] ?? obj["code"] ?? "")".lowercased()
                if !["1", "true", "200", "0"].contains(flag) {
                    let msg = (obj["msg"] as? String)
                        ?? (obj["message"] as? String)
                        ?? (obj["error"] as? String)
                        ?? (obj["errmsg"] as? String)
                        ?? "学号、密码或验证码错误"
                    throw NSError(domain: "GmisClient", code: -5, userInfo: [NSLocalizedDescriptionKey: msg])
                }
            }
        }

        let cookieHeader = loginJar.cookieHeaderFor(url: URL(string: "\(Self.baseURL)/student/default/index")!)
        let profile = try await fetchProfile(cookie: cookieHeader, fallbackId: cleanUser)
        return (cookieHeader, profile)
    }

    public func fetchProfile(cookie: String, fallbackId: String) async throws -> UserAccountProfile {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/student/default/getxscardinfo?_=\(ts)")!)
        req.httpMethod = "GET"
        req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("\(Self.baseURL)/student/default/index", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if !cookie.isEmpty {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let resp = try await webVpn.execute(req, timeout: 20)
        if [401, 403].contains(resp.statusCode) || resp.isRedirect {
            throw GmisSessionExpiredError()
        }
        guard let info = GmisParser.parseStudentCardInfo(rawPayload: resp.bodyString, fallbackId: fallbackId) else {
            throw GmisSessionExpiredError()
        }
        return UserAccountProfile(studentId: info.studentId, studentName: info.name, systemType: .graduateGmis)
    }

    public func fetchTerms(cookie: String) async throws -> [AcademicTerm] {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/student/default/bindterm?_=\(ts)")!)
        req.httpMethod = "GET"
        req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("\(Self.baseURL)/student/default/index", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }

        let resp = try await webVpn.execute(req, timeout: 20)
        if [401, 403].contains(resp.statusCode) || resp.isRedirect {
            throw GmisSessionExpiredError()
        }
        return GmisParser.parseTerms(rawPayload: resp.bodyString)
    }

    public func fetchSchedule(termCode: String, cookie: String) async throws -> [ScheduleCourse] {
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/student/pygl/py_kbcx_ew")!)
        req.httpMethod = "POST"
        req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("\(Self.baseURL)/student/pygl/py_kbcx", forHTTPHeaderField: "Referer")
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }
        req.httpBody = formEncode([("kblx", "xs"), ("termcode", termCode)])

        let resp = try await webVpn.execute(req, timeout: 25)
        if [401, 403].contains(resp.statusCode) || resp.isRedirect {
            throw GmisSessionExpiredError()
        }
        return GmisParser.parseSchedule(rawPayload: resp.bodyString)
    }

    public func fetchGrades(cookie: String, currentTerm: AcademicTerm) async throws -> OverallAcademicBundle {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        var req = URLRequest(url: URL(string: "\(Self.baseURL)/student/pygl/xscjcx_list?_=\(ts)")!)
        req.httpMethod = "GET"
        req.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        req.setValue("\(Self.baseURL)/student/pygl/xscjcx", forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if !cookie.isEmpty { req.setValue(cookie, forHTTPHeaderField: "Cookie") }

        let resp = try await webVpn.execute(req, timeout: 25)
        if [401, 403].contains(resp.statusCode) || resp.isRedirect {
            throw GmisSessionExpiredError()
        }
        return GmisParser.parseGrades(rawPayload: resp.bodyString, currentTerm: currentTerm)
    }

    private func formEncode(_ pairs: [(String, String)]) -> Data {
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
