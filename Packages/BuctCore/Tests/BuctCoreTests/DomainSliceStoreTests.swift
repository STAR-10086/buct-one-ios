import BuctModel
@testable import BuctStore
import Foundation
import XCTest

final class DomainSliceStoreTests: XCTestCase {

    private func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BuctCoreTests_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("slice.json")
    }

    func testDataLayerFourIronLaws() async throws {
        let fileURL = makeTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = DomainSliceStore<[String]>(source: "test_domain", parserVersion: 2, fileURL: fileURL)

        // 1. 从未同步：never != emptyConfirmed
        let initial = await store.load()
        XCTAssertEqual(initial.provenance.refreshState, .never)
        XCTAssertNil(initial.data)

        // 2. 空列表确认：emptyConfirmed
        let emptySlice = try await store.saveSuccess(data: [], isEmpty: true, nowMillis: 1_000)
        XCTAssertEqual(emptySlice.provenance.refreshState, .emptyConfirmed)
        XCTAssertEqual(emptySlice.data, [])

        // 3. 成功写入有效数据 + 时钟回拨保护（capturedAt 单调不减）
        let freshSlice = try await store.saveSuccess(data: ["高数", "大物"], isEmpty: false, nowMillis: 5_000)
        XCTAssertEqual(freshSlice.provenance.refreshState, .fresh)
        XCTAssertEqual(freshSlice.provenance.capturedAt, 5_000)

        let backClockSlice = try await store.saveSuccess(data: ["高数", "大物", "线代"], isEmpty: false, nowMillis: 3_000)
        XCTAssertEqual(backClockSlice.provenance.capturedAt, 5_000, "系统时钟回拨时 capturedAt 不得倒退")

        // 4. 失败永不产生新 data：旧 data 原样保留，状态转为 failedFallback
        let failedSlice = try await store.recordFailure(error: "timeout 2023010099", nowMillis: 6_000)
        XCTAssertEqual(failedSlice.provenance.refreshState, .failedFallback)
        XCTAssertEqual(failedSlice.data, ["高数", "大物", "线代"])
        XCTAssertEqual(failedSlice.lastError, "timeout ***")

        // 重新实例化验证原子落盘持久化
        let reloadedStore = DomainSliceStore<[String]>(source: "test_domain", parserVersion: 2, fileURL: fileURL)
        let reloaded = await reloadedStore.load()
        XCTAssertEqual(reloaded.provenance.refreshState, .failedFallback)
        XCTAssertEqual(reloaded.data, ["高数", "大物", "线代"])
    }
}
