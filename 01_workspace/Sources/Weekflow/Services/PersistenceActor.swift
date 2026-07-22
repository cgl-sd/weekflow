import Foundation

/// Sole owner of the live SwiftData repository and therefore its ModelContext.
/// All database access is isolated to this actor; callers use `performTransaction`
/// (async, non-blocking) or the legacy synchronous bridge for startup/tests.
actor PersistenceActor {
    private let storeURL: URL
    private let calendar: Calendar
    private let faultInjector: PersistenceFaultInjector?
    private var repository: SwiftDataPersistenceRepository?

    /// Legacy serial queue retained only for the synchronous compatibility
    /// bridge used during initialization and deterministic tests.
    nonisolated private let persistenceQueue: DispatchQueue
    nonisolated(unsafe) private var legacyRepository: SwiftDataPersistenceRepository?

    init(
        storeURL: URL,
        calendar: Calendar = SystemBusinessCalendar.current.calendar,
        faultInjector: PersistenceFaultInjector? = nil
    ) {
        self.storeURL = storeURL
        self.calendar = calendar
        self.faultInjector = faultInjector
        persistenceQueue = DispatchQueue(
            label: "com.weekflow.persistence.\(UUID().uuidString)",
            qos: .userInitiated
        )
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
            recordMigrationFailure(error)
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

    // MARK: - Synchronous compatibility (startup & tests only)

    nonisolated fileprivate func executeBlocking<Result>(
        _ operation: PersistenceOperation<Result>
    ) {
        persistenceQueue.sync {
            do {
                let repository: SwiftDataPersistenceRepository
                if let existing = self.legacyRepository {
                    repository = existing
                } else {
                    let created = try SwiftDataPersistenceRepository(
                        storeURL: storeURL,
                        calendar: calendar,
                        faultInjector: faultInjector
                    )
                    self.legacyRepository = created
                    repository = created
                }
                operation.result = try operation.body(repository)
            } catch {
                operation.error = error
                recordMigrationFailure(error)
            }
        }
    }

    nonisolated func reset() { persistenceQueue.sync { legacyRepository = nil } }

    nonisolated private func recordMigrationFailure(_ error: Error) {
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

/// Unchecked only as a transport envelope for the legacy synchronous bridge.
private final class PersistenceOperation<Result>: @unchecked Sendable {
    let body: (SwiftDataPersistenceRepository) throws -> Result
    var result: Result?
    var error: Error?

    init(body: @escaping (SwiftDataPersistenceRepository) throws -> Result) {
        self.body = body
    }
}

private struct PersistenceMigrationFailureReport: Codable {
    let schemaVersion: Int
    let failedAt: Date
    let reason: String
}

/// Compatibility bridge for the existing synchronous command surface (startup,
/// tests). Production mutations should prefer the async `performTransaction`.
enum PersistenceActorBridge {
    /// Synchronous – blocks the calling thread. Use only during init or tests.
    static func run<Result>(
        on actor: PersistenceActor,
        _ body: @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        let operation = PersistenceOperation(body: body)
        actor.executeBlocking(operation)
        if let error = operation.error { throw error }
        guard let result = operation.result else {
            throw PersistenceActorError.missingResult
        }
        return result
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
