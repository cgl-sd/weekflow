import Foundation

/// R08: builds the atomic persistence snapshot from the store's current state.
/// Centralizing the assembly keeps the startup and termination persist paths
/// consistent (both must capture the same set of entities atomically).
struct ApplicationSnapshotService {
    func makeSnapshot(
        goals: [WeeklyGoal],
        plans: [WeeklyPlan],
        channels: [TaskChannel],
        calendarEvents: [CalendarEvent],
        dailyPlanningStates: [DailyPlanningState],
        focusRecords: [FocusRecord],
        dailySummaries: [DailySummary],
        activeTimerSession: TaskTimerSession?
    ) -> WeekflowPersistenceSnapshot {
        WeekflowPersistenceSnapshot(
            goals: goals,
            plans: plans,
            channels: channels,
            calendarEvents: calendarEvents,
            dailyPlanningStates: dailyPlanningStates,
            focusRecords: focusRecords,
            dailySummaries: dailySummaries,
            activeTimerSession: activeTimerSession
        )
    }
}
