import Foundation

/// Daily planning business logic service (P2-2 Store split).
///
/// Encapsulates daily planning rules including cutoff/start time management,
/// task scheduling, and rollover logic. The Store coordinates state and
/// persistence; this service handles the domain rules.
struct PlanningService {
    let businessCalendar: any BusinessCalendarProviding

    init(businessCalendar: any BusinessCalendarProviding = BusinessCalendar()) {
        self.businessCalendar = businessCalendar
    }

    // MARK: - Cutoff/Start Time Queries

    /// Returns the cutoff minutes for a date, or the default if not set.
    func cutoffMinutes(for date: Date, in states: [DailyPlanningState]) -> Int {
        let day = businessCalendar.day(containing: date)
        return states.first { $0.day == day }?.cutoffMinutes
            ?? DailyPlanningState.defaultCutoffMinutes
    }

    /// Returns the start minutes for a date, or the default if not set.
    func startMinutes(for date: Date, in states: [DailyPlanningState]) -> Int {
        let day = businessCalendar.day(containing: date)
        return states.first { $0.day == day }?.startMinutes
            ?? DailyPlanningState.defaultStartMinutes
    }

    // MARK: - Cutoff/Start Time Updates

    /// Computes the updated state when setting start minutes.
    /// Returns (normalizedStart, adjustedCutoff, updatedStates).
    func withStartMinutes(
        _ minutes: Int,
        on date: Date,
        in states: [DailyPlanningState]
    ) -> (start: Int, cutoff: Int, states: [DailyPlanningState]) {
        let normalized = DailyPlanningState.normalizedStartMinutes(minutes)
        let currentCutoff = cutoffMinutes(for: date, in: states)
        let adjustedCutoff = currentCutoff > normalized
            ? currentCutoff
            : min(
                normalized + DailyPlanningState.cutoffStepMinutes,
                DailyPlanningState.maximumCutoffMinutes
            )

        var updatedStates = states
        if let index = updatedStates.firstIndex(where: {
            businessCalendar.calendar.isDate($0.date, inSameDayAs: date)
        }) {
            updatedStates[index].startMinutes = normalized
            updatedStates[index].cutoffMinutes = adjustedCutoff
        } else {
            updatedStates.append(
                DailyPlanningState(
                    date: date,
                    startMinutes: normalized,
                    cutoffMinutes: adjustedCutoff
                )
            )
        }
        return (normalized, adjustedCutoff, updatedStates)
    }

    /// Computes the updated state when setting cutoff minutes.
    /// Returns (adjustedStart, normalizedCutoff, updatedStates).
    func withCutoffMinutes(
        _ minutes: Int,
        on date: Date,
        in states: [DailyPlanningState]
    ) -> (start: Int, cutoff: Int, states: [DailyPlanningState]) {
        let normalized = DailyPlanningState.normalizedCutoffMinutes(minutes)
        let currentStart = startMinutes(for: date, in: states)
        let adjustedStart = currentStart < normalized
            ? currentStart
            : max(
                normalized - DailyPlanningState.startStepMinutes,
                DailyPlanningState.minimumStartMinutes
            )

        var updatedStates = states
        if let index = updatedStates.firstIndex(where: {
            businessCalendar.calendar.isDate($0.date, inSameDayAs: date)
        }) {
            updatedStates[index].startMinutes = adjustedStart
            updatedStates[index].cutoffMinutes = normalized
        } else {
            updatedStates.append(
                DailyPlanningState(
                    date: date,
                    startMinutes: adjustedStart,
                    cutoffMinutes: normalized
                )
            )
        }
        return (adjustedStart, normalized, updatedStates)
    }

    // MARK: - Task Scheduling

    /// Computes the next available start time for a new task on a date.
    func nextTaskStart(
        on date: Date,
        tasks: [(startTime: Date?, estimatedMinutes: Int)],
        startMinutes: Int
    ) -> Date {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.date(
            byAdding: .minute,
            value: startMinutes,
            to: day
        ) ?? day

        for task in tasks {
            let explicit = task.startTime.flatMap { startTime in
                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                return calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: day
                )
            }
            let start = explicit ?? cursor
            cursor = calendar.date(
                byAdding: .minute,
                value: max(task.estimatedMinutes, 1),
                to: start
            ) ?? start
        }
        return cursor
    }

    /// Computes scheduled times for all tasks in a day.
    /// Returns an array of (taskIndex, startTime, estimatedMinutes) for tasks that need updates.
    func computeDailySchedule(
        on date: Date,
        tasks: [(id: UUID, startTime: Date?, estimatedMinutes: Int)],
        startMinutes: Int,
        newlyAssignedID: UUID? = nil
    ) -> [(id: UUID, startTime: Date, estimatedMinutes: Int)] {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.date(
            byAdding: .minute,
            value: startMinutes,
            to: day
        ) ?? day
        var cascadesForward = false
        var updates: [(id: UUID, startTime: Date, estimatedMinutes: Int)] = []

        for task in tasks {
            let isNewlyAssigned = task.id == newlyAssignedID
            let duration = isNewlyAssigned ? 60 : max(task.estimatedMinutes, 1)
            let normalizedExplicitStart = task.startTime.flatMap { startTime in
                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                return calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: day
                )
            }

            let resolvedStart: Date
            if isNewlyAssigned || normalizedExplicitStart == nil {
                resolvedStart = cursor
                cascadesForward = true
            } else if cascadesForward,
                      let normalizedExplicitStart,
                      normalizedExplicitStart < cursor {
                resolvedStart = cursor
            } else {
                resolvedStart = normalizedExplicitStart ?? cursor
            }

            if task.startTime != resolvedStart || (isNewlyAssigned && task.estimatedMinutes != duration) {
                updates.append((id: task.id, startTime: resolvedStart, estimatedMinutes: duration))
            }
            cursor = calendar.date(
                byAdding: .minute,
                value: duration,
                to: resolvedStart
            ) ?? resolvedStart
        }
        return updates
    }

    // MARK: - Rollover

    /// Computes the target date for a rollover task.
    func rolloverTargetDate(from sourceDate: Date, to targetDate: Date? = nil) -> Date {
        let calendar = businessCalendar.calendar
        let sourceDay = calendar.startOfDay(for: sourceDate)
        return calendar.startOfDay(
            for: targetDate
                ?? calendar.date(byAdding: .day, value: 1, to: sourceDay)
                ?? sourceDay
        )
    }

    // MARK: - Calendar Event Keys

    /// Generates the source key for a daily planning cutoff event.
    func cutoffSourceKey(for date: Date) -> String {
        let day = businessCalendar.day(containing: date)
        return "dailyPlanningCutoff:\(day.persistenceKey)"
    }

    /// Computes the cutoff date/time for a given day and cutoff minutes.
    func cutoffDate(on date: Date, minutes: Int) -> Date {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
    }
}
