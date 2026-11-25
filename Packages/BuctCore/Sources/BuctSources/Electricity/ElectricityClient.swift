import BuctModel
import BuctNetwork
import Foundation

public actor ElectricityClient {
    private static let gatewayBase = "https://ele.buct.one"
    private static let mobileUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"

    private let transport: BuctHttpTransport

    public init(transport: BuctHttpTransport = .shared) {
        self.transport = transport
    }

    public func fetchReadings(
        targets: [ElectricityRoomTarget],
        studentId: String,
        clientId: String,
        signSecret: String,
        appVersion: String
    ) async throws -> [ElectricityReading] {
        let cleanSid = studentId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanSid.range(of: #"^[A-Za-z0-9]{6,20}$"#, options: .regularExpression) != nil else {
            throw NSError(domain: "ElectricityClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "学号格式无效，无法查询宿舍电费"])
        }
        var results: [ElectricityReading] = []
        for target in targets {
            let reading = try await fetchSingleReading(
                target: target,
                studentId: cleanSid,
                clientId: clientId,
                signSecret: signSecret,
                appVersion: appVersion
            )
            results.append(reading)
        }
        return results
    }

    private func fetchSingleReading(
        target: ElectricityRoomTarget,
        studentId: String,
        clientId: String,
        signSecret: String,
        appVersion: String
    ) async throws -> ElectricityReading {
        var comps = URLComponents(string: "\(Self.gatewayBase)/v1/electricity")!
        comps.queryItems = [
            URLQueryItem(name: "schoolid", value: target.schoolId),
            URLQueryItem(name: "roomid", value: target.roomId)
        ]
        guard let url = comps.url else {
            throw NSError(domain: "ElectricityClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "电费请求地址构造失败"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("\(Self.mobileUA) BuctOne/\(appVersion)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(clientId, forHTTPHeaderField: "X-Client-Id")
        req.setValue(studentId, forHTTPHeaderField: "X-Student-Id")

        let cleanSecret = signSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanSecret.isEmpty {
            let ts = Int64(Date().timeIntervalSince1970)
            let rawSign = "\(studentId):\(clientId):\(target.roomId):\(ts):\(cleanSecret)"
            let sign = BuctCrypto.sha256Hex(rawSign)
            req.setValue("\(ts)", forHTTPHeaderField: "X-Timestamp")
            req.setValue(sign, forHTTPHeaderField: "X-Sign")
        }

        let resp = try await transport.send(req, cookieJar: nil, timeout: 15)
        let text = resp.decodedText()
        guard resp.statusCode == 200 else {
            throw ElectricityParser.parseGatewayError(
                statusCode: resp.statusCode,
                jsonString: text,
                retryAfterHeader: resp.header("Retry-After")
            )
        }
        return try ElectricityParser.parseReading(jsonString: text, target: target)
    }
}
