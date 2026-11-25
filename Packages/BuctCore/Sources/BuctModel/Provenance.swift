import Foundation

/// 校园数据域的五种刷新状态。
/// 铁律：never != emptyConfirmed，未同步过不能显示「没有数据」。
public enum RefreshState: String, Codable, Sendable, CaseIterable {
    /// 刚同步成功且有有效数据
    case fresh
    /// 本地已有历史快照，但已过期
    case stale
    /// 已成功同步且服务端明确返回空列表
    case emptyConfirmed
    /// 本次同步失败，保留旧快照作为兜底
    case failedFallback
    /// 从未成功同步过
    case never

    public var displayLabel: String {
        switch self {
        case .fresh: return "已同步"
        case .stale: return "待刷新"
        case .emptyConfirmed: return "暂无内容"
        case .failedFallback: return "使用缓存"
        case .never: return "未同步"
        }
    }
}

public struct Completeness: Codable, Sendable, Equatable {
    public let complete: Bool
    public let reason: String?
    public let expectedCount: Int?
    public let actualCount: Int

    public init(
        complete: Bool,
        reason: String? = nil,
        expectedCount: Int? = nil,
        actualCount: Int = 0
    ) {
        self.complete = complete
        self.reason = reason
        self.expectedCount = expectedCount
        self.actualCount = actualCount
    }
}

public struct Provenance: Codable, Sendable, Equatable {
    public let source: String
    public let capturedAt: Int64
    public let parserVersion: Int
    public let refreshState: RefreshState
    public let complete: Bool
    public let incompleteReason: String?

    public init(
        source: String,
        capturedAt: Int64,
        parserVersion: Int,
        refreshState: RefreshState,
        complete: Bool = true,
        incompleteReason: String? = nil
    ) {
        self.source = source
        self.capturedAt = capturedAt
        self.parserVersion = parserVersion
        self.refreshState = refreshState
        self.complete = complete
        self.incompleteReason = incompleteReason
    }
}

public struct DomainSlice<T: Codable & Sendable>: Codable, Sendable {
    public let data: T?
    public let provenance: Provenance
    public let lastError: String?

    public init(data: T?, provenance: Provenance, lastError: String? = nil) {
        self.data = data
        self.provenance = provenance
        self.lastError = lastError
    }

    public static func never(source: String, parserVersion: Int) -> DomainSlice<T> {
        DomainSlice(
            data: nil,
            provenance: Provenance(
                source: source,
                capturedAt: 0,
                parserVersion: parserVersion,
                refreshState: .never,
                complete: true,
                incompleteReason: nil
            ),
            lastError: nil
        )
    }
}
