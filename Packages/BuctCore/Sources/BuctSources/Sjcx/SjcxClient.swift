import BuctModel
import BuctNetwork
import Foundation

public actor SjcxClient {
    private static let baseURL = "https://sjcx.buct.edu.cn"
    private static let ssoLoginURL = "https://sidportal.buct.edu.cn/login?service=https%3A%2F%2Fsjcx.buct.edu.cn%2Fbuct%2F"
    private static let sidPortalHost = "sidportal.buct.edu.cn"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    private let transport: BuctHttpTransport
    private let jar = MatchingMemoryCookieJar()
    private var jwt: String = ""
    private var rsaPublicKey: String = ""
    private var yearterm: String = ""

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func clearSession() {
        jar.clear()
        jwt = ""
        rsaPublicKey = ""
        yearterm = ""
    }

    public func fetchSnapshot(sidCookies: String) async throws -> SjcxSnapshot {
        try await withAuthRetry(sidCookies: sidCookies) {
            var currentWeek = 1
            if let prodText = try? await postSigned(path: "/config/sys/menu/listProductByStu", query: [:], body: nil),
               let prodData = try? SjcxParser.parseEnvelope(prodText) as? [String: Any],
               let w = prodData["week"] as? Int {
                currentWeek = w
            }

            // 激活实验教学模块上下文 (menuId=9900)
            _ = try? await postSigned(path: "/config/sys/menu/listStuMenuByProduct", query: ["menuId": "9900"], body: nil)
            let pageBody: [String: Any] = ["currentPage": 1, "pageSize": 100]
            let reportsText = (try? await postSigned(path: "/fteach/teach/report/listStuReportPage", query: [:], body: pageBody)) ?? ""
            let schedulesText = (try? await postSigned(path: "/fteach/teach/timeTable/listStuTimePage", query: [:], body: pageBody)) ?? ""
            let scoresText = (try? await postSigned(path: "/fteach/teach/score/listStuScorePage", query: [:], body: pageBody)) ?? ""

            // 激活创新学分模块上下文 (menuId=11900)
            _ = try? await postSigned(path: "/config/sys/menu/listStuMenuByProduct", query: ["menuId": "11900"], body: nil)
            let openBody: [String: Any] = ["currentPage": 1, "pageSize": 50, "state": 1, "keyword": ""]
            let endedBody: [String: Any] = ["currentPage": 1, "pageSize": 50, "state": 2, "keyword": ""]
            let openText = (try? await postSigned(path: "/fcredit/credit/creProjectTime/listStuBatchPage", query: [:], body: openBody)) ?? ""
            let endedText = (try? await postSigned(path: "/fcredit/credit/creProjectTime/listStuBatchPage", query: [:], body: endedBody)) ?? ""
            let myText = (try? await postSigned(path: "/fcredit/credit/creProjectStu/stu/listMyBatchPage", query: [:], body: pageBody)) ?? ""
            let creditText = (try? await postSigned(path: "/fcredit/credit/creStu/stu/listTotalCreditPage", query: [:], body: pageBody)) ?? ""
            let noSignText = (try? await postSigned(path: "/fcredit/credit/creProjectStu/stu/getNoSignNum", query: [:], body: nil)) ?? ""

            let credits = SjcxParser.parseCredits(creditText)
            return SjcxSnapshot(
                yearterm: yearterm,
                currentWeek: currentWeek,
                reports: SjcxParser.parseReports(reportsText),
                schedules: SjcxParser.parseSchedules(schedulesText),
                scores: SjcxParser.parseScores(scoresText),
                openLectures: SjcxParser.parseLectures(openText, isRegistered: false),
                endedLectures: SjcxParser.parseLectures(endedText, isRegistered: false),
                myLectures: SjcxParser.parseLectures(myText, isRegistered: true),
                creditRecords: credits.records,
                totalCredit: credits.total,
                noSignCount: SjcxParser.parseNoSignCount(noSignText)
            )
        }
    }

    public func registerLecture(sidCookies: String, projectTimeId: String) async throws {
        try await withAuthRetry(sidCookies: sidCookies) {
            _ = try? await postSigned(path: "/config/sys/menu/listStuMenuByProduct", query: ["menuId": "11900"], body: nil)
            let text = try await postSigned(
                path: "/fcredit/credit/creProjectStu/stu/StuRegistrationProject",
                query: ["projectTimeId": projectTimeId],
                body: nil
            )
            _ = try SjcxParser.parseEnvelope(text)
        }
    }

    public func cancelLectureRegistration(sidCookies: String, registrationId: String) async throws {
        try await withAuthRetry(sidCookies: sidCookies) {
            _ = try? await postSigned(path: "/config/sys/menu/listStuMenuByProduct", query: ["menuId": "11900"], body: nil)
            let text = try await postSigned(
                path: "/fcredit/credit/creProjectStu/stu/cancelRegistration",
                query: ["id": registrationId],
                body: nil
            )
            _ = try SjcxParser.parseEnvelope(text)
        }
    }

    public func submitLectureExperience(sidCookies: String, registrationId: String, experience: String) async throws {
        try await withAuthRetry(sidCookies: sidCookies) {
            _ = try? await postSigned(path: "/config/sys/menu/listStuMenuByProduct", query: ["menuId": "11900"], body: nil)
            let text = try await postSigned(
                path: "/fcredit/credit/creProjectStu/stu/saveExperience",
                query: [:],
                body: ["creProjectStuId": registrationId, "experience": experience]
            )
            _ = try SjcxParser.parseEnvelope(text)
        }
    }

    // MARK: - Auth & Signing

    private func withAuthRetry<T>(sidCookies: String, _ block: () async throws -> T) async throws -> T {
        if jwt.isEmpty || rsaPublicKey.isEmpty {
            try await authenticate(sidCookies: sidCookies)
        }
        do {
            return try await block()
        } catch is SjcxAuthExpiredError {
            jwt = ""
            rsaPublicKey = ""
            try await authenticate(sidCookies: sidCookies)
            return try await block()
        }
    }

    private func authenticate(sidCookies: String) async throws {
        jar.clear()
        let cleanSid = sidCookies.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSid.isEmpty {
            jar.seed(cookieHeader: cleanSid, setByHost: Self.sidPortalHost)
        }

        var current = URL(string: Self.ssoLoginURL)!
        var extractedJwt = ""

        for _ in 0..<12 {
            var req = URLRequest(url: current)
            req.httpMethod = "GET"
            req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
            if resp.isRedirect, let loc = resp.header("Location") {
                if let token = SjcxParser.extractTokenFromLocation(loc) {
                    extractedJwt = token
                    break
                }
                if let next = URL(string: loc, relativeTo: current)?.absoluteURL {
                    current = next
                    continue
                }
            }
            break
        }

        guard !extractedJwt.isEmpty else {
            throw SjcxAuthExpiredError("未能完成实践教学 CAS 登录，请重新登录统一身份认证")
        }
        jwt = extractedJwt

        var casReq = URLRequest(url: URL(string: "\(Self.baseURL)/config/sys/login/permissions/cas/login")!)
        casReq.httpMethod = "POST"
        casReq.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        casReq.setValue(jwt, forHTTPHeaderField: "Authorization")
        casReq.setValue("null", forHTTPHeaderField: "MenuId")
        casReq.setValue("null", forHTTPHeaderField: "Product")
        casReq.setValue("\(Int64(Date().timeIntervalSince1970 * 1000))", forHTTPHeaderField: "Random")
        casReq.setValue("application/json", forHTTPHeaderField: "Accept")

        let casResp = try await transport.send(casReq, cookieJar: jar, timeout: 20)
        guard casResp.statusCode == 200 else {
            throw SjcxAuthExpiredError("实践教学权限初始化失败（HTTP \(casResp.statusCode)）")
        }
        let loginData = try SjcxParser.parseCasLoginData(casResp.decodedText())
        rsaPublicKey = loginData.rsaKey
        yearterm = loginData.yearterm
    }

    private func postSigned(path: String, query: [String: String], body: [String: Any]?) async throws -> String {
        var comps = URLComponents(string: "\(Self.baseURL)\(path)")!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else {
            throw NSError(domain: "SjcxClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "实践教学请求地址无效"])
        }

        let (xtsign, cnonce) = try buildSignature(query: query, body: body)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(jwt, forHTTPHeaderField: "Authorization")
        req.setValue("null", forHTTPHeaderField: "MenuId")
        req.setValue("null", forHTTPHeaderField: "Product")
        req.setValue(xtsign, forHTTPHeaderField: "Xtsign")
        req.setValue(cnonce, forHTTPHeaderField: "Cnonce")
        req.setValue("\(Int64(Date().timeIntervalSince1970 * 1000))", forHTTPHeaderField: "Random")

        if let body {
            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let resp = try await transport.send(req, cookieJar: jar, timeout: 20)
        if resp.statusCode == 401 || resp.statusCode == 403 {
            throw SjcxAuthExpiredError()
        }
        guard resp.statusCode == 200 else {
            throw NSError(domain: "SjcxClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "实践教学请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp.decodedText()
    }

    private func buildSignature(query: [String: String], body: [String: Any]?) throws -> (xtsign: String, cnonce: String) {
        var map: [String: [String]] = [:]
        for (k, v) in query where !v.isEmpty {
            map[k, default: []].append(v)
        }
        if let body {
            flattenJSON(body, into: &map)
        }
        if map.isEmpty {
            map["Authorization"] = [jwt]
        }

        let zhLocale = Locale(identifier: "zh_CN")
        let sortedKeys = map.keys.sorted { $0.compare($1, locale: zhLocale) == .orderedAscending }
        var concat = ""
        for k in sortedKeys {
            let vals = (map[k] ?? []).sorted { $0.compare($1, locale: zhLocale) == .orderedAscending }
            for v in vals {
                concat += "\(k)=\(v)"
            }
        }
        let clean = concat
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\u{2028}", with: "")
            .replacingOccurrences(of: "\u{2029}", with: "")

        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let nonce = String((0..<32).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let hmac = BuctCrypto.hmacSHA256(data: Data(clean.utf8), key: Data(nonce.utf8))
        let xtsign = hmac.map { String(format: "%02X", $0) }.joined()
        let cnonceData = try BuctCrypto.rsaEncryptPKCS1(plaintext: Data(nonce.utf8), spkiBase64: rsaPublicKey)
        return (xtsign, cnonceData.base64EncodedString())
    }

    private func flattenJSON(_ value: Any, into map: inout [String: [String]]) {
        if let dict = value as? [String: Any] {
            for (k, v) in dict {
                if let subDict = v as? [String: Any] {
                    flattenJSON(subDict, into: &map)
                } else if let arr = v as? [Any] {
                    for elem in arr {
                        if let nested = elem as? [String: Any] {
                            flattenJSON(nested, into: &map)
                        } else {
                            let s = String(describing: elem)
                            if !s.isEmpty { map[k, default: []].append(s) }
                        }
                    }
                } else if !(v is NSNull) {
                    let s = String(describing: v)
                    if !s.isEmpty { map[k, default: []].append(s) }
                }
            }
        }
    }
}
