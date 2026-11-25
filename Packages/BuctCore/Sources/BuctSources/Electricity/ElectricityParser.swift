import BuctModel
import Foundation

public struct ElectricityGatewayError: Error, LocalizedError, Sendable {
    public let statusCode: Int
    public let message: String
    public let isBanned: Bool
    public let retryAfterSeconds: Int?

    public init(statusCode: Int, message: String, isBanned: Bool = false, retryAfterSeconds: Int? = nil) {
        self.statusCode = statusCode
        self.message = message
        self.isBanned = isBanned
        self.retryAfterSeconds = retryAfterSeconds
    }

    public var errorDescription: String? { message }
}

public enum ElectricityParser {
    public static let parserVersion = 1

    public static func parseCatalog(data: Data) throws -> ElectricityRoomCatalog {
        let raw = try JSONDecoder().decode(ElectricityRoomCatalog.self, from: data)
        let filteredCampuses = raw.campuses.compactMap { campus -> ElectricityCampusOption? in
            let buildings = campus.buildings.compactMap { bld -> ElectricityBuildingOption? in
                let floors = bld.floors.compactMap { flr -> ElectricityFloorOption? in
                    let rooms = flr.rooms.filter { !$0.roomId.isEmpty && !$0.name.isEmpty }
                    guard !rooms.isEmpty else { return nil }
                    return ElectricityFloorOption(floorId: flr.floorId, name: flr.name, rooms: rooms)
                }
                guard !floors.isEmpty else { return nil }
                return ElectricityBuildingOption(buildingId: bld.buildingId, name: bld.name, floors: floors)
            }
            guard !buildings.isEmpty else { return nil }
            return ElectricityCampusOption(
                schoolId: campus.schoolId,
                name: campus.name,
                hasMeterType: campus.hasMeterType,
                buildings: buildings
            )
        }
        return ElectricityRoomCatalog(factorycode: raw.factorycode, crawledAt: raw.crawledAt, campuses: filteredCampuses)
    }

    public static func parseReading(jsonString: String, target: ElectricityRoomTarget) throws -> ElectricityReading {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ElectricityParser", code: -1, userInfo: [NSLocalizedDescriptionKey: "电费响应格式异常"])
        }

        let balanceText = strValue(obj["balanceText"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var balanceValue = doubleValue(obj["balanceValue"])
        if balanceValue == nil, !balanceText.isEmpty {
            balanceValue = extractFirstDouble(from: balanceText)
        }

        var unit = strValue(obj["unit"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if unit.isEmpty {
            if balanceText.contains("kWh") || balanceText.contains("度") {
                unit = "kWh"
            } else {
                unit = "元"
            }
        }

        let finalText: String
        if !balanceText.isEmpty {
            finalText = balanceText
        } else if let val = balanceValue {
            finalText = String(format: "%.2f %@", val, unit)
        } else {
            finalText = "--"
        }

        let queriedAt = int64Value(obj["queriedAt"]) ?? Int64(Date().timeIntervalSince1970)
        let fromCache = boolValue(obj["fromCache"])
        let accountStatus = strValue(obj["accountStatus"]).isEmpty ? "1" : strValue(obj["accountStatus"])

        return ElectricityReading(
            schoolId: target.schoolId,
            roomId: target.roomId,
            campusName: nonEmpty(strValue(obj["campusName"]), fallback: target.campusName),
            buildingName: nonEmpty(strValue(obj["buildingName"]), fallback: target.buildingName),
            floorName: nonEmpty(strValue(obj["floorName"]), fallback: target.floorName),
            roomName: nonEmpty(strValue(obj["roomName"]), fallback: target.roomName),
            meterType: nonEmpty(strValue(obj["meterType"]), fallback: target.meterType),
            balanceText: finalText,
            balanceValue: balanceValue,
            unit: unit,
            accountStatus: accountStatus,
            queriedAt: queriedAt,
            fromCache: fromCache
        )
    }

    public static func parseGatewayError(statusCode: Int, jsonString: String, retryAfterHeader: String?) -> ElectricityGatewayError {
        var serverMessage = ""
        var banned = false
        var retryAfter = retryAfterHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        if let data = jsonString.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            serverMessage = strValue(obj["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
            banned = boolValue(obj["banned"]) || serverMessage.contains("暂停")
            if let r = intValue(obj["retryAfterSeconds"]) {
                retryAfter = r
            }
        }

        let friendly: String
        switch statusCode {
        case 400:
            friendly = serverMessage.isEmpty ? "宿舍参数无效，请重新选择房间" : serverMessage
        case 401:
            friendly = serverMessage.isEmpty ? "电费网关签名校验失败" : serverMessage
        case 403:
            friendly = serverMessage.isEmpty ? "当前学号已被电费网关限制查询" : serverMessage
        case 429:
            if let sec = retryAfter, sec > 0 {
                let mins = max(1, (sec + 59) / 60)
                friendly = serverMessage.isEmpty ? "切换宿舍过于频繁，请约 \(mins) 分钟后再试" : "\(serverMessage)（约 \(mins) 分钟后重试）"
            } else {
                friendly = serverMessage.isEmpty ? "查询过于频繁，请稍后再试" : serverMessage
            }
        case 503:
            friendly = serverMessage.isEmpty ? "电费查询网关维护中，请稍后再试" : serverMessage
        default:
            friendly = serverMessage.isEmpty ? "电费查询失败（HTTP \(statusCode)）" : serverMessage
        }

        return ElectricityGatewayError(
            statusCode: statusCode,
            message: friendly,
            isBanned: banned || statusCode == 403,
            retryAfterSeconds: retryAfter
        )
    }

    private static func extractFirstDouble(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?\d+(?:\.\d+)?"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return Double(text[range])
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    private static func strValue(_ raw: Any?) -> String {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }

    private static func doubleValue(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func intValue(_ raw: Any?) -> Int? {
        if let i = raw as? Int { return i }
        if let n = raw as? NSNumber { return n.intValue }
        if let s = raw as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func int64Value(_ raw: Any?) -> Int64? {
        if let i = raw as? Int64 { return i }
        if let i = raw as? Int { return Int64(i) }
        if let n = raw as? NSNumber { return n.int64Value }
        if let s = raw as? String { return Int64(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func boolValue(_ raw: Any?) -> Bool {
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.intValue != 0 }
        if let s = raw as? String { return s.lowercased() == "true" || s == "1" }
        return false
    }
}
