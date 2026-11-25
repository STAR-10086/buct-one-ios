import Foundation

public struct CampusNetOnlineDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(ip)|\(loginTime)" }
    public let ip: String
    public let loginTime: String
    public let billingName: String

    public init(ip: String, loginTime: String = "", billingName: String = "") {
        self.ip = ip
        self.loginTime = loginTime
        self.billingName = billingName
    }
}

public struct CampusNetPayRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(payTime)|\(amountText)|\(payType)" }
    public let amountText: String
    public let payType: String
    public let payTime: String

    public init(amountText: String, payType: String = "", payTime: String = "") {
        self.amountText = amountText
        self.payType = payType
        self.payTime = payTime
    }
}

public struct CampusNetCheckoutRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(checkoutTime)|\(productName)|\(feeText)" }
    public let feeText: String
    public let productName: String
    public let trafficText: String
    public let durationText: String
    public let checkoutTime: String

    public init(
        feeText: String,
        productName: String = "",
        trafficText: String = "",
        durationText: String = "",
        checkoutTime: String = ""
    ) {
        self.feeText = feeText
        self.productName = productName
        self.trafficText = trafficText
        self.durationText = durationText
        self.checkoutTime = checkoutTime
    }
}

public struct CampusNetSnapshot: Codable, Sendable, Equatable {
    public let username: String
    public let isOnline: Bool
    public let accountStatus: String
    public let onlineIp: String
    public let productsName: String
    public let billingName: String
    public let sumBytes: Int64
    public let allBytes: Int64
    public let sumSeconds: Int64
    public let trafficText: String
    public let durationText: String
    public let userBalance: Double?
    public let walletBalance: Double?
    public let userCharge: Double?
    public let onlineDeviceTotal: Int
    public let onlineDevices: [CampusNetOnlineDevice]
    public let payRecords: [CampusNetPayRecord]
    public let checkoutRecords: [CampusNetCheckoutRecord]

    public init(
        username: String = "",
        isOnline: Bool = false,
        accountStatus: String = "",
        onlineIp: String = "",
        productsName: String = "",
        billingName: String = "",
        sumBytes: Int64 = 0,
        allBytes: Int64 = 0,
        sumSeconds: Int64 = 0,
        trafficText: String = "",
        durationText: String = "",
        userBalance: Double? = nil,
        walletBalance: Double? = nil,
        userCharge: Double? = nil,
        onlineDeviceTotal: Int = 0,
        onlineDevices: [CampusNetOnlineDevice] = [],
        payRecords: [CampusNetPayRecord] = [],
        checkoutRecords: [CampusNetCheckoutRecord] = []
    ) {
        self.username = username
        self.isOnline = isOnline
        self.accountStatus = accountStatus
        self.onlineIp = onlineIp
        self.productsName = productsName
        self.billingName = billingName
        self.sumBytes = sumBytes
        self.allBytes = allBytes
        self.sumSeconds = sumSeconds
        self.trafficText = trafficText
        self.durationText = durationText
        self.userBalance = userBalance
        self.walletBalance = walletBalance
        self.userCharge = userCharge
        self.onlineDeviceTotal = onlineDeviceTotal
        self.onlineDevices = onlineDevices
        self.payRecords = payRecords
        self.checkoutRecords = checkoutRecords
    }

    /// 北化深澜校园网采用十进制 1000 进位（1 GB = 1,000,000,000 B）。
    public static func formatTraffic(bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let d = Double(bytes)
        if d >= 1_000_000_000_000 { return String(format: "%.2f TB", d / 1_000_000_000_000) }
        if d >= 1_000_000_000 { return String(format: "%.2f GB", d / 1_000_000_000) }
        if d >= 1_000_000 { return String(format: "%.2f MB", d / 1_000_000) }
        if d >= 1_000 { return String(format: "%.1f KB", d / 1_000) }
        return "\(bytes) B"
    }

    public static func formatDuration(seconds: Int64) -> String {
        guard seconds > 0 else { return "0 分钟" }
        let hours = seconds / 3600
        let mins = (seconds % 3600) / 60
        if hours > 0 { return "\(hours) 小时 \(mins) 分钟" }
        return "\(mins) 分钟"
    }

    public var displayTrafficText: String {
        if !trafficText.isEmpty { return trafficText }
        return Self.formatTraffic(bytes: sumBytes)
    }

    public var displayDurationText: String {
        if !durationText.isEmpty { return durationText }
        return Self.formatDuration(seconds: sumSeconds)
    }
}
