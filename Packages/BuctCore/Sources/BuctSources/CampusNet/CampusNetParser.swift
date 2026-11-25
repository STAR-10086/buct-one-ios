import BuctModel
import Foundation
import SwiftSoup

public struct CampusNetRadInfo: Sendable, Equatable {
    public let isOnline: Bool
    public let username: String
    public let onlineIp: String
    public let productsName: String
    public let billingName: String
    public let sumBytes: Int64
    public let allBytes: Int64
    public let sumSeconds: Int64
    public let userBalance: Double?
    public let walletBalance: Double?
    public let userCharge: Double?
    public let onlineDeviceTotal: Int
}

public struct CampusNetSelfServiceHome: Sendable, Equatable {
    public let accountStatus: String
    public let walletBalance: Double?
    public let productsName: String
    public let billingName: String
    public let trafficText: String
    public let durationText: String
    public let userCharge: Double?
    public let productBalance: Double?
    public let onlineDevices: [CampusNetOnlineDevice]
}

public enum CampusNetParser {
    public static let parserVersion = 2

    public static func parseRadUserInfo(jsonp: String) -> CampusNetRadInfo? {
        let trimmed = jsonp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let jsonStr: String
        if let firstParen = trimmed.firstIndex(of: "("),
           let lastParen = trimmed.lastIndex(of: ")"),
           firstParen < lastParen {
            jsonStr = String(trimmed[trimmed.index(after: firstParen)..<lastParen])
        } else {
            jsonStr = trimmed
        }
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let err = strValue(obj["error"]).lowercased()
        let isOnline = (err == "ok")
        let onlineIp = nonEmpty(strValue(obj["online_ip"]), fallback: strValue(obj["client_ip"]))
        if !isOnline {
            return CampusNetRadInfo(
                isOnline: false,
                username: strValue(obj["user_name"]),
                onlineIp: onlineIp,
                productsName: "",
                billingName: "",
                sumBytes: 0,
                allBytes: 0,
                sumSeconds: 0,
                userBalance: nil,
                walletBalance: nil,
                userCharge: nil,
                onlineDeviceTotal: 0
            )
        }

        return CampusNetRadInfo(
            isOnline: true,
            username: strValue(obj["user_name"]),
            onlineIp: onlineIp,
            productsName: strValue(obj["products_name"]),
            billingName: strValue(obj["billing_name"]),
            sumBytes: int64Value(obj["sum_bytes"]) ?? 0,
            allBytes: int64Value(obj["all_bytes"]) ?? 0,
            sumSeconds: int64Value(obj["sum_seconds"]) ?? 0,
            userBalance: doubleValue(obj["user_balance"]),
            walletBalance: doubleValue(obj["wallet_balance"]),
            userCharge: doubleValue(obj["user_charge"]),
            onlineDeviceTotal: intValue(obj["online_device_total"]) ?? 0
        )
    }

    public static func parseSelfServiceHome(html: String) -> CampusNetSelfServiceHome? {
        guard html.contains("电子钱包") || html.contains("产品信息") || html.contains("w3-container") else {
            return nil
        }
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let hasW3 = ((try? doc.select("#w3-container").size()) ?? 0) > 0
        let listItems = (try? doc.select("li.list-group-item").array()) ?? []
        guard hasW3 || !listItems.isEmpty else { return nil }

        var accountStatus = ""
        var walletBalance: Double?

        for li in listItems {
            let fullText = (try? li.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if fullText.contains("状态") {
                if let clone = li.copy() as? Element {
                    _ = try? clone.select("label, a").remove()
                    let val = (try? clone.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !val.isEmpty { accountStatus = val }
                }
            } else if fullText.contains("电子钱包") {
                if let clone = li.copy() as? Element {
                    _ = try? clone.select("label, a").remove()
                    let val = (try? clone.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    walletBalance = extractNumber(from: val)
                }
            }
        }

        // 在线设备 (#w1-container table tbody tr)
        var devices: [CampusNetOnlineDevice] = []
        if let rows = try? doc.select("#w1-container table tbody tr").array() {
            for row in rows where !isEmptyTableRow(row) {
                let ip = cellText(row: row, colSeq: 1, fallbackIndex: 1)
                let loginTime = cellText(row: row, colSeq: 3, fallbackIndex: 2)
                let billing = cellText(row: row, colSeq: 11, fallbackIndex: 3)
                if !ip.isEmpty {
                    devices.append(CampusNetOnlineDevice(ip: ip, loginTime: loginTime, billingName: billing))
                }
            }
        }

        // 产品信息 (#w3-container table tbody tr)
        var productsName = ""
        var billingName = ""
        var trafficText = ""
        var durationText = ""
        var userCharge: Double?
        var productBalance: Double?

        if let rows = try? doc.select("#w3-container table tbody tr").array() {
            for row in rows where !isEmptyTableRow(row) {
                productsName = cellText(row: row, colSeq: 1, fallbackIndex: 1)
                billingName = cellText(row: row, colSeq: 2, fallbackIndex: 2)
                trafficText = cellText(row: row, colSeq: 3, fallbackIndex: 3)
                durationText = cellText(row: row, colSeq: 4, fallbackIndex: 4)
                userCharge = extractNumber(from: cellText(row: row, colSeq: 6, fallbackIndex: 6))
                productBalance = extractNumber(from: cellText(row: row, colSeq: 7, fallbackIndex: 7))
                break
            }
        }

        return CampusNetSelfServiceHome(
            accountStatus: accountStatus,
            walletBalance: walletBalance,
            productsName: productsName,
            billingName: billingName,
            trafficText: trafficText,
            durationText: durationText,
            userCharge: userCharge,
            productBalance: productBalance,
            onlineDevices: devices
        )
    }

    public static func parsePayRecords(html: String) -> [CampusNetPayRecord] {
        guard let doc = try? SwiftSoup.parse(html),
              let rows = try? doc.select("table.kv-grid-table tbody tr").array() else {
            return []
        }
        var results: [CampusNetPayRecord] = []
        for row in rows where !isEmptyTableRow(row) {
            if results.count >= 20 { break }
            let amount = cellText(row: row, colSeq: 2, fallbackIndex: 1)
            let payType = cellText(row: row, colSeq: 4, fallbackIndex: 2)
            let payTime = cellText(row: row, colSeq: 6, fallbackIndex: 3)
            if !amount.isEmpty || !payTime.isEmpty {
                results.append(CampusNetPayRecord(amountText: amount, payType: payType, payTime: payTime))
            }
        }
        return results
    }

    public static func parseCheckoutRecords(html: String) -> [CampusNetCheckoutRecord] {
        guard let doc = try? SwiftSoup.parse(html),
              let rows = try? doc.select("table.kv-grid-table tbody tr").array() else {
            return []
        }
        var results: [CampusNetCheckoutRecord] = []
        for row in rows where !isEmptyTableRow(row) {
            if results.count >= 12 { break }
            var fee = cellText(row: row, colSeq: 3, fallbackIndex: 2)
            if fee.isEmpty { fee = cellText(row: row, colSeq: 2, fallbackIndex: 1) }
            let product = cellText(row: row, colSeq: 4, fallbackIndex: 3)
            let traffic = cellText(row: row, colSeq: 7, fallbackIndex: 5)
            let duration = cellText(row: row, colSeq: 9, fallbackIndex: 7)
            let time = cellText(row: row, colSeq: 12, fallbackIndex: 8)
            if !fee.isEmpty || !time.isEmpty || !product.isEmpty {
                results.append(
                    CampusNetCheckoutRecord(
                        feeText: fee,
                        productName: product,
                        trafficText: traffic,
                        durationText: duration,
                        checkoutTime: time
                    )
                )
            }
        }
        return results
    }

    public static func merge(
        studentId: String,
        rad: CampusNetRadInfo?,
        home: CampusNetSelfServiceHome?,
        payRecords: [CampusNetPayRecord],
        checkoutRecords: [CampusNetCheckoutRecord]
    ) -> CampusNetSnapshot {
        let devices = home?.onlineDevices ?? []
        let isOnline = (rad?.isOnline ?? false) || !devices.isEmpty
        let deviceTotal = max(rad?.onlineDeviceTotal ?? 0, devices.count)
        let username = nonEmpty(rad?.username ?? "", fallback: studentId)

        return CampusNetSnapshot(
            username: username,
            isOnline: isOnline,
            accountStatus: nonEmpty(home?.accountStatus ?? "", fallback: isOnline ? "在线" : "离线"),
            onlineIp: rad?.onlineIp ?? devices.first?.ip ?? "",
            productsName: nonEmpty(home?.productsName ?? "", fallback: rad?.productsName ?? ""),
            billingName: nonEmpty(home?.billingName ?? "", fallback: rad?.billingName ?? ""),
            sumBytes: rad?.sumBytes ?? 0,
            allBytes: rad?.allBytes ?? 0,
            sumSeconds: rad?.sumSeconds ?? 0,
            trafficText: home?.trafficText ?? "",
            durationText: home?.durationText ?? "",
            userBalance: home?.productBalance ?? rad?.userBalance,
            walletBalance: home?.walletBalance ?? rad?.walletBalance,
            userCharge: home?.userCharge ?? rad?.userCharge,
            onlineDeviceTotal: deviceTotal,
            onlineDevices: devices,
            payRecords: payRecords,
            checkoutRecords: checkoutRecords
        )
    }

    // MARK: - Helpers

    private static func isEmptyTableRow(_ row: Element) -> Bool {
        if ((try? row.select(".empty").size()) ?? 0) > 0 { return true }
        let tds = (try? row.select("td").array()) ?? []
        if tds.isEmpty { return true }
        if tds.count == 1, ((try? tds[0].hasAttr("colspan")) ?? false) { return true }
        return false
    }

    private static func cellText(row: Element, colSeq: Int, fallbackIndex: Int) -> String {
        if let el = try? row.select("td[data-col-seq=\(colSeq)]").first(),
           let text = try? el.text().trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        let tds = (try? row.select("td").array()) ?? []
        if fallbackIndex >= 0 && fallbackIndex < tds.count {
            return (try? tds[fallbackIndex].text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        }
        return ""
    }

    private static func extractNumber(from text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        guard let regex = try? NSRegularExpression(pattern: #"[-+]?\d+(?:\.\d+)?"#),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range, in: cleaned) else {
            return nil
        }
        return Double(cleaned[range])
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
}
