import Foundation

/// Coordinates asynchronous persistence writes to prevent out-of-order commits,
/// stale rollbacks, and cross-domain data loss.
///
/// Key guarantees:
/// - Per-domain pending write slots (different entities never overwrite each other)
/// - Per-domain committed revision (one domain's success/failure cannot affect another)
/// - Commits use the snapshot captured at diff-computation time, not the latest state
/// - Nesting-aware sync barrier prevents in-flight async writes from writing stale data
/// - Error callback propagates async failures to the Store for UI protection mode
/// - `cancelPending(for:)`, `beginSyncWrite()`, and `endSyncWrite()` are synchronous,
///   safe to call from MainActor without DispatchSemaphore (avoids deadlock in tests)
final class PersistenceCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    /// Per-domain monotonically increasing revision counter.
    private var latestRevisionByDomain: [String: UInt64] = [:]
    /// Per-domain committed revision. A write commits only if its revision is
    /// greater than its own domain's committed revision (P0 fix: no cross-domain
    /// interference).
    private var committedRevisionByDomain: [String: UInt64] = [:]
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
    /// Nesting-aware sync barrier counter. Async writers skip disk writes when
    /// this is > 0. Using a counter instead of Bool prevents inner endSyncWrite
    /// from prematurely releasing the outer barrier (P0 termination fix).
    private var _syncBarrierDepth = 0

    struct PendingWrite {
        let domain: String
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
    /// Different domains never interfere with each other.
    func enqueue(
        domain: String,
        label: String,
        operation: @Sendable @escaping () async throws -> Void,
        commit: @MainActor @escaping () -> Void,
        rollback: @MainActor @escaping () -> Void
    ) {
        let enabled: Bool = withState {
            guard isEnabled else { return false }
            let nextRevision = (latestRevisionByDomain[domain] ?? 0) + 1
            latestRevisionByDomain[domain] = nextRevision
            pendingWrites[domain] = PendingWrite(
                domain: domain,
                revision: nextRevision,
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
    /// Synchronous – safe to call from MainActor without blocking.
    func cancelPending(for domain: String) {
        withState { _ = pendingWrites.removeValue(forKey: domain) }
    }

    /// Cancels ALL pending writes across every domain.
    func cancelAllPending() {
        withState { pendingWrites.removeAll() }
    }

    /// Marks the beginning of a sync write. Async writers will skip their disk
    /// write while the barrier depth is > 0. Supports nesting: multiple callers
    /// can begin/end without prematurely releasing the barrier.
    func beginSyncWrite() {
        withState { _syncBarrierDepth += 1 }
    }

    /// Marks the end of a sync write. Decrements the barrier depth. When depth
    /// reaches 0, advances ALL domain committed revisions to their latest so
    /// in-flight async writes with older revisions will not commit stale state.
    func endSyncWrite() {
        withState {
            guard _syncBarrierDepth > 0 else { return }
            _syncBarrierDepth -= 1
            if _syncBarrierDepth == 0 {
                // Advance all domains' committed revision to their latest.
                for (domain, latest) in latestRevisionByDomain {
                    committedRevisionByDomain[domain] = latest
                }
            }
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
        // If a sync barrier is active, skip the disk write entirely.
        let syncActive: Bool = withState { _syncBarrierDepth > 0 }
        guard !syncActive else { return true }

        do {
            try await write.operation()

            // After the disk write, check again: a sync barrier may have been
            // raised during our operation. If so, skip the commit.
            let shouldCommit: Bool = withState {
                let domainCommitted = committedRevisionByDomain[write.domain] ?? 0
                guard write.revision > domainCommitted && _syncBarrierDepth == 0 else {
                    return false
                }
                committedRevisionByDomain[write.domain] = write.revision
                return true
            }
            if shouldCommit {
                await MainActor.run { write.commit() }
            }
            return true
        } catch {
            // Per-domain error handling: only suppress if this domain already
            // committed a newer revision (meaning our write is stale).
            let report: (callback: (@MainActor (String, String) -> Void)?, message: String)? = withState {
                let domainCommitted = committedRevisionByDomain[write.domain] ?? 0
                guard write.revision > domainCommitted else { return nil }
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
