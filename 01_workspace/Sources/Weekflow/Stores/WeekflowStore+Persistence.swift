import Foundation
import Observation

// All persistence orchestration: sync, async, debounced, and entity-specific writes.

extension WeekflowStore {
    func persist(kind: PersistenceMutationKind = .userEdit) {
        if synchronousPersistence {
            _ = persistSync(kind: kind)
            return
        }
        // Cheap pre-check to avoid scheduling a write when nothing changed.
        guard goals != persistedGoals else { return }
        Task { await enqueueGoalPersist(kind: kind) }
    }

    /// Enqueues a goal persistence write on the coordinator (P0-2/P2-3 fix).
    ///
    /// The diff is computed at EXECUTION time (inside the coordinator's serial
    /// writer) relative to the latest committed baseline, not at enqueue time.
    /// Rapid edits coalesce into a single pending write whose diff is always
    /// correct, eliminating the stale baseline that previously dropped inserts
    /// (e.g. a freshly added goal) and caused out-of-order commits. Exposed as
    /// an async method so `flushPersistence()` can await registration directly.
    func enqueueGoalPersist(kind: PersistenceMutationKind = .userEdit) async {
        await persistenceCoordinator.enqueue(
            label: "周目标与任务",
            operation: { [weak self] in
                guard let self else { return }
                let changes = await MainActor.run {
                    PersistenceGoalChangeSet.difference(
                        before: self.persistedGoals,
                        after: self.goals
                    )
                }
                guard !changes.isEmpty else { return }
                try await self.storage.applyGoalChangesAsync(changes, kind: kind)
            },
            commit: { [weak self] in
                guard let self else { return }
                self.persistedGoals = self.goals
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
    @discardableResult
    func persistSync(kind: PersistenceMutationKind = .userEdit) -> Bool {
        let changes = PersistenceGoalChangeSet.difference(
            before: persistedGoals,
            after: goals
        )
        guard !changes.isEmpty else { return true }
        return persistSafely(
            "周目标与任务",
            operation: { try storage.applyGoalChanges(changes, kind: kind) },
            commit: { persistedGoals = goals },
            rollback: { goals = persistedGoals }
        )
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
        persistSafely(
            "频道",
            operation: { try storage.saveChannels(channels) },
            commit: { persistedChannels = channels },
            rollback: { channels = persistedChannels }
        )
    }

    func persistCalendarEvents() {
        persistSafely(
            "日历事件",
            operation: { try storage.saveCalendarEvents(calendarEvents) },
            commit: { persistedCalendarEvents = calendarEvents },
            rollback: { calendarEvents = persistedCalendarEvents }
        )
    }

    func persistDailyPlanningStates() {
        persistSafely(
            "每日计划",
            operation: { try storage.saveDailyPlanningStates(dailyPlanningStates) },
            commit: { persistedDailyPlanningStates = dailyPlanningStates },
            rollback: { dailyPlanningStates = persistedDailyPlanningStates }
        )
    }

    func persistDailyPlanAndCalendarEvents() {
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
        persistSafely(
            "每日总结",
            operation: { try storage.saveDailySummaries(dailySummaries) },
            commit: { persistedDailySummaries = dailySummaries },
            rollback: { dailySummaries = persistedDailySummaries }
        )
    }

    func persistActiveTaskTimer() {
        let session = activeTaskTimer
        _ = persistSafely(
            "活动计时",
            operation: { try storage.saveActiveTimerSession(session) },
            commit: {},
            rollback: {
                if session != nil { activeTaskTimer = nil }
            }
        )
    }

    func persistTaskAndActiveTimer(rollbackSession: TaskTimerSession?) {
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
        // Use coordinator to serialize writes (P0-2 fix)
        // P0-2 review fix: use [weak self] to avoid retaining the Store if the
        // coordinator holds a pending write during Store deallocation.
        Task { [weak self] in
            guard let self else { return }
            await persistenceCoordinator.enqueue(
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
