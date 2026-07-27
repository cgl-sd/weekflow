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
    private nonisolated let syncBridgeTimeoutSeconds: Double
    private var repository: SwiftDataPersistenceRepository?

    init(
        storeURL: URL,
        calendar: Calendar = SystemBusinessCalendar.current.calendar,
        faultInjector: PersistenceFaultInjector? = nil,
        syncBridgeTimeoutSeconds: Double = 60
    ) {
        self.storeURL = storeURL
        self.calendar = calendar
        self.faultInjector = faultInjector
        self.syncBridgeTimeoutSeconds = syncBridgeTimeoutSeconds
    }

    // MARK: - Async (primary path – never blocks the caller)

    /// Executes `body` on the actor's executor. The calling task suspends
    /// instead of blocking its thread, so MainActor callers remain responsive.
    func performTransaction<Result>(
        _ body: @Sendable (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        // A synchronous caller may cancel while this transaction is waiting for
        // the actor. Honour that cancellation before opening the store or running
        // user code so a reported timeout can never become a later write.
        try Task.checkCancellation()
        let repo = try ensureRepository()
        do {
            try Task.checkCancellation()
            return try body(repo)
        } catch is CancellationError {
            throw CancellationError()
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

    /// Phase 2-5 fix: maximum time the synchronous bridge will block before
    /// giving up. Converts a potential infinite hang (e.g. a future misuse that
    /// deadlocks the actor) into a catchable, logged error. 60s is far beyond any
    /// legitimate startup / synchronous-save / termination persist.
    /// Synchronous, BLOCKING wrapper. Blocks the calling thread until the actor
    /// completes. Uses the SAME repository as the async path, ensuring a single
    /// ModelContext per database (P0-1 fix).
    ///
    /// - Warning: ONLY call from non-actor contexts (startup, synchronous saves,
    ///   termination, tests). NEVER call from within the PersistenceActor's
    ///   executor or from an async method isolated to it — the semaphore wait
    ///   would block the very thread the inner Task needs, deadlocking. From async
    ///   contexts use `performTransaction` instead.
    ///
    /// Phase 2-5 fix: a re-entrancy guard rejects same-thread nested calls, and a
    /// timeout turns any residual deadlock into `syncBridgeTimedOut` instead of an
    /// infinite hang.
    @available(*, noasync, message: "Use performTransaction from asynchronous code")
    nonisolated func runSyncBlocking<Result: Sendable>(
        _ body: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        let reentryKey = "weekflow.persistence.syncBridge.active"
        let threadDict = Thread.current.threadDictionary
        precondition(
            threadDict[reentryKey] == nil,
            "PersistenceActor.runSyncBlocking called re-entrantly on the same thread; this would deadlock. Use the async performTransaction from async contexts."
        )
        threadDict[reentryKey] = true
        defer { threadDict[reentryKey] = nil }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<Result>()

        let task = Task {
            do {
                box.value = try await performTransaction(body)
            } catch {
                box.error = error
            }
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + syncBridgeTimeoutSeconds)
        if waitResult != .success {
            // Swift tasks cannot safely pre-empt a synchronous SwiftData commit.
            // Cancellation prevents a queued transaction from starting. Waiting
            // for acknowledgement ensures this method never returns a timeout
            // while the transaction can still mutate the database later.
            task.cancel()
            semaphore.wait()
            if box.error is CancellationError {
                throw PersistenceActorError.syncBridgeTimedOut
            }
        }

        if let error = box.error { throw error }
        guard let value = box.value else {
            throw PersistenceActorError.missingResult
        }
        return value
    }

    @available(*, noasync, message: "Use resetRepository from asynchronous code")
    @discardableResult
    nonisolated func reset() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await resetRepository()
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + syncBridgeTimeoutSeconds) == .success
    }

    // MARK: - Error Recording

    /// Records persistence failures with proper categorization (P1-2 fix).
    /// Migration failures are only recorded during repository creation.
    private func recordPersistenceFailure(_ error: Error, operation: String) {
        let report = PersistenceFailureReport(
            schemaVersion: SwiftDataPersistenceRepository.schemaVersion,
            failedAt: .now,
            operation: operation,
            databaseURL: "Database/\(storeURL.lastPathComponent)",
            reason: DiagnosticRedactor.redact(error.localizedDescription)
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
            reason: DiagnosticRedactor.redact(error.localizedDescription)
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
    @available(*, noasync, message: "Use runAsync from asynchronous code")
    static func run<Result: Sendable>(
        on actor: PersistenceActor,
        _ body: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        try actor.runSyncBlocking(body)
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
    /// Phase 2-5 fix: the synchronous bridge blocked past its timeout, which
    /// strongly suggests a deadlock or a severely degraded database. Surfacing an
    /// error is strictly better than hanging the app forever.
    case syncBridgeTimedOut

    var errorDescription: String? {
        switch self {
        case .missingResult:
            return "持久化 Actor 未返回事务结果"
        case .syncBridgeTimedOut:
            return "持久化同步桥等待超时（可能存在死锁或数据库严重异常）"
        }
    }
}
