import Foundation

/// 通用单飞去重协调器：相同 key 的并发异步任务合并为单次执行。
public actor SingleFlightCoordinator {
    private var inFlightTasks: [String: Task<Void, Error>] = [:]

    public init() {}

    public func run(key: String, operation: @escaping @Sendable () async throws -> Void) async throws {
        if let existing = inFlightTasks[key] {
            try await existing.value
            return
        }
        let task = Task {
            try await operation()
        }
        inFlightTasks[key] = task
        defer { inFlightTasks.removeValue(forKey: key) }
        try await task.value
    }
}
