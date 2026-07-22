import Foundation

/// Coordinates asynchronous persistence writes to prevent out-of-order commits,
/// stale rollbacks, and cross-domain data loss (P0-1/P0-2/P0-3/P0-4 fix).
///
/// Key guarantees:
/// - Per-domain pending write slots (goals and focus records never overwrite each other)
/// - Commits use the snapshot captured at diff-computation time, not the latest state
/// - Monotonically increasing revision prevents stale async commits after sync writes
/// - Error callback propagates async failures to the Store for UI protection mode
/// - `cancelPending(for:)`, `beginSyncWrite()`, and `endSyncWrite()` are synchronous,
///   safe to call from MainActor without DispatchSemaphore (avoids deadlock in tests)
/// - `syncInProgress` flag prevents in-flight async writes from writing stale data
///   to disk when a sync persist is running
final class PersistenceCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    /// Monotonically increasing revision counter shared across all domains.
    private var latestRevision: UInt64 = 0
    /// The revision that was last successfully committed to disk (any domain).
    private var committedRevision: UInt64 = 0
    /// Per-domain pending write slots. Each domain coalesces independently.
    private var pendingWrites: [String: PendingWrite] = [:]
    /// Per-domain writer tasks.
    private var writerTasks: [String: Task<Void, Never>] = [:]
    /// Whether persistence is currently enabled.
    private var isEnabled = true
    /// Error message if persistence was disabled due to failure.
    private var failureMessage: String?
    /// Callback invoked on MainActor when an async write fails.
    private var onFailure: (@MainActor (String, String) -> Void)?
    /// Set to true while a sync persist is running. Async writers check this
    /// BEFORE writing to disk to avoid putting stale data on disk (P0-3 fix).
    private var _syncInProgress = false

    struct PendingWrite {
        let revision: UInt64
        let label: String
        let operation: @Sendable () async throws -> Void
        let commit: @MainActor () -> Void
        let rollback: @MainActor () -> Void
    }

    // MARK: - Synchronous state access helpers (avoid NSLock-in-async errors)

    private func withState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    // MARK: - Public API

    /// Sets the error callback. Called once during Store initialization.
    func setOnFailure(_ callback: @escaping @MainActor (String, String) -> Void) {
        withState { onFailure = callback }
    }

    /// Enqueues a write operation for the given domain. If a write is already
    /// pending for this domain, it will be replaced (coalesced) with this newer one.
    /// Different domains never interfere with each other (P0-2 fix).
    func enqueue(
        domain: String,
        label: String,
        operation: @Sendable @escaping () async throws -> Void,
        commit: @MainActor @escaping () -> Void,
        rollback: @MainActor @escaping () -> Void
    ) {
        let enabled: Bool = withState {
            guard isEnabled else { return false }
            latestRevision += 1
            let revision = latestRevision
            pendingWrites[domain] = PendingWrite(
                revision: revision,
                label: label,
                operation: operation,
                commit: commit,
                rollback: rollback
            )
            if writerTasks[domain] == nil {
                writerTasks[domain] = Task { [weak self] in
                    await self?.writerLoop(domain: domain)
                }
            }
            return true
        }
        if !enabled {
            Task { @MainActor in rollback() }
        }
    }

    /// Waits for all pending writes across all domains to complete.
    func flush() async {
        let tasks: [Task<Void, Never>] = withState { Array(writerTasks.values) }
        for task in tasks {
            await task.value
        }
    }

    /// Cancels any pending (not yet executing) write for the given domain.
    /// Synchronous – safe to call from MainActor without blocking (P0-3 fix).
    func cancelPending(for domain: String) {
        withState { pendingWrites.removeValue(forKey: domain) }
    }

    /// Marks the beginning of a sync write. Async writers will skip their disk
    /// write if this flag is set, preventing stale data from reaching disk (P0-3 fix).
    func beginSyncWrite() {
        withState { _syncInProgress = true }
    }

    /// Marks the end of a sync write and advances the committed revision.
    /// In-flight async writes with older revisions will not commit stale state (P0-1/P0-3 fix).
    func endSyncWrite() {
        withState {
            _syncInProgress = false
            latestRevision += 1
            committedRevision = latestRevision
        }
    }

    /// Returns whether persistence is currently enabled.
    var persistenceEnabled: Bool {
        withState { isEnabled }
    }

    /// Returns the failure message if persistence was disabled.
    var persistenceFailureMessage: String? {
        withState { failureMessage }
    }

    /// Re-enables persistence after a failure (e.g., user retry).
    func reenable() {
        withState {
            isEnabled = true
            failureMessage = nil
        }
    }

    // MARK: - Private (async writer)

    private func writerLoop(domain: String) async {
        while true {
            let write: PendingWrite? = withState {
                guard let w = pendingWrites[domain] else {
                    writerTasks[domain] = nil
                    return nil
                }
                pendingWrites[domain] = nil
                return w
            }
            guard let write else { break }
            let success = await executeWrite(write)
            if !success { break }
        }
    }

    private func executeWrite(_ write: PendingWrite) async -> Bool {
        // P0-3 fix: if a sync write is in progress, skip the disk write entirely.
        let syncActive: Bool = withState { _syncInProgress }
        guard !syncActive else { return true }

        do {
            try await write.operation()

            // After the disk write, check again: a sync write may have started
            // during our operation. If so, skip the commit (P0-1/P0-3 fix).
            let shouldCommit: Bool = withState {
                guard write.revision > committedRevision && !_syncInProgress else {
                    return false
                }
                committedRevision = write.revision
                return true
            }
            if shouldCommit {
                await MainActor.run { write.commit() }
            }
            return true
        } catch {
            let report: (callback: (@MainActor (String, String) -> Void)?, message: String)? = withState {
                guard write.revision > committedRevision else { return nil }
                isEnabled = false
                let message = "\(write.label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
                failureMessage = message
                return (onFailure, message)
            }
            if let report {
                await MainActor.run {
                    write.rollback()
                    report.callback?(write.label, report.message)
                }
            }
            return false
        }
    }
}
