import Foundation

public struct CardAccountInfo: Codable, Sendable, Equatable {
    public let idSerial: String
    public let userName: String
    public let cardNo: String
    public let balanceFen: Int64
    public let accStatus: String
    public let accTypeName: String
    public let createDate: String

    public init(
        idSerial: String = "",
        userName: String = "",
        cardNo: String = "",
        balanceFen: Int64 = 0,
        accStatus: String = "1",
        accTypeName: String = "",
        createDate: String = ""
    ) {
        self.idSerial = idSerial
        self.userName = userName
        self.cardNo = cardNo
        self.balanceFen = balanceFen
        self.accStatus = accStatus
        self.accTypeName = accTypeName
        self.createDate = createDate
    }

    public var balanceYuanText: String {
        CardMoneyFormatter.formatFenToYuan(balanceFen)
    }

    public var maskedIdSerial: String {
        CardMoneyFormatter.maskId(idSerial)
    }
}

public struct CardTransaction: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let txCode: String
    public let summary: String
    public let merchantName: String
    public let posCode: String
    public let amountFen: Int64
    public let balanceAfterFen: Int64
    public let timestampMillis: Int64
    public let timeText: String
    public let isExpense: Bool

    public init(
        id: String,
        txCode: String = "",
        summary: String,
        merchantName: String = "",
        posCode: String = "",
        amountFen: Int64,
        balanceAfterFen: Int64 = 0,
        timestampMillis: Int64 = 0,
        timeText: String = "",
        isExpense: Bool = true
    ) {
        self.id = id
        self.txCode = txCode
        self.summary = summary
        self.merchantName = merchantName
        self.posCode = posCode
        self.amountFen = amountFen
        self.balanceAfterFen = balanceAfterFen
        self.timestampMillis = timestampMillis
        self.timeText = timeText
        self.isExpense = isExpense
    }

    public var signedAmountText: String {
        let absText = CardMoneyFormatter.formatFenToYuan(abs(amountFen))
        return isExpense ? "-\(absText)" : "+\(absText)"
    }

    public var category: CardSpendingCategory {
        CardSpendingCategory.classify(summary: summary, merchant: merchantName)
    }
}

public enum CardSpendingCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case dining = "食堂餐饮"
    case market = "超市购物"
    case shower = "洗浴水控"
    case campusService = "校内服务"
    case other = "其他消费"

    public var id: String { rawValue }

    public static func classify(summary: String, merchant: String) -> CardSpendingCategory {
        let text = "\(summary) \(merchant)".lowercased()
        if text.contains("食堂") || text.contains("餐厅") || text.contains("风味") || text.contains("清真") || text.contains("餐饮") || text.contains("早餐") || text.contains("咖啡") {
            return .dining
        }
        if text.contains("超市") || text.contains("便利") || text.contains("水果") || text.contains("商店") || text.contains("小卖部") {
            return .market
        }
        if text.contains("水控") || text.contains("浴") || text.contains("淋浴") || text.contains("开水") || text.contains("直饮") || text.contains("洗衣") {
            return .shower
        }
        if text.contains("校车") || text.contains("医院") || text.contains("打印") || text.contains("图书") || text.contains("网费") || text.contains("体育") {
            return .campusService
        }
        return .other
    }
}

public struct CardSnapshot: Codable, Sendable, Equatable {
    public var account: CardAccountInfo
    public var transactions: [CardTransaction]
    public var queryStartDate: String
    public var queryEndDate: String
    public var totalCount: Int
    public var hasMore: Bool

    public init(
        account: CardAccountInfo = CardAccountInfo(),
        transactions: [CardTransaction] = [],
        queryStartDate: String = "",
        queryEndDate: String = "",
        totalCount: Int = 0,
        hasMore: Bool = false
    ) {
        self.account = account
        self.transactions = transactions
        self.queryStartDate = queryStartDate
        self.queryEndDate = queryEndDate
        self.totalCount = totalCount
        self.hasMore = hasMore
    }
}

public enum CardMoneyFormatter {
    public static func formatFenToYuan(_ fen: Int64) -> String {
        let sign = fen < 0 ? "-" : ""
        let absVal = abs(fen)
        return String(format: "%@%.2f", sign, Double(absVal) / 100.0)
    }

    public static func maskId(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 6 else { return t }
        return "\(t.prefix(3))****\(t.suffix(3))"
    }
}
