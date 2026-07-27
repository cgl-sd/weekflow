import Foundation

/// Serializes all SwiftData writes through one globally ordered queue.
///
/// The repository owns one ModelContext behind one PersistenceActor, so running
/// independent per-domain writers cannot increase database throughput. A single
/// queue also prevents an older single-entity snapshot from landing after a newer
/// cross-entity transaction. Pending writes still coalesce by domain, but a
/// replacement is appended at the queue tail so chronology across domains is kept.
final class PersistenceCoordinator: @unchecked Sendable {
    private enum ActivePhase: Equatable {
        case operating
        case committing
    }

    private struct ActiveWrite {
        let domain: String
        let revision: UInt64
        var phase: ActivePhase
    }

    private let lock = NSLock()
    private var nextRevision: UInt64 = 0
    private var committedRevisionByDomain: [String: UInt64] = [:]
    private var invalidatedRevisionByDomain: [String: UInt64] = [:]
    private var globallyInvalidatedRevision: UInt64 = 0
    private var invalidatedPrefixCutoffs: [String: UInt64] = [:]
    // Indexed FIFO with tombstones. This preserves global order and same-domain
    // tail coalescing without the O(N) scan/shift cost of Array removeAll/removeFirst.
    private var pendingWritesByRevision: [UInt64: PendingWrite] = [:]
    private var pendingRevisionByDomain: [String: UInt64] = [:]
    private var pendingOrder: [UInt64] = []
    private var pendingOrderHead = 0
    private var activeWrite: ActiveWrite?
    private var writerTask: Task<Void, Never>?
    private var writerGeneration: UInt64 = 0
    private var isEnabled = true
    private var failureMessage: String?
    private var onFailure: (@MainActor (String, String) -> Void)?
    private var syncBarrierDepth = 0

    struct PendingWrite {
        let domain: String
        let revision: UInt64
        let label: String
        let operation: @Sendable () async throws -> Void
        let commit: @MainActor () -> Void
        let rollback: @MainActor () -> Void
    }

    private func withState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func setOnFailure(_ callback: @escaping @MainActor (String, String) -> Void) {
        withState { onFailure = callback }
    }

    func enqueue(
        domain: String,
        label: String,
        operation: @Sendable @escaping () async throws -> Void,
        commit: @MainActor @escaping () -> Void,
        rollback: @MainActor @escaping () -> Void
    ) {
        withState {
            guard isEnabled else {
                // Persistence is paused/disabled: drop the write but preserve the
                // caller's in-memory edit. Only an accepted write that later fails
                // rolls back (see executeWrite). Rolling back here would revert the
                // user's latest work even though no disk write was attempted.
                return
            }
            nextRevision &+= 1
            let write = PendingWrite(
                domain: domain,
                revision: nextRevision,
                label: label,
                operation: operation,
                commit: commit,
                rollback: rollback
            )
            enqueuePendingLocked(write)
            startWriterIfNeededLocked()
        }
    }

    /// Returns only after the active writer and all writes visible to the
    /// coordinator have drained. It loops because commit callbacks may enqueue a
    /// follow-up write before the current writer task clears itself.
    ///
    /// Do not call while a sync barrier is holding pending writes unless the
    /// pending queue has first been cancelled. Termination follows that ordering.
    func flush() async {
        while true {
            if let task = withState({ writerTask }) {
                await task.value
                continue
            }
            let drained = withState { pendingWritesByRevision.isEmpty && writerTask == nil }
            if drained { return }
            await Task.yield()
        }
    }

    /// Waits only for the writer that has already been claimed. Unlike
    /// `flush()`, this remains safe while a sync barrier is raised: writes that
    /// arrive during the wait stay pending behind the barrier and therefore do
    /// not make this method spin forever. Termination cancels those pending
    /// writes again before capturing its authoritative full snapshot.
    func drainActiveWriter() async {
        if let task = withState({ writerTask }) {
            await task.value
        }
    }

    func cancelPending(for domain: String) {
        withState { cancelPendingLocked(for: domain) }
    }

    func cancelAllPending() {
        withState { removeAllPendingLocked() }
    }

    /// Cancels pending (not-yet-started) writes whose domain begins with `prefix`.
    /// Used by a full-snapshot sync write to supersede every per-task edit
    /// (`task:<uuid>`) without touching unrelated domains (focus/calendar/…).
    func cancelPending(matchingPrefix prefix: String) {
        withState {
            let matchingDomains = pendingRevisionByDomain.keys.filter { $0.hasPrefix(prefix) }
            for domain in matchingDomains {
                cancelPendingLocked(for: domain)
            }
        }
    }

    /// Pauses the queue and permanently invalidates writes that were already
    /// issued for the supplied domains. Passing nil invalidates every write issued
    /// so far. Newer writes enqueued while the barrier is active remain valid and
    /// resume after `endSyncWrite()`.
    func beginSyncWrite(invalidating domains: Set<String>? = nil, invalidatingPrefixes: [String] = []) {
        withState {
            syncBarrierDepth += 1
            let cutoff = nextRevision
            if let domains {
                for domain in domains {
                    invalidatedRevisionByDomain[domain] = max(
                        invalidatedRevisionByDomain[domain] ?? 0,
                        cutoff
                    )
                }
            } else {
                globallyInvalidatedRevision = max(globallyInvalidatedRevision, cutoff)
            }
            // Prefix invalidation: a full-snapshot sync write supersedes every
            // in-flight per-task edit (`task:<uuid>`) issued before the barrier.
            for prefix in invalidatingPrefixes {
                invalidatedPrefixCutoffs[prefix] = max(invalidatedPrefixCutoffs[prefix] ?? 0, cutoff)
            }
        }
    }

    /// Waits synchronously only when a currently operating write was invalidated
    /// by the active barrier. This is safe on MainActor because an invalidated
    /// operation never invokes its MainActor commit/rollback callback. A write
    /// that has already reached the committing phase has completed its disk I/O;
    /// its stale callback is suppressed by the persistent revision cutoff.
    @available(*, noasync, message: "Use flush() from asynchronous code")
    func drainInvalidatedWriteBlocking(timeout: TimeInterval = 60) -> Bool {
        let task: Task<Void, Never>? = withState {
            guard syncBarrierDepth > 0,
                let activeWrite,
                activeWrite.phase == .operating,
                isInvalidatedLocked(domain: activeWrite.domain, revision: activeWrite.revision)
            else { return nil }
            return writerTask
        }
        guard let task else { return true }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await task.value
            semaphore.signal()
        }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }

    func endSyncWrite() {
        withState {
            guard syncBarrierDepth > 0 else { return }
            syncBarrierDepth -= 1
            if syncBarrierDepth == 0 {
                startWriterIfNeededLocked()
            }
        }
    }

    var persistenceEnabled: Bool { withState { isEnabled } }
    var persistenceFailureMessage: String? { withState { failureMessage } }

    func disable(reason: String?) {
        withState {
            isEnabled = false
            failureMessage = reason
            removeAllPendingLocked()
        }
    }

    /// Re-enables future writes after the caller has repaired/reopened storage.
    /// Any write queued before the failure remains discarded.
    func reenable() {
        withState {
            isEnabled = true
            failureMessage = nil
            startWriterIfNeededLocked()
        }
    }

    private func startWriterIfNeededLocked() {
        guard writerTask == nil,
            isEnabled,
            syncBarrierDepth == 0,
            !pendingWritesByRevision.isEmpty
        else { return }
        writerGeneration &+= 1
        let generation = writerGeneration
        writerTask = Task { [weak self] in
            await self?.writerLoop(generation: generation)
        }
    }

    private func writerLoop(generation: UInt64) async {
        defer {
            withState {
                guard writerGeneration == generation else { return }
                activeWrite = nil
                writerTask = nil
                startWriterIfNeededLocked()
            }
        }

        while true {
            let write = withState { () -> PendingWrite? in
                guard isEnabled,
                    syncBarrierDepth == 0,
                    !pendingWritesByRevision.isEmpty
                else { return nil }
                guard let write = dequeuePendingLocked() else { return nil }
                activeWrite = ActiveWrite(
                    domain: write.domain,
                    revision: write.revision,
                    phase: .operating
                )
                return write
            }
            guard let write else { return }
            let success = await executeWrite(write)
            withState {
                if activeWrite?.revision == write.revision {
                    activeWrite = nil
                }
            }
            if !success { return }
        }
    }

    private func executeWrite(_ write: PendingWrite) async -> Bool {
        let mayStart = withState {
            isEnabled && !isStaleLocked(write)
        }
        guard mayStart else { return true }

        do {
            try await write.operation()
            let mayCommit = withState { () -> Bool in
                guard isEnabled, !isStaleLocked(write) else { return false }
                if activeWrite?.revision == write.revision {
                    activeWrite?.phase = .committing
                }
                return true
            }
            guard mayCommit else { return true }

            await MainActor.run {
                let shouldCommit = self.withState { () -> Bool in
                    guard self.isEnabled, !self.isStaleLocked(write) else { return false }
                    self.committedRevisionByDomain[write.domain] = write.revision
                    return true
                }
                if shouldCommit { write.commit() }
            }
            return true
        } catch {
            let report = withState { () -> (callback: (@MainActor (String, String) -> Void)?, message: String)? in
                guard !isStaleLocked(write) else { return nil }
                isEnabled = false
                removeAllPendingLocked()
                let message = "\(write.label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
                failureMessage = message
                return (onFailure, message)
            }
            if let report {
                await MainActor.run {
                    write.rollback()
                    report.callback?(write.label, report.message)
                }
                return false
            }
            return true
        }
    }

    private func enqueuePendingLocked(_ write: PendingWrite) {
        if let previousRevision = pendingRevisionByDomain[write.domain] {
            pendingWritesByRevision.removeValue(forKey: previousRevision)
        }
        pendingRevisionByDomain[write.domain] = write.revision
        pendingWritesByRevision[write.revision] = write
        pendingOrder.append(write.revision)
        compactPendingOrderIfNeededLocked()
    }

    private func dequeuePendingLocked() -> PendingWrite? {
        while pendingOrderHead < pendingOrder.count {
            let revision = pendingOrder[pendingOrderHead]
            pendingOrderHead += 1
            guard let write = pendingWritesByRevision.removeValue(forKey: revision) else {
                compactPendingOrderIfNeededLocked()
                continue
            }
            if pendingRevisionByDomain[write.domain] == revision {
                pendingRevisionByDomain.removeValue(forKey: write.domain)
            }
            compactPendingOrderIfNeededLocked()
            return write
        }
        compactPendingOrderIfNeededLocked(force: true)
        return nil
    }

    private func cancelPendingLocked(for domain: String) {
        guard let revision = pendingRevisionByDomain.removeValue(forKey: domain) else { return }
        pendingWritesByRevision.removeValue(forKey: revision)
        compactPendingOrderIfNeededLocked()
    }

    private func removeAllPendingLocked() {
        pendingWritesByRevision.removeAll()
        pendingRevisionByDomain.removeAll()
        pendingOrder.removeAll()
        pendingOrderHead = 0
    }

    /// Rebuilds the revision order only after enough consumed/tombstoned slots
    /// accumulate. The occasional O(N) compaction is amortized across at least
    /// 1,024 O(1) queue operations.
    private func compactPendingOrderIfNeededLocked(force: Bool = false) {
        let queuedSlotCount = pendingOrder.count - pendingOrderHead
        let liveCount = pendingWritesByRevision.count
        let consumedPrefixIsLarge = pendingOrderHead >= 1_024
            && pendingOrderHead * 2 >= pendingOrder.count
        let tombstoneCountIsLarge = queuedSlotCount >= 1_024
            && queuedSlotCount > max(liveCount * 2, 1_024)
        let shouldCompact = force || consumedPrefixIsLarge || tombstoneCountIsLarge
        guard shouldCompact else { return }
        let liveRevisions = Set(pendingWritesByRevision.keys)
        pendingOrder = pendingOrder[pendingOrderHead...].filter(liveRevisions.contains)
        pendingOrderHead = 0
    }

    private func isStaleLocked(_ write: PendingWrite) -> Bool {
        let committed = committedRevisionByDomain[write.domain] ?? 0
        return write.revision <= committed
            || isInvalidatedLocked(domain: write.domain, revision: write.revision)
    }

    private func isInvalidatedLocked(domain: String, revision: UInt64) -> Bool {
        if revision <= globallyInvalidatedRevision
            || revision <= (invalidatedRevisionByDomain[domain] ?? 0) {
            return true
        }
        for (prefix, cutoff) in invalidatedPrefixCutoffs where domain.hasPrefix(prefix) {
            if revision <= cutoff { return true }
        }
        return false
    }
}
