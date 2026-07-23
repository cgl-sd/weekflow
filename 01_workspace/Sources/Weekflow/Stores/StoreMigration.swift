import Foundation
import Observation

// Startup migrations, payload normalization, and legacy data upgrades.

extension WeekflowStore {
    func synchronizeAllSubgoalTasksIfNeeded() -> Bool {
        let migrationKey = "weekflow.goals.projectionSync.v2"
        guard !legacyPreferences.bool(forKey: migrationKey) else { return false }
        let synchronizedGoals = goals.map { goalService.project($0) }
        legacyPreferences.set(true, forKey: migrationKey)
        guard synchronizedGoals != goals else { return false }
        goals = synchronizedGoals
        invalidateGoalIndex()
        return true
    }

    /// P1-1: One-time eager payload normalization. Re-encodes all persisted
    /// records at the storage layer so no mixed-format payloads remain after
    /// a version upgrade. Runs directly on the repository (not through in-memory
    /// state) to guarantee disk consistency regardless of Store mutations.
    func normalizePersistedPayloadsIfNeeded() {
        do {
            _ = try storage.normalizeAllPayloadsIfNeeded(marker: "payloadNormalization.v1")
        } catch {
            persistenceEnabled = false
            persistenceIssue = "持久化数据格式规范化失败，本次会话已暂停保存，以免覆盖原文件。\n\n\(error.localizedDescription)"
            persistenceCoordinator.disable(reason: persistenceIssue)
        }
    }

    func upsertDailyPlanningCutoffEvent(
        on date: Date,
        minutes: Int,
        persistImmediately: Bool = true
    ) -> UUID {
        let sourceKey = dailyPlanningCutoffSourceKey(for: date)
        let startDate = cutoffDate(on: date, minutes: minutes)
        if let index = calendarEvents.firstIndex(where: { $0.sourceKey == sourceKey }) {
            calendarEvents[index].title = "工作截止时间"
            calendarEvents[index].startDate = startDate
            calendarEvents[index].durationMinutes = 30
            calendarEvents[index].colorName = "purple"
            if persistImmediately { persistCalendarEventRecord(calendarEvents[index]) }
            return calendarEvents[index].id
        }

        let event = CalendarEvent(
            title: "工作截止时间",
            startDate: startDate,
            durationMinutes: 30,
            colorName: "purple",
            sourceKey: sourceKey
        )
        calendarEvents.append(event)
        if persistImmediately { persistCalendarEventRecord(event) }
        return event.id
    }

    /// P1-7 Fix: Delegate to PlanningService for consistent cutoff date calculation.
    func cutoffDate(on date: Date, minutes: Int) -> Date {
        planningService.cutoffDate(on: date, minutes: minutes)
    }

    /// P1-7 Fix: Delegate to PlanningService for consistent source key format.
    func dailyPlanningCutoffSourceKey(for date: Date) -> String {
        planningService.cutoffSourceKey(for: date)
    }

    @discardableResult
    func migrateLegacyDailyPlanningCutoffIfNeeded() -> Bool {
        let key = "weekflow.dailyPlanning.shutdownHour"
        guard dailyPlanningStates.isEmpty,
              let legacyHour = legacyPreferences.object(forKey: key) as? Int,
              (17...23).contains(legacyHour),
              let tomorrow = businessCalendar.calendar.date(byAdding: .day, value: 1, to: .now) else { return false }
        dailyPlanningStates = [
            DailyPlanningState(date: tomorrow, cutoffMinutes: legacyHour * 60)
        ]
        legacyPreferences.removeObject(forKey: key)
        return true
    }

    @discardableResult
    func migrateLegacyDailySummaryIfNeeded() -> Bool {
        let summaryKey = "weekflow.dailyShutdownSummary"
        let dateKey = "weekflow.dailyShutdownSummaryDate"
        guard dailySummaries.isEmpty,
              let legacySummary = legacyPreferences.string(forKey: summaryKey),
              !legacySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        dailySummaries = [DailySummary(date: businessCalendar.calendar.startOfDay(for: .now), content: legacySummary)]
        legacyPreferences.removeObject(forKey: summaryKey)
        legacyPreferences.removeObject(forKey: dateKey)
        return true
    }

    /// P4-16 fix: delegates to TaskService.changeRecords (single source of truth).
}
