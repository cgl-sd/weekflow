import Foundation
import Observation

// All persistence orchestration: sync, async, debounced, and entity-specific writes.

/// Per-write carrier for the goals snapshot captured at diff-computation time.
/// Phase 2-3 fix: replaces the shared `WeekflowStore._pendingGoalSnapshot` slot.
/// Each enqueued goal write owns its own box, so two in-flight writes can never
/// overwrite each other's baseline. All access is serialized on MainActor — the
/// operation writes it inside `MainActor.run`, the commit reads it on MainActor —
/// hence `@unchecked Sendable`.
final class GoalSnapshotBox: @unchecked Sendable {
    var snapshot: [WeeklyGoal]?
}

extension WeekflowStore {
    /// Stops every writer and releases SwiftData so a validated SQLite backup can
    /// replace the live store without racing an open ModelContext.
    private func prepareForStorageRecovery() async {
        textInputDebouncer.cancelPending()
        persistenceCoordinator.cancelAllPending()
        persistenceCoordinator.beginSyncWrite()
        await persistenceCoordinator.drainActiveWriter()
        persistenceCoordinator.cancelAllPending()
        persistenceCoordinator.disable(reason: "正在恢复本地数据库")
        await storage.closeRepositoryForRecovery()
        persistenceCoordinator.endSyncWrite()
    }

    func availableRecoveryBackups() async -> [URL] {
        await storage.availableBackupsForRecovery()
    }

    func retryStorageConnection() async {
        await prepareForStorageRecovery()
    }

    func restoreBackupForRecovery(from backup: URL) async throws {
        await prepareForStorageRecovery()
        try await storage.restoreBackupForRecovery(from: backup)
    }

    func databaseBackupStatus() -> DatabaseBackupStatus {
        storage.backupStatus()
    }

    /// Creates a verified backup only after all writers have stopped and the live
    /// SwiftData context has been released. Normal persistence resumes regardless
    /// of whether this best-effort backup succeeds.
    func createVerifiedBackup() async throws {
        let wasEnabled = persistenceEnabled
        let previousIssue = persistenceIssue
        await prepareForStorageRecovery()
        defer {
            if wasEnabled {
                persistenceEnabled = true
                persistenceIssue = previousIssue
                persistenceCoordinator.reenable()
            }
        }
        try await storage.makeBackupAsync()
    }

    func exportFullDataArchive(to url: URL) throws {
        try FullDataArchiveService().write(snapshot: makeApplicationSnapshot(), to: url)
    }

    func exportDiagnosticSupportBundle(to url: URL) throws {
        try DiagnosticSupportService().write(storage: storage, to: url)
    }

    /// Imports one validated, complete application snapshot. The existing store is
    /// backed up first, and the replacement is committed as one SwiftData
    /// transaction before any in-memory collection changes.
    func importFullDataArchive(from url: URL) async throws {
        let archiveService = FullDataArchiveService()
        let snapshot = try await Task.detached(priority: .userInitiated) {
            try archiveService.read(from: url)
        }.value

        await prepareForStorageRecovery()
        do {
            try await storage.makeBackupAsync()
            try await storage.saveApplicationSnapshotAsync(snapshot)
        } catch {
            persistenceIssue = "完整数据导入失败，本次会话已暂停保存。\n\n\(error.localizedDescription)"
            persistenceEnabled = false
            persistenceCoordinator.disable(reason: persistenceIssue)
            throw error
        }

        goals = snapshot.goals
        plans = snapshot.plans
        channels = snapshot.channels
        calendarEvents = snapshot.calendarEvents
        dailyPlanningStates = snapshot.dailyPlanningStates
        focusRecords = snapshot.focusRecords
        dailySummaries = snapshot.dailySummaries
        activeTaskTimer = nil
        pendingTimerRecovery = snapshot.activeTimerSession.map {
            InterruptedTaskTimerRecovery(
                session: $0,
                elapsedSeconds: max(Int(Date.now.timeIntervalSince($0.startedAt)), 0)
            )
        }
        automaticDistributionChanges = []
        selectedGoalID = goals.first?.id
        persistedGoals = goals
        persistedPlans = plans
        persistedChannels = channels
        persistedCalendarEvents = calendarEvents
        persistedDailyPlanningStates = dailyPlanningStates
        persistedFocusRecords = focusRecords
        persistedDailySummaries = dailySummaries
        invalidateGoalIndex()
        persistenceIssue = nil
        persistenceEnabled = true
        persistenceCoordinator.reenable()
    }

    func persist(kind: PersistenceMutationKind = .userEdit) {
        if synchronousPersistence {
            _ = persistSync(kind: kind)
            return
        }
        // O(1) scheduling: the coordinator coalesces per-domain, and the
        // background diff (in enqueueGoalPersist) handles the empty-change case.
        // This avoids an O(N) deep array comparison on MainActor.
        enqueueGoalPersist(kind: kind)
    }

    /// Enqueues a goal persistence write on the coordinator (P0-1/P0-2 fix).
    ///
    /// P1-5 fix: The diff is computed OFF the MainActor. Only the snapshot
    /// capture (a value-type copy) happens on MainActor; the expensive
    /// dictionary-based diff runs on the coordinator's background executor.
    /// P0-1 fix: The commit closure captures the goals snapshot at diff-computation
    /// time, ensuring `persistedGoals` reflects exactly what was written to disk,
    /// not the potentially-newer state from edits made during the write.
    func enqueueGoalPersist(kind: PersistenceMutationKind = .userEdit) {
        // Phase 2-3 fix: per-write snapshot box instead of a shared Store slot.
        let box = GoalSnapshotBox()
        // Capture the snapshots now, on the MainActor (this method runs there).
        // Hopping back to the MainActor from inside the async operation would
        // deadlock when a synchronous write (persistSync) blocks the MainActor in
        // drainInvalidatedWriteBlocking while waiting for this very writer task.
        let currentGoals = goals
        let baselineGoals = persistedGoals
        persistenceCoordinator.enqueue(
            domain: "goals",
            label: "周目标与任务",
            operation: { [weak self] in
                guard let self else { return }
                // Validate the complete snapshot before the dictionary-based
                // diff can collapse duplicate task identities.
                try PersistenceIdentityValidator.validate(goals: currentGoals)
                // Expensive diff computed OFF MainActor.
                let changes = PersistenceGoalChangeSet.difference(
                    before: baselineGoals,
                    after: currentGoals
                )
                guard !changes.isEmpty else { return }
                try await self.storage.applyGoalChangesAsync(changes, kind: kind)
                // Store the snapshot on this write's own box for commit (P0-1 + Phase 2-3).
                box.snapshot = currentGoals
            },
            commit: { [weak self] in
                guard let self else { return }
                // P0-1 fix: use the snapshot captured at diff time, not self.goals.
                if let snapshot = box.snapshot {
                    self.persistedGoals = snapshot
                } else {
                    self.persistedGoals = self.goals
                }
            },
            rollback: { [weak self] in
                guard let self else { return }
                self.goals = self.persistedGoals
            }
        )
    }

    /// R13: persist a single interactive task edit in O(1) with respect to the
    /// total task count. Instead of diffing every goal/task collection (the O(N)
    /// `PersistenceGoalChangeSet.difference`), this builds a change-set that names
    /// only the edited task plus its goal envelope and applies it through the same
    /// transactional `applyGoalChanges` path, whose batch fetches are keyed to the
    /// single ids. Full-collection diffing remains reserved for startup recovery,
    /// explicit import, and the exit fallback snapshot.
    func persistSingleTaskEdit(
        goalID: UUID,
        task: WeekTask,
        envelope: WeeklyGoal,
        kind: PersistenceMutationKind = .userEdit
    ) {
        var changes = PersistenceGoalChangeSet()
        changes.goalsToUpsert = [envelope]
        changes.tasksToUpsert = [PersistedTaskUpsert(goalID: goalID, task: task)]
        let changeSet = changes
        if synchronousPersistence {
            _ = persistSafely(
                "单任务编辑",
                operation: { try storage.applyGoalChanges(changeSet, kind: kind) },
                commit: { syncPersistedBaseline(forGoal: envelope) },
                rollback: {
                    goals = persistedGoals
                    invalidateGoalIndex()
                }
            )
            return
        }
        // Per-task domain: edits to the same task coalesce to the latest, while
        // edits to different tasks never supplant one another.
        persistenceCoordinator.enqueue(
            domain: "task:\(task.id.uuidString)",
            label: "单任务编辑",
            operation: { [storage] in
                try PersistenceIdentityValidator.validate(goals: [envelope])
                try await storage.applyGoalChangesAsync(changeSet, kind: kind)
            },
            commit: { [weak self] in
                self?.syncPersistedBaseline(forGoal: envelope)
            },
            rollback: { [weak self] in
                guard let self else { return }
                self.goals = self.persistedGoals
                self.invalidateGoalIndex()
            }
        )
    }

    /// Update the persisted baseline for just the edited goal. Locating the goal is
    /// O(number of goals) and copying it is O(tasks within that goal) — both
    /// independent of the total task count across all goals, so this never
    /// reintroduces the O(N) interactive hot path.
    private func syncPersistedBaseline(forGoal goal: WeeklyGoal) {
        if let index = persistedGoals.firstIndex(where: { $0.id == goal.id }) {
            persistedGoals[index] = goal
        } else {
            persistedGoals.append(goal)
        }
    }

    /// Synchronous persist – blocks the calling thread. Use ONLY when the
    /// return value is needed (automatic distribution rollback) or during
    /// startup/tests where blocking is acceptable.
    /// P0-3 fix: uses synchronous coordinator API (NSLock-based) to cancel
    /// pending async writes and advance the revision, preventing stale commits.
    @discardableResult
    func persistSync(kind: PersistenceMutationKind = .userEdit) -> Bool {
        // Cancel any pending async write for goals and signal that a sync write
        // is starting. In-flight async writers will skip their disk write.
        persistenceCoordinator.cancelPending(for: "goals")
        persistenceCoordinator.cancelPending(for: "goalsTimer")
        // P0-1: a full-snapshot sync write supersedes every per-task edit. Cancel
        // pending `task:<uuid>` writes AND invalidate any in-flight one, so a stale
        // single-task write cannot land after this authoritative snapshot.
        persistenceCoordinator.cancelPending(matchingPrefix: "task:")
        persistenceCoordinator.beginSyncWrite(invalidating: ["goals", "goalsTimer"], invalidatingPrefixes: ["task:"])
        guard persistenceCoordinator.drainInvalidatedWriteBlocking() else {
            persistenceCoordinator.endSyncWrite()
            goals = persistedGoals
            invalidateGoalIndex()
            persistenceEnabled = false
            persistenceIssue = "等待旧持久化写入结束超时，本次会话已暂停保存。"
            persistenceCoordinator.disable(reason: persistenceIssue)
            return false
        }

        let changes: PersistenceGoalChangeSet
        do {
            try PersistenceIdentityValidator.validate(goals: goals)
            changes = PersistenceGoalChangeSet.difference(
                before: persistedGoals,
                after: goals
            )
        } catch {
            persistenceCoordinator.endSyncWrite()
            goals = persistedGoals
            invalidateGoalIndex()
            persistenceEnabled = false
            persistenceIssue = "周目标与任务校验失败，本次会话已暂停保存。\n\n\(error.localizedDescription)"
            persistenceCoordinator.disable(reason: persistenceIssue)
            return false
        }
        guard !changes.isEmpty else {
            persistenceCoordinator.endSyncWrite()
            return true
        }
        let success = persistSafely(
            "周目标与任务",
            operation: { try storage.applyGoalChanges(changes, kind: kind) },
            commit: { persistedGoals = goals },
            rollback: { goals = persistedGoals }
        )
        // P0-3 fix: advance coordinator revision so in-flight async writes
        // with older revisions will not commit stale state.
        persistenceCoordinator.endSyncWrite()
        return success
    }

    /// Single-transaction startup persist. All startup migrations and
    /// synchronization are committed atomically so a crash during startup
    /// cannot leave partially committed state (P1-3 requirement).
    func persistStartup() {
        let snapshot = makeApplicationSnapshot()
        if synchronousPersistence {
            _ = persistSafely(
                "启动同步",
                operation: { try storage.saveApplicationSnapshot(snapshot) },
            commit: {
                persistedGoals = goals
                persistedPlans = plans
                persistedChannels = channels
                persistedCalendarEvents = calendarEvents
                persistedDailyPlanningStates = dailyPlanningStates
                persistedFocusRecords = focusRecords
                persistedDailySummaries = dailySummaries
            },
                rollback: {
                    goals = persistedGoals
                    invalidateGoalIndex()
                    plans = persistedPlans
                    channels = persistedChannels
                    calendarEvents = persistedCalendarEvents
                    dailyPlanningStates = persistedDailyPlanningStates
                    focusRecords = persistedFocusRecords
                    dailySummaries = persistedDailySummaries
                }
            )
            return
        }
        persistenceCoordinator.enqueue(
            domain: "applicationSnapshot",
            label: "启动同步",
            operation: { [weak self] in
                try await self?.storage.saveApplicationSnapshotAsync(snapshot)
            },
            commit: { [weak self] in
                guard let self else { return }
                self.persistedGoals = snapshot.goals
                self.persistedPlans = snapshot.plans
                self.persistedChannels = snapshot.channels
                self.persistedCalendarEvents = snapshot.calendarEvents
                self.persistedDailyPlanningStates = snapshot.dailyPlanningStates
                self.persistedFocusRecords = snapshot.focusRecords
                self.persistedDailySummaries = snapshot.dailySummaries
            },
            rollback: { [weak self] in
                guard let self else { return }
                self.goals = self.persistedGoals
                self.invalidateGoalIndex()
                self.plans = self.persistedPlans
                self.channels = self.persistedChannels
                self.calendarEvents = self.persistedCalendarEvents
                self.dailyPlanningStates = self.persistedDailyPlanningStates
                self.focusRecords = self.persistedFocusRecords
                self.dailySummaries = self.persistedDailySummaries
            }
        )
    }

    func persistChannels() {
        if synchronousPersistence {
            persistSafely(
                "频道",
                operation: { try storage.saveChannels(channels) },
                commit: { persistedChannels = channels },
                rollback: { channels = persistedChannels }
            )
            return
        }
        // P1-4 fix: non-blocking write via coordinator.
        // Self-check fix: dedicated domain prevents coalescing data loss.
        let snapshot = channels
        let rollbackSnapshot = persistedChannels
        persistenceCoordinator.enqueue(
            domain: "channels",
            label: "频道",
            operation: { [weak self] in
                try await self?.storage.saveChannelsAsync(snapshot)
            },
            commit: { [weak self] in self?.persistedChannels = snapshot },
            rollback: { [weak self] in self?.channels = rollbackSnapshot }
        )
    }

    // MARK: - Full-array persistence (reserved for startup/termination/import)
    //
    // Interactive paths use targeted single-entity methods in
    // StoreTargetedPersistence.swift (persistCalendarEventRecord, etc.).
    // Full-array writes are only appropriate for:
    //   - First-time import
    //   - Schema migration
    //   - User-initiated full restore
    //   - Exit snapshot (saveApplicationSnapshot)

    func persistActiveTaskTimer() {
        if synchronousPersistence {
            let session = activeTaskTimer
            _ = persistSafely(
                "活动计时",
                operation: { try storage.saveActiveTimerSession(session) },
                commit: {},
                rollback: {
                    if session != nil { activeTaskTimer = nil }
                }
            )
            return
        }
        // P1-4 fix: non-blocking write via coordinator.
        let session = activeTaskTimer
        persistenceCoordinator.enqueue(
            domain: "timer",
            label: "活动计时",
            operation: { [weak self] in
                try await self?.storage.saveActiveTimerSessionAsync(session)
            },
            commit: {},
            rollback: { [weak self] in
                if session != nil { self?.activeTaskTimer = nil }
            }
        )
    }

    /// P1-3: persist the timer change incrementally. The timer only ever changes the
    /// timed task(s), which live in `affectedGoalIDs`, so the diff is scoped to those
    /// goals — O(tasks in those goals) instead of O(all tasks). Reuses the existing
    /// diff logic (correctness) and keeps the task + active-timer session atomic.
    func persistTaskAndActiveTimer(rollbackSession: TaskTimerSession?, affectedGoalIDs: Set<UUID>) {
        if synchronousPersistence {
            let changes = PersistenceGoalChangeSet.difference(
                before: persistedGoals.filter { affectedGoalIDs.contains($0.id) },
                after: goals.filter { affectedGoalIDs.contains($0.id) }
            )
            let session = activeTaskTimer
            _ = persistSafely(
                "任务与活动计时",
                operation: {
                    try storage.saveGoalChangesAndActiveTimer(
                        changes: changes,
                        session: session
                    )
                },
                commit: {
                    applyPersistedBaseline(
                        writtenGoals: goals.filter { affectedGoalIDs.contains($0.id) }
                    )
                },
                rollback: {
                    goals = persistedGoals
                    invalidateGoalIndex()
                    taskTimerService.restore(session: rollbackSession)
                }
            )
            return
        }
        // Non-blocking write via coordinator. The combined transaction supersedes
        // pending goal-only / timer-only / per-task writes for the affected goals.
        persistenceCoordinator.cancelPending(for: "goals")
        persistenceCoordinator.cancelPending(for: "timer")
        persistenceCoordinator.cancelPending(matchingPrefix: "task:")
        // Capture the snapshots now, on the MainActor (this method runs there).
        // Hopping back to the MainActor from inside the async operation would
        // deadlock when a synchronous write blocks the MainActor in
        // drainInvalidatedWriteBlocking while waiting for this writer task.
        let currentGoals = goals.filter { affectedGoalIDs.contains($0.id) }
        let baselineGoals = persistedGoals.filter { affectedGoalIDs.contains($0.id) }
        let session = activeTaskTimer
        persistenceCoordinator.enqueue(
            domain: "goalsTimer",
            label: "任务与活动计时",
            operation: { [weak self] in
                guard let self else { return }
                let changes = PersistenceGoalChangeSet.difference(
                    before: baselineGoals,
                    after: currentGoals
                )
                try await self.storage.saveGoalChangesAndActiveTimerAsync(
                    changes: changes,
                    session: session
                )
            },
            commit: { [weak self] in
                // Advance the baseline to exactly the snapshot that completed
                // its database transaction. Reading `self.goals` here would be
                // unsafe: the user may have made a newer, still-debounced edit
                // while this write was in flight. Marking that newer value as
                // persisted would make its later diff empty and lose it after
                // restart.
                self?.applyPersistedBaseline(writtenGoals: currentGoals)
            },
            rollback: { [weak self] in
                self?.goals = self?.persistedGoals ?? []
                self?.invalidateGoalIndex()
                self?.taskTimerService.restore(session: rollbackSession)
            }
        )
    }

    /// Update the persisted baseline for just the given goals (their current in-memory
    /// state), leaving every other goal's baseline untouched.
    private func applyPersistedBaseline(writtenGoals: [WeeklyGoal]) {
        for writtenGoal in writtenGoals {
            if let index = persistedGoals.firstIndex(where: { $0.id == writtenGoal.id }) {
                persistedGoals[index] = writtenGoal
            } else {
                persistedGoals.append(writtenGoal)
            }
        }
    }

    @discardableResult
    func persistSafely(
        _ label: String,
        operation: () throws -> Void,
        commit: () -> Void,
        rollback: () -> Void
    ) -> Bool {
        // Regression fixtures intentionally run without disk writes, but their
        // in-memory command semantics should remain identical to production.
        guard persistenceEnabled else {
            if developmentFixture != nil { return true }
            rollback()
            return false
        }
        do {
            try operation()
            commit()
            return true
        } catch {
            rollback()
            persistenceEnabled = false
            persistenceIssue = "\(label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
            persistenceCoordinator.disable(reason: persistenceIssue)
            return false
        }
    }

    // MARK: - Async persistence (non-blocking on MainActor)

    /// Async variant of `persistSafely`. Suspends the calling task during disk
    /// I/O so the main thread remains responsive (satisfies P1-7 requirement).
    @discardableResult
    func persistSafelyAsync(
        _ label: String,
        operation: @Sendable () async throws -> Void,
        commit: @MainActor () -> Void,
        rollback: @MainActor () -> Void
    ) async -> Bool {
        guard persistenceEnabled else {
            if developmentFixture != nil { return true }
            rollback()
            return false
        }
        do {
            try await operation()
            commit()
            return true
        } catch {
            rollback()
            persistenceEnabled = false
            persistenceIssue = "\(label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
            persistenceCoordinator.disable(reason: persistenceIssue)
            return false
        }
    }
}

struct TaskReference: Identifiable, Hashable, Codable, Sendable {
    let goalID: UUID
    let taskID: UUID
    var id: UUID { taskID }
}
