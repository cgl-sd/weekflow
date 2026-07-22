import Foundation

/// Sole owner of the live SwiftData repository and therefore its ModelContext.
/// All database access is isolated to this actor; callers use `performTransaction`
/// (async, non-blocking) or `runSync` for startup/tests.
///
/// P0-1 Fix: Removed legacy dual-repository architecture. Now only ONE
/// `SwiftDataPersistenceRepository` exists per database, eliminating the risk
/// of stale context conflicts and inconsistent rollback.
actor PersistenceActor {
    private let storeURL: URL
    private let calendar: Calendar
    private let faultInjector: PersistenceFaultInjector?
    private var repository: SwiftDataPersistenceRepository?

    init(
        storeURL: URL,
        calendar: Calendar = SystemBusinessCalendar.current.calendar,
        faultInjector: PersistenceFaultInjector? = nil
    ) {
        self.storeURL = storeURL
        self.calendar = calendar
        self.faultInjector = faultInjector
    }

    // MARK: - Async (primary path – never blocks the caller)

    /// Executes `body` on the actor's executor. The calling task suspends
    /// instead of blocking its thread, so MainActor callers remain responsive.
    func performTransaction<Result>(
        _ body: @Sendable (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        let repo = try ensureRepository()
        do {
            return try body(repo)
        } catch {
            recordPersistenceFailure(error, operation: "transaction")
            throw error
        }
    }

    func resetRepository() { repository = nil }

    private func ensureRepository() throws -> SwiftDataPersistenceRepository {
        if let existing = repository { return existing }
        let created = try SwiftDataPersistenceRepository(
            storeURL: storeURL,
            calendar: calendar,
            faultInjector: faultInjector
        )
        repository = created
        return created
    }

    // MARK: - Synchronous bridge (startup & tests only)

    /// Synchronous wrapper that blocks the calling thread until the actor
    /// completes. Uses the SAME repository as the async path, ensuring a
    /// single ModelContext per database (P0-1 fix).
    ///
    /// - Warning: Only call from non-actor contexts (startup, tests).
    ///   Never call from within the actor's executor.
    nonisolated func runSync<Result: Sendable>(
        _ body: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Result>()

        Task {
            do {
                box.value = try await performTransaction(body)
            } catch {
                box.error = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = box.error { throw error }
        guard let value = box.value else {
            throw PersistenceActorError.missingResult
        }
        return value
    }

    nonisolated func reset() {
        // Synchronous reset for tests - blocks until actor processes it
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await resetRepository()
            semaphore.signal()
        }
        semaphore.wait()
    }

    // MARK: - Error Recording

    /// Records persistence failures with proper categorization (P1-2 fix).
    /// Migration failures are only recorded during repository creation.
    private func recordPersistenceFailure(_ error: Error, operation: String) {
        let report = PersistenceFailureReport(
            schemaVersion: SwiftDataPersistenceRepository.schemaVersion,
            failedAt: .now,
            operation: operation,
            databaseURL: storeURL.path,
            reason: error.localizedDescription
        )
        let url = storeURL.deletingLastPathComponent()
            .appendingPathComponent("persistence-failure.json")
        if let data = try? JSONEncoder.weekflow.encode(report) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Records migration-specific failures (only during repository creation).
    nonisolated func recordMigrationFailure(_ error: Error) {
        let report = PersistenceMigrationFailureReport(
            schemaVersion: SwiftDataPersistenceRepository.schemaVersion,
            failedAt: .now,
            reason: error.localizedDescription
        )
        let url = storeURL.deletingLastPathComponent()
            .appendingPathComponent("migration-failure.json")
        if let data = try? JSONEncoder.weekflow.encode(report) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Thread-safe result transport for the synchronous actor bridge.
///
/// P4-17/18 fix: Safety invariant — `value`/`error` are written exactly once
/// inside the `Task` closure, then read after `semaphore.wait()`. The
/// DispatchSemaphore provides the happens-before edge that guarantees the
/// reader sees the written values. No concurrent access occurs.
private final class ResultBox<Result>: @unchecked Sendable {
    var value: Result?
    var error: Error?
}

private struct PersistenceMigrationFailureReport: Codable {
    let schemaVersion: Int
    let failedAt: Date
    let reason: String
}

/// Persistence failure report with operation context (P1-2 fix).
private struct PersistenceFailureReport: Codable {
    let schemaVersion: Int
    let failedAt: Date
    let operation: String
    let databaseURL: String
    let reason: String
}

/// Compatibility bridge for the existing synchronous command surface (startup,
/// tests). Production mutations should prefer the async `performTransaction`.
enum PersistenceActorBridge {
    /// Synchronous – blocks the calling thread until the actor completes.
    /// Uses the SAME repository as async operations (P0-1 fix).
    static func run<Result: Sendable>(
        on actor: PersistenceActor,
        _ body: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        try actor.runSync(body)
    }

    /// Async – suspends the calling task without blocking the thread.
    /// MainActor callers remain responsive during disk I/O.
    static func runAsync<Result: Sendable>(
        on actor: PersistenceActor,
        _ body: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) async throws -> Result {
        try await actor.performTransaction(body)
    }
}

enum PersistenceActorError: LocalizedError {
    case missingResult

    var errorDescription: String? { "持久化 Actor 未返回事务结果" }
}
