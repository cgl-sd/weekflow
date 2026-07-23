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
        persistenceCoordinator.enqueue(
            domain: "goals",
            label: "周目标与任务",
            operation: { [weak self] in
                guard let self else { return }
                // P1-5 fix: only snapshot capture on MainActor (fast value copy).
                let (currentGoals, baselineGoals) = await MainActor.run {
                    (self.goals, self.persistedGoals)
                }
                // Expensive diff computed OFF MainActor.
                let changes = PersistenceGoalChangeSet.difference(
                    before: baselineGoals,
                    after: currentGoals
                )
                guard !changes.isEmpty else { return }
                try await self.storage.applyGoalChangesAsync(changes, kind: kind)
                // Store the snapshot on this write's own box for commit (P0-1 + Phase 2-3).
                await MainActor.run {
                    box.snapshot = currentGoals
                }
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
        persistenceCoordinator.beginSyncWrite()

        let changes = PersistenceGoalChangeSet.difference(
            before: persistedGoals,
            after: goals
        )
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
        let snapshot = WeekflowPersistenceSnapshot(
            goals: goals,
            channels: channels,
            calendarEvents: calendarEvents,
            dailyPlanningStates: dailyPlanningStates,
            focusRecords: focusRecords,
            dailySummaries: dailySummaries
        )
        persistSafely(
            "启动同步",
            operation: { try storage.saveApplicationSnapshot(snapshot) },
            commit: {
                persistedGoals = goals
                persistedChannels = channels
                persistedCalendarEvents = calendarEvents
                persistedDailyPlanningStates = dailyPlanningStates
                persistedFocusRecords = focusRecords
                persistedDailySummaries = dailySummaries
            },
            rollback: {
                goals = persistedGoals
                invalidateGoalIndex()
                channels = persistedChannels
                calendarEvents = persistedCalendarEvents
                dailyPlanningStates = persistedDailyPlanningStates
                focusRecords = persistedFocusRecords
                dailySummaries = persistedDailySummaries
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

    func persistCalendarEvents() {
        if synchronousPersistence {
            persistSafely(
                "日历事件",
                operation: { try storage.saveCalendarEvents(calendarEvents) },
                commit: { persistedCalendarEvents = calendarEvents },
                rollback: { calendarEvents = persistedCalendarEvents }
            )
            return
        }
        // P1-4 fix: non-blocking write via coordinator.
        // Self-check fix: dedicated domain prevents coalescing data loss.
        let snapshot = calendarEvents
        let rollbackSnapshot = persistedCalendarEvents
        persistenceCoordinator.enqueue(
            domain: "calendarEvents",
            label: "日历事件",
            operation: { [weak self] in
                try await self?.storage.saveCalendarEventsAsync(snapshot)
            },
            commit: { [weak self] in self?.persistedCalendarEvents = snapshot },
            rollback: { [weak self] in self?.calendarEvents = rollbackSnapshot }
        )
    }

    func persistDailyPlanningStates() {
        if synchronousPersistence {
            persistSafely(
                "每日计划",
                operation: { try storage.saveDailyPlanningStates(dailyPlanningStates) },
                commit: { persistedDailyPlanningStates = dailyPlanningStates },
                rollback: { dailyPlanningStates = persistedDailyPlanningStates }
            )
            return
        }
        // P1-4 fix: non-blocking write via coordinator.
        // Self-check fix: dedicated domain prevents coalescing data loss.
        let snapshot = dailyPlanningStates
        let rollbackSnapshot = persistedDailyPlanningStates
        persistenceCoordinator.enqueue(
            domain: "dailyPlanning",
            label: "每日计划",
            operation: { [weak self] in
                try await self?.storage.saveDailyPlanningStatesAsync(snapshot)
            },
            commit: { [weak self] in self?.persistedDailyPlanningStates = snapshot },
            rollback: { [weak self] in self?.dailyPlanningStates = rollbackSnapshot }
        )
    }

    func persistDailyPlanAndCalendarEvents() {
        if synchronousPersistence {
            persistSafely(
                "每日计划与日历事件",
                operation: {
                    try storage.saveDailyPlanAndCalendarEvents(
                        states: dailyPlanningStates,
                        events: calendarEvents
                    )
                },
                commit: {
                    persistedDailyPlanningStates = dailyPlanningStates
                    persistedCalendarEvents = calendarEvents
                },
                rollback: {
                    dailyPlanningStates = persistedDailyPlanningStates
                    calendarEvents = persistedCalendarEvents
                }
            )
            return
        }
        // Atomic async write: both entities in ONE transaction on a dedicated
        // domain so they always succeed or fail together.
        let statesSnapshot = dailyPlanningStates
        let eventsSnapshot = calendarEvents
        let rollbackStates = persistedDailyPlanningStates
        let rollbackEvents = persistedCalendarEvents
        persistenceCoordinator.enqueue(
            domain: "dailyPlanCalendar",
            label: "每日计划与日历事件",
            operation: { [weak self] in
                try await self?.storage.saveDailyPlanAndCalendarEventsAsync(
                    states: statesSnapshot,
                    events: eventsSnapshot
                )
            },
            commit: { [weak self] in
                self?.persistedDailyPlanningStates = statesSnapshot
                self?.persistedCalendarEvents = eventsSnapshot
            },
            rollback: { [weak self] in
                self?.dailyPlanningStates = rollbackStates
                self?.calendarEvents = rollbackEvents
            }
        )
    }

    func persistFocusRecords() {
        if synchronousPersistence {
            persistSafely(
                "专注记录",
                operation: { try storage.saveFocusRecords(focusRecords) },
                commit: { persistedFocusRecords = focusRecords },
                rollback: { focusRecords = persistedFocusRecords }
            )
            return
        }
        // Non-blocking: focus records are append-only and don't need sync
        // confirmation for interactive responsiveness (P1-7).
        persistFocusRecordsAsync()
    }

    func persistDailySummaries() {
        if synchronousPersistence {
            persistSafely(
                "每日总结",
                operation: { try storage.saveDailySummaries(dailySummaries) },
                commit: { persistedDailySummaries = dailySummaries },
                rollback: { dailySummaries = persistedDailySummaries }
            )
            return
        }
        // P1-4 fix: non-blocking write via coordinator.
        // Self-check fix: dedicated domain prevents coalescing data loss.
        let snapshot = dailySummaries
        let rollbackSnapshot = persistedDailySummaries
        persistenceCoordinator.enqueue(
            domain: "dailySummaries",
            label: "每日总结",
            operation: { [weak self] in
                try await self?.storage.saveDailySummariesAsync(snapshot)
            },
            commit: { [weak self] in self?.persistedDailySummaries = snapshot },
            rollback: { [weak self] in self?.dailySummaries = rollbackSnapshot }
        )
    }

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

    func persistTaskAndActiveTimer(rollbackSession: TaskTimerSession?) {
        if synchronousPersistence {
            let changes = PersistenceGoalChangeSet.difference(
                before: persistedGoals,
                after: goals
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
                commit: { persistedGoals = goals },
                rollback: {
                    goals = persistedGoals
                    invalidateGoalIndex()
                    taskTimerService.restore(session: rollbackSession)
                }
            )
            return
        }
        // P1-4 fix: non-blocking write via coordinator.
        // Cancel pending goal writes to avoid conflicts with this combined write.
        persistenceCoordinator.cancelPending(for: "goals")
        // Phase 2-3 fix: per-write snapshot box instead of a shared Store slot.
        let box = GoalSnapshotBox()
        // Self-check fix: diff computed OFF MainActor (consistent with P1-5).
        persistenceCoordinator.enqueue(
            domain: "goals",
            label: "任务与活动计时",
            operation: { [weak self] in
                guard let self else { return }
                let (currentGoals, baselineGoals, session) = await MainActor.run {
                    (self.goals, self.persistedGoals, self.activeTaskTimer)
                }
                let changes = PersistenceGoalChangeSet.difference(
                    before: baselineGoals,
                    after: currentGoals
                )
                try await self.storage.saveGoalChangesAndActiveTimerAsync(
                    changes: changes,
                    session: session
                )
                await MainActor.run {
                    box.snapshot = currentGoals
                }
            },
            commit: { [weak self] in
                guard let self else { return }
                if let snapshot = box.snapshot {
                    self.persistedGoals = snapshot
                } else {
                    self.persistedGoals = self.goals
                }
            },
            rollback: { [weak self] in
                self?.goals = self?.persistedGoals ?? []
                self?.invalidateGoalIndex()
                self?.taskTimerService.restore(session: rollbackSession)
            }
        )
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
            return false
        }
    }

    func persistFocusRecordsAsync() {
        let records = focusRecords
        let snapshot = persistedFocusRecords
        // P0-2 fix: use separate domain so focus writes never overwrite goal writes
        Task { [weak self] in
            guard let self else { return }
            persistenceCoordinator.enqueue(
                domain: "focusRecords",
                label: "专注记录",
                operation: { try await self.storage.saveFocusRecordsAsync(records) },
                commit: { self.persistedFocusRecords = records },
                rollback: { self.focusRecords = snapshot }
            )
        }
    }
}

struct TaskReference: Identifiable, Hashable, Codable, Sendable {
    let goalID: UUID
    let taskID: UUID
    var id: UUID { taskID }
}
