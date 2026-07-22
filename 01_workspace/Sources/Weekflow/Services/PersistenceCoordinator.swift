import Foundation

/// Coordinates asynchronous persistence writes to prevent out-of-order commits
/// and stale rollbacks (P0-2 fix).
///
/// Key guarantees:
/// - Only one write operation is in-flight at a time
/// - Subsequent edits are coalesced into the latest snapshot
/// - Commits only apply if the revision is still current
/// - Rollbacks never overwrite newer state
/// - `flush()` ensures all pending writes complete before app termination
actor PersistenceCoordinator {
    /// Monotonically increasing revision counter.
    private var latestRevision: UInt64 = 0
    /// The revision that was last successfully committed to disk.
    private var committedRevision: UInt64 = 0
    /// Pending snapshot waiting to be written (coalesced).
    private var pendingWrite: PendingWrite?
    /// The currently executing write task, if any.
    private var writerTask: Task<Void, Never>?
    /// Whether persistence is currently enabled.
    private var isEnabled = true
    /// Error message if persistence was disabled due to failure.
    private var failureMessage: String?

    struct PendingWrite {
        let revision: UInt64
        let label: String
        let operation: @Sendable () async throws -> Void
        let commit: @MainActor () -> Void
        let rollback: @MainActor () -> Void
    }

    /// Enqueues a write operation. If a write is already pending, it will be
    /// replaced (coalesced) with this newer one.
    func enqueue(
        label: String,
        operation: @Sendable @escaping () async throws -> Void,
        commit: @MainActor @escaping () -> Void,
        rollback: @MainActor @escaping () -> Void
    ) {
        guard isEnabled else {
            // Persistence disabled – execute rollback immediately
            Task { @MainActor in rollback() }
            return
        }

        latestRevision += 1
        let revision = latestRevision

        pendingWrite = PendingWrite(
            revision: revision,
            label: label,
            operation: operation,
            commit: commit,
            rollback: rollback
        )

        // Start writer if not already running
        if writerTask == nil {
            startWriter()
        }
    }

    /// Waits for all pending writes to complete. Call before app termination.
    func flush() async {
        if let task = writerTask {
            await task.value
        }
    }

    /// Returns whether persistence is currently enabled.
    var persistenceEnabled: Bool { isEnabled }

    /// Returns the failure message if persistence was disabled.
    var persistenceFailureMessage: String? { failureMessage }

    /// Re-enables persistence after a failure (e.g., user retry).
    func reenable() {
        isEnabled = true
        failureMessage = nil
    }

    // MARK: - Private

    private func startWriter() {
        writerTask = Task {
            while let write = pendingWrite {
                pendingWrite = nil
                let success = await executeWrite(write)
                if !success {
                    // Stop processing on failure
                    break
                }
            }
            writerTask = nil
        }
    }

    private func executeWrite(_ write: PendingWrite) async -> Bool {
        do {
            try await write.operation()

            // Only commit if this revision is still the latest
            // (prevents stale commits from coalesced writes)
            if write.revision >= committedRevision {
                committedRevision = write.revision
                await MainActor.run { write.commit() }
            }
            return true
        } catch {
            // Only rollback if no newer revision has been committed
            // (prevents stale rollbacks from overwriting newer state)
            if write.revision > committedRevision {
                isEnabled = false
                failureMessage = "\(write.label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
                await MainActor.run { write.rollback() }
            }
            return false
        }
    }
}
