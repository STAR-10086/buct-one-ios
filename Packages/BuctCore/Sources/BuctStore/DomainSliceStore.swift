import BuctModel
import Foundation

/// 遵循数据层四条铁律的泛型域切片持久化存储：
/// 1. 失败永不产生新 data（旧 data 原样保留）
/// 2. never != emptyConfirmed
/// 3. parserVersion 只增不减
/// 4. capturedAt 单调不减（时钟回拨保护）
public actor DomainSliceStore<T: Codable & Sendable> {
    public let source: String
    public let parserVersion: Int
    public let fileURL: URL

    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }()

    private let decoder = JSONDecoder()

    public init(source: String, parserVersion: Int, fileURL: URL) {
        self.source = source
        self.parserVersion = parserVersion
        self.fileURL = fileURL
    }

    public func load() -> DomainSlice<T> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .never(source: source, parserVersion: parserVersion)
        }
        do {
            let raw = try Data(contentsOf: fileURL)
            return try decoder.decode(DomainSlice<T>.self, from: raw)
        } catch {
            return DomainSlice(
                data: nil,
                provenance: Provenance(
                    source: source,
                    capturedAt: 0,
                    parserVersion: parserVersion,
                    refreshState: .never,
                    complete: false,
                    incompleteReason: "本地快照解码失败"
                ),
                lastError: error.localizedDescription
            )
        }
    }

    @discardableResult
    public func saveSuccess(
        data: T,
        isEmpty: Bool,
        complete: Bool = true,
        incompleteReason: String? = nil,
        nowMillis: Int64? = nil
    ) throws -> DomainSlice<T> {
        let previous = load()
        let currentNow = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        let monotonicTimestamp = max(previous.provenance.capturedAt, currentNow)

        let slice = DomainSlice(
            data: data,
            provenance: Provenance(
                source: source,
                capturedAt: monotonicTimestamp,
                parserVersion: parserVersion,
                refreshState: isEmpty ? .emptyConfirmed : .fresh,
                complete: complete,
                incompleteReason: incompleteReason
            ),
            lastError: nil
        )
        try persist(slice)
        return slice
    }

    @discardableResult
    public func recordFailure(error: String, nowMillis: Int64? = nil) throws -> DomainSlice<T> {
        let previous = load()
        let currentNow = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        let monotonicTimestamp = max(previous.provenance.capturedAt, currentNow)
        let hasOldData = previous.data != nil

        let slice = DomainSlice(
            data: previous.data,
            provenance: Provenance(
                source: source,
                capturedAt: hasOldData ? monotonicTimestamp : 0,
                parserVersion: max(previous.provenance.parserVersion, parserVersion),
                refreshState: hasOldData ? .failedFallback : .never,
                complete: previous.provenance.complete,
                incompleteReason: previous.provenance.incompleteReason
            ),
            lastError: LogRedactor.redact(error)
        )
        try persist(slice)
        return slice
    }

    private func persist(_ slice: DomainSlice<T>) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoded = try encoder.encode(slice)
        try encoded.write(to: fileURL, options: [.atomic])
    }
}
