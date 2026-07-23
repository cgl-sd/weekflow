import Foundation

extension WeekflowStore {
    func persistCalendarEventRecord(_ event: CalendarEvent) {
        let previous = persistedCalendarEvents.first(where: { $0.id == event.id })
        if synchronousPersistence {
            _ = persistSafely(
                "日历事件",
                operation: { try storage.upsertCalendarEvent(event) },
                commit: { replacePersistedCalendarEvent(event) },
                rollback: { restoreCalendarEvent(id: event.id, previous: previous) }
            )
            return
        }
        persistenceCoordinator.enqueue(
            domain: "calendarEvent:\(event.id.uuidString)",
            label: "日历事件",
            operation: { [weak self] in try await self?.storage.upsertCalendarEventAsync(event) },
            commit: { [weak self] in self?.replacePersistedCalendarEvent(event) },
            rollback: { [weak self] in self?.restoreCalendarEvent(id: event.id, previous: previous) }
        )
    }

    func persistFocusRecord(_ record: FocusRecord) {
        let previous = persistedFocusRecords.first(where: { $0.id == record.id })
        if synchronousPersistence {
            _ = persistSafely(
                "专注记录",
                operation: { try storage.upsertFocusRecord(record) },
                commit: { replacePersistedFocusRecord(record) },
                rollback: { restoreFocusRecord(id: record.id, previous: previous) }
            )
            return
        }
        persistenceCoordinator.enqueue(
            domain: "focusRecord:\(record.id.uuidString)",
            label: "专注记录",
            operation: { [weak self] in try await self?.storage.upsertFocusRecordAsync(record) },
            commit: { [weak self] in self?.replacePersistedFocusRecord(record) },
            rollback: { [weak self] in self?.restoreFocusRecord(id: record.id, previous: previous) }
        )
    }

    func persistDailySummaryRecord(_ summary: DailySummary) {
        let key = summary.day.persistenceKey
        let previous = persistedDailySummaries.first(where: { $0.day == summary.day })
        if synchronousPersistence {
            _ = persistSafely(
                "每日总结",
                operation: { try storage.upsertDailySummary(summary) },
                commit: { replacePersistedDailySummary(summary) },
                rollback: { restoreDailySummary(day: summary.day, previous: previous) }
            )
            return
        }
        persistenceCoordinator.enqueue(
            domain: "dailySummary:\(key)",
            label: "每日总结",
            operation: { [weak self] in try await self?.storage.upsertDailySummaryAsync(summary) },
            commit: { [weak self] in self?.replacePersistedDailySummary(summary) },
            rollback: { [weak self] in self?.restoreDailySummary(day: summary.day, previous: previous) }
        )
    }

    func persistDailyPlanningStateRecord(_ state: DailyPlanningState) {
        let key = state.day.persistenceKey
        let previous = persistedDailyPlanningStates.first(where: { $0.day == state.day })
        if synchronousPersistence {
            _ = persistSafely(
                "每日计划",
                operation: { try storage.upsertDailyPlanningState(state) },
                commit: { replacePersistedDailyPlanningState(state) },
                rollback: { restoreDailyPlanningState(day: state.day, previous: previous) }
            )
            return
        }
        persistenceCoordinator.enqueue(
            domain: "dailyPlanning:\(key)",
            label: "每日计划",
            operation: { [weak self] in try await self?.storage.upsertDailyPlanningStateAsync(state) },
            commit: { [weak self] in self?.replacePersistedDailyPlanningState(state) },
            rollback: { [weak self] in self?.restoreDailyPlanningState(day: state.day, previous: previous) }
        )
    }

    func persistDailyPlanAndCalendarEventRecord(
        state: DailyPlanningState,
        event: CalendarEvent
    ) {
        let domain = "dailyPlanCalendar:\(state.day.persistenceKey):\(event.id.uuidString)"
        let previousState = persistedDailyPlanningStates.first(where: { $0.day == state.day })
        let previousEvent = persistedCalendarEvents.first(where: { $0.id == event.id })
        if synchronousPersistence {
            _ = persistSafely(
                "每日计划与日历事件",
                operation: { try storage.upsertDailyPlanAndCalendarEvent(state: state, event: event) },
                commit: {
                    replacePersistedDailyPlanningState(state)
                    replacePersistedCalendarEvent(event)
                },
                rollback: {
                    restoreDailyPlanningState(day: state.day, previous: previousState)
                    restoreCalendarEvent(id: event.id, previous: previousEvent)
                }
            )
            return
        }
        persistenceCoordinator.enqueue(
            domain: domain,
            label: "每日计划与日历事件",
            operation: { [weak self] in
                try await self?.storage.upsertDailyPlanAndCalendarEventAsync(state: state, event: event)
            },
            commit: { [weak self] in
                self?.replacePersistedDailyPlanningState(state)
                self?.replacePersistedCalendarEvent(event)
            },
            rollback: { [weak self] in
                self?.restoreDailyPlanningState(day: state.day, previous: previousState)
                self?.restoreCalendarEvent(id: event.id, previous: previousEvent)
            }
        )
    }

    private func restoreCalendarEvent(id: UUID, previous: CalendarEvent?) {
        calendarEvents.removeAll { $0.id == id }
        if let previous { calendarEvents.append(previous) }
    }

    private func restoreFocusRecord(id: UUID, previous: FocusRecord?) {
        focusRecords.removeAll { $0.id == id }
        if let previous { focusRecords.append(previous) }
    }

    private func restoreDailySummary(day: LocalDay, previous: DailySummary?) {
        dailySummaries.removeAll { $0.day == day }
        if let previous { dailySummaries.append(previous) }
    }

    private func restoreDailyPlanningState(day: LocalDay, previous: DailyPlanningState?) {
        dailyPlanningStates.removeAll { $0.day == day }
        if let previous { dailyPlanningStates.append(previous) }
    }

    private func replacePersistedCalendarEvent(_ event: CalendarEvent) {
        if let index = persistedCalendarEvents.firstIndex(where: { $0.id == event.id }) {
            persistedCalendarEvents[index] = event
        } else {
            persistedCalendarEvents.append(event)
        }
    }

    private func replacePersistedFocusRecord(_ record: FocusRecord) {
        if let index = persistedFocusRecords.firstIndex(where: { $0.id == record.id }) {
            persistedFocusRecords[index] = record
        } else {
            persistedFocusRecords.append(record)
        }
    }

    private func replacePersistedDailySummary(_ summary: DailySummary) {
        if let index = persistedDailySummaries.firstIndex(where: { $0.day == summary.day }) {
            persistedDailySummaries[index] = summary
        } else {
            persistedDailySummaries.append(summary)
        }
    }

    private func replacePersistedDailyPlanningState(_ state: DailyPlanningState) {
        if let index = persistedDailyPlanningStates.firstIndex(where: { $0.day == state.day }) {
            persistedDailyPlanningStates[index] = state
        } else {
            persistedDailyPlanningStates.append(state)
        }
    }
}
