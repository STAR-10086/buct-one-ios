import BuctModel
import BuctNetwork
import Foundation

public actor EcardClient {
    private static let baseURL = "https://ecard.buct.edu.cn"
    private static let indexURL = "https://ecard.buct.edu.cn/index"
    private static let desktopUA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"

    private let webVpn: BuctWebVpnManager
    private let jar = MatchingMemoryCookieJar()
    private var cachedRsaPublicKey: String = ""

    public init(webVpn: BuctWebVpnManager = .shared) {
        self.webVpn = webVpn
    }

    public func clearSession() {
        jar.clear()
        cachedRsaPublicKey = ""
    }

    public func login(idSerial: String, password: String) async throws {
        jar.clear()
        let rsaPubKey = try await fetchIndexAndRsaKey()
        let payload: [String: Any] = [
            "username": idSerial,
            "password": password,
            "orgid": "2",
            "organcode": "11111",
            "type": "idserial"
        ]
        let body = try buildEncryptedEnvelope(payload: payload, rsaPublicKey: rsaPubKey)
        let text = try await postJSON(path: "/business/loginWebUser", body: body)
        try EcardParser.validateLoginResponse(text)
    }

    public func fetchSnapshot(
        idSerial: String,
        password: String?,
        startDate: String,
        endDate: String,
        pageSize: Int = 20
    ) async throws -> CardSnapshot {
        do {
            return try await fetchSnapshotInternal(idSerial: idSerial, startDate: startDate, endDate: endDate, pageSize: pageSize)
        } catch is EcardAuthError {
            guard let pwd = password, !pwd.isEmpty else {
                throw EcardAuthError("请先登录校园卡查询密码")
            }
            try await login(idSerial: idSerial, password: pwd)
            return try await fetchSnapshotInternal(idSerial: idSerial, startDate: startDate, endDate: endDate, pageSize: pageSize)
        }
    }

    public func fetchTransactionsPage(
        idSerial: String,
        startDate: String,
        endDate: String,
        pageNumber: Int,
        pageSize: Int = 20
    ) async throws -> (total: Int, rows: [CardTransaction]) {
        let payload: [String: Any] = [
            "starttime": startDate,
            "endtime": endDate,
            "tradetype": "-1",
            "datetype": "1",
            "pageNumber": pageNumber,
            "pageSize": pageSize,
            "idserial": idSerial
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = try await postJSON(path: "/business/thirdQuerSelfTrade", body: data)
        return try EcardParser.parseTransactions(jsonString: text)
    }

    // MARK: - Internal

    private func fetchSnapshotInternal(
        idSerial: String,
        startDate: String,
        endDate: String,
        pageSize: Int
    ) async throws -> CardSnapshot {
        let rsaKey = cachedRsaPublicKey.isEmpty ? (try await fetchIndexAndRsaKey()) : cachedRsaPublicKey

        var accTypeMap: [String: String] = [:]
        if let commonBody = try? JSONSerialization.data(withJSONObject: ["names": "acctype"]),
           let commonText = try? await postJSON(path: "/business/queryCommon", body: commonBody) {
            accTypeMap = EcardParser.parseAccTypeMap(jsonString: commonText)
        }

        let userBody = try buildEncryptedEnvelope(payload: ["idserial": idSerial], rsaPublicKey: rsaKey)
        let userText = try await postJSON(path: "/core/getCardUserInfoByIdserial", body: userBody)
        let account = try EcardParser.parseCardUserInfo(
            jsonString: userText,
            fallbackIdSerial: idSerial,
            accTypeMap: accTypeMap
        )

        let txPage = try await fetchTransactionsPage(
            idSerial: idSerial,
            startDate: startDate,
            endDate: endDate,
            pageNumber: 0,
            pageSize: pageSize
        )

        return CardSnapshot(
            account: account,
            transactions: txPage.rows,
            queryStartDate: startDate,
            queryEndDate: endDate,
            totalCount: txPage.total,
            hasMore: txPage.rows.count < txPage.total
        )
    }

    private func fetchIndexAndRsaKey() async throws -> String {
        var req = URLRequest(url: URL(string: Self.indexURL)!)
        req.httpMethod = "GET"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
        guard resp.statusCode == 200 else {
            throw EcardAuthError("访问校园卡首页失败（HTTP \(resp.statusCode)）")
        }
        guard let key = EcardParser.extractRsaPublicKey(fromIndexHtml: resp.decodedText()), !key.isEmpty else {
            throw EcardAuthError("未能解析校园卡加密公钥")
        }
        cachedRsaPublicKey = key
        return key
    }

    private func postJSON(path: String, body: Data) async throws -> String {
        var req = URLRequest(url: URL(string: "\(Self.baseURL)\(path)")!)
        req.httpMethod = "POST"
        req.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.baseURL, forHTTPHeaderField: "Origin")
        req.setValue(Self.indexURL, forHTTPHeaderField: "Referer")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        req.httpBody = body

        let resp = try await webVpn.execute(req, cookieJar: jar, timeout: 20)
        if resp.isRedirect || resp.statusCode == 401 || resp.statusCode == 403 {
            throw EcardAuthError("校园卡登录已过期（HTTP \(resp.statusCode)）")
        }
        guard resp.statusCode == 200 else {
            throw NSError(domain: "EcardClient", code: resp.statusCode, userInfo: [NSLocalizedDescriptionKey: "校园卡请求失败（HTTP \(resp.statusCode)）"])
        }
        return resp.decodedText()
    }

    private func buildEncryptedEnvelope(payload: [String: Any], rsaPublicKey: String) throws -> Data {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        let aesKeyStr = String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let aesKeyData = Data(aesKeyStr.utf8)
        let plainData = try JSONSerialization.data(withJSONObject: payload)
        let encPayload = try BuctCrypto.aesECBEncrypt(plaintext: plainData, key: aesKeyData)
        let encKey = try BuctCrypto.rsaEncryptPKCS1(plaintext: aesKeyData, spkiBase64: rsaPublicKey)
        let envelope: [String: String] = [
            "data": encPayload.base64EncodedString(),
            "aesKey": encKey.base64EncodedString()
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }
}
