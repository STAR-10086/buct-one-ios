import BuctModel
import BuctNetwork
import Foundation

public struct EcardAuthError: Error, LocalizedError, Sendable {
    public let message: String
    public let invalidCredentials: Bool

    public init(_ message: String = "校园卡登录已过期或密码错误", invalidCredentials: Bool = false) {
        self.message = message
        self.invalidCredentials = invalidCredentials
    }

    public var errorDescription: String? { message }
}

public enum EcardParser {
    public static let parserVersion = 3
    private static let cbcKey = Data("abcdef0123456789".utf8)
    private static let cbcIV = Data("0123456789abcdef".utf8)

    public static func mapErrorMessage(_ codeOrMsg: String) -> String {
        let raw = codeOrMsg.trimmingCharacters(in: .whitespacesAndNewlines)
        switch raw.uppercased() {
        case "CORE20003", "WEB10001":
            return "校园卡密码错误（默认身份证后六位，有字母用 1 代替）"
        case "CORE20004", "WEB20001", "WEB20002":
            return "未找到该学工号对应的校园卡账户"
        case "CORE21120":
            return "登录失败次数过多，请稍后再试"
        case "WEB10003":
            return "初始密码禁用登录，请先在企业微信或圈存机修改卡密码"
        case "CORE20005":
            return "校园卡账户状态异常"
        case "CORE50006":
            return "该校园卡已销户"
        case "CORE50009":
            return "该校园卡已预销户"
        case "CORE80030":
            return "此卡已上交遗失卡"
        case "WEB20004":
            return "校园卡会话已过期，请重新登录"
        case "WEB20005":
            return "请求签名校验失败，请重试"
        case "WEB20003", "CORE20107":
            return "请求参数校验失败"
        case "CORE20222":
            return "存在多条校园卡档案，请联系学校信息中心处理"
        case "CORE20131":
            return "未查询到相关信息"
        case "CORE10003", "CORE10004", "CORE10005":
            return "校园卡服务暂时异常，请稍后重试（\(raw)）"
        default:
            return raw.isEmpty ? "校园卡请求失败，请稍后重试" : raw
        }
    }

    public static func extractRsaPublicKey(fromIndexHtml html: String) -> String? {
        let pattern = #"rasPublicKey['"]\s*,\s*['"]([^'"]+)['"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\n", with: "")
            .replacingOccurrences(of: "\\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parseAccTypeMap(jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let res = root["resultData"] as? [String: Any],
              let list = res["acctype"] as? [[String: Any]] else {
            return [:]
        }
        var map: [String: String] = [:]
        for item in list {
            let code = strValue(item["acctypecode"])
            let name = strValue(item["acctypename"])
            if !code.isEmpty && !name.isEmpty {
                map[code] = name
            }
        }
        return map
    }

    public static func parseCardUserInfo(
        jsonString: String,
        fallbackIdSerial: String,
        accTypeMap: [String: String]
    ) throws -> CardAccountInfo {
        let root = try parseEnvelope(jsonString)
        let decryptedDict: [String: Any]
        if let rawCipher = root["resultData"] as? String, !rawCipher.isEmpty {
            guard let cipherData = Data(base64Encoded: rawCipher.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw NSError(domain: "EcardParser", code: -2, userInfo: [NSLocalizedDescriptionKey: "校园卡用户信息密文无效"])
            }
            let plainData = try BuctCrypto.aesCBCDecryptZeroPadded(ciphertext: cipherData, key: cbcKey, iv: cbcIV)
            guard let parsed = try? JSONSerialization.jsonObject(with: plainData) as? [String: Any] else {
                throw NSError(domain: "EcardParser", code: -3, userInfo: [NSLocalizedDescriptionKey: "校园卡用户信息解密后格式异常"])
            }
            decryptedDict = parsed
        } else if let direct = root["resultData"] as? [String: Any] {
            decryptedDict = direct
        } else {
            throw NSError(domain: "EcardParser", code: -4, userInfo: [NSLocalizedDescriptionKey: "校园卡用户信息为空"])
        }

        let accInfo = (decryptedDict["accountinfo"] as? [String: Any]) ?? [:]
        let userInfo = (accInfo["cardUserinfo"] as? [String: Any]) ?? (decryptedDict["cardUserinfo"] as? [String: Any]) ?? [:]

        let balanceFen = int64Value(accInfo["balance"]) ?? 0
        let createDate = strValue(accInfo["createdate"])
        let userName = strValue(userInfo["username"])
        let idSerial = nonEmpty(strValue(userInfo["idserial"]), fallback: fallbackIdSerial)

        let cards = normalizeCardInfoList(decryptedDict["cardinfos"])
        let chosenCard = cards.first(where: { strValue($0["accstatus"]) == "1" }) ?? cards.first
        let cardNo = strValue(chosenCard?["cardno"]).isEmpty ? strValue(chosenCard?["cardid"]) : strValue(chosenCard?["cardno"])
        let accStatus = nonEmpty(strValue(chosenCard?["accstatus"]), fallback: "1")
        let accTypeCode = nonEmpty(strValue(chosenCard?["cardtype"]), fallback: strValue(chosenCard?["acctypecode"]))
        let accTypeName = accTypeMap[accTypeCode] ?? strValue(chosenCard?["acctypename"])

        return CardAccountInfo(
            idSerial: idSerial,
            userName: userName,
            cardNo: cardNo,
            balanceFen: balanceFen,
            accStatus: accStatus,
            accTypeName: accTypeName,
            createDate: createDate
        )
    }

    public static func parseTransactions(jsonString: String) throws -> (total: Int, rows: [CardTransaction]) {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EcardAuthError("校园卡流水返回非 JSON 内容，会话可能已失效")
        }
        let message = strValue(root["message"])
        if message.caseInsensitiveCompare("WEB20004") == .orderedSame {
            throw EcardAuthError("校园卡会话已过期")
        }
        if message.caseInsensitiveCompare("WEB20006") == .orderedSame {
            return (0, [])
        }
        let ok = (root["success"] as? Bool) ?? (root["isSuccess"] as? Bool) ?? true
        if !ok {
            let msg = mapErrorMessage(nonEmpty(message, fallback: strValue(root["msg"])))
            throw NSError(domain: "EcardParser", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        let res = (root["resultData"] as? [String: Any]) ?? [:]
        let total = intValue(res["total"]) ?? 0
        let rawRows = (res["rows"] as? [[String: Any]]) ?? []

        var seen = Set<String>()
        var items: [CardTransaction] = []
        for row in rawRows {
            let txCode = strValue(row["txcode"])
            let txName = strValue(row["txname"])
            let rawSummary = strValue(row["summary"])
            let merchant = nonEmpty(strValue(row["mername"]), fallback: nonEmpty(txName, fallback: strValue(row["posname"])))
            let posCode = nonEmpty(strValue(row["poscode"]), fallback: strValue(row["stationcode"]))
            let amountFen = int64Value(row["txamt"]) ?? 0
            let balanceAfterFen = int64Value(row["balance"]) ?? 0
            let (tsMs, timeText) = parseTxDate(row["txdate"])

            let displaySummary: String
            if txCode == "2241" {
                displaySummary = "发放补助"
            } else if txCode == "2239" || txCode == "2240" {
                displaySummary = nonEmpty(rawSummary, fallback: nonEmpty(merchant, fallback: "补助发放"))
            } else {
                displaySummary = nonEmpty(merchant, fallback: nonEmpty(rawSummary, fallback: "校园卡交易"))
            }

            let isExpense: Bool
            if amountFen < 0 {
                isExpense = true
            } else if txCode == "2241" || txCode == "2239" || txCode == "2240" || rawSummary.contains("充值") || rawSummary.contains("补助") || rawSummary.contains("退款") || txName.contains("充值") || txName.contains("补助") {
                isExpense = false
            } else {
                isExpense = false
            }

            let journo = nonEmpty(strValue(row["journo"]), fallback: nonEmpty(strValue(row["id"]), fallback: "\(tsMs)"))
            let dedupId = "\(journo)|\(txCode)|\(amountFen)|\(balanceAfterFen)|\(posCode)"
            guard seen.insert(dedupId).inserted else { continue }

            items.append(
                CardTransaction(
                    id: dedupId,
                    txCode: txCode,
                    summary: displaySummary,
                    merchantName: merchant,
                    posCode: posCode,
                    amountFen: abs(amountFen),
                    balanceAfterFen: balanceAfterFen,
                    timestampMillis: tsMs,
                    timeText: timeText,
                    isExpense: isExpense
                )
            )
        }
        return (max(total, items.count), items)
    }

    public static func validateLoginResponse(_ jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EcardAuthError("校园卡登录响应异常", invalidCredentials: false)
        }
        let ok = (root["success"] as? Bool) ?? (root["isSuccess"] as? Bool) ?? (strValue(root["resultCode"]) == "0000")
        if !ok {
            let rawCode = nonEmpty(strValue(root["message"]), fallback: strValue(root["msg"]))
            let mapped = mapErrorMessage(rawCode)
            let upper = rawCode.uppercased()
            let badCred = ["CORE20003", "WEB10001", "WEB10003", "CORE20004", "WEB20001", "WEB20002"].contains(upper)
                || mapped.contains("密码") || mapped.contains("锁定")
            throw EcardAuthError(mapped, invalidCredentials: badCred)
        }
    }

    // MARK: - Helpers

    private static func parseEnvelope(_ jsonString: String) throws -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EcardAuthError("校园卡接口返回非 JSON 内容，会话可能已失效")
        }
        let message = strValue(root["message"])
        if message.caseInsensitiveCompare("WEB20004") == .orderedSame {
            throw EcardAuthError("校园卡会话已过期")
        }
        let ok = (root["success"] as? Bool) ?? (root["isSuccess"] as? Bool) ?? true
        if !ok {
            let msg = mapErrorMessage(nonEmpty(message, fallback: strValue(root["msg"])))
            throw NSError(domain: "EcardParser", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return root
    }

    private static func normalizeCardInfoList(_ raw: Any?) -> [[String: Any]] {
        if let arr = raw as? [[String: Any]] { return arr }
        if let dict = raw as? [String: Any] {
            if dict["cardno"] != nil || dict["accstatus"] != nil || dict["acctypecode"] != nil {
                return [dict]
            }
            return dict.values.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    private static func parseTxDate(_ raw: Any?) -> (millis: Int64, text: String) {
        if let ms = int64Value(raw), ms > 10_000_000_000 {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "zh_CN")
            fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
            fmt.dateFormat = "yyyy-MM-dd HH:mm"
            return (ms, fmt.string(from: Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)))
        }
        let text = strValue(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return (0, "") }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "zh_CN")
        fmt.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = fmt.date(from: text) {
            return (Int64(date.timeIntervalSince1970 * 1000), String(text.prefix(16)))
        }
        return (0, text)
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    private static func strValue(_ raw: Any?) -> String {
        if let s = raw as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
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
}
