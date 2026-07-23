import Foundation
import Observation

// Daily planning cutoff, scheduling, and calendar event operations.

extension WeekflowStore {
    func events(on date: Date) -> [CalendarEvent] {
        calendarEvents.filter { businessCalendar.calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    func dailyPlanningCutoffMinutes(on date: Date) -> Int {
        // Delegate to PlanningService (P2-2)
        planningService.cutoffMinutes(for: date, in: dailyPlanningStates)
    }

    func dailyPlanningStartMinutes(on date: Date) -> Int {
        // Delegate to PlanningService (P2-2)
        planningService.startMinutes(for: date, in: dailyPlanningStates)
    }

    @discardableResult
    func setDailyPlanningStart(minutes: Int, on date: Date) -> Int {
        // Delegate computation to PlanningService (P2-2)
        let result = planningService.withStartMinutes(minutes, on: date, in: dailyPlanningStates)
        dailyPlanningStates = result.states
        persistDailyPlanningChange(on: date, cutoff: result.cutoff)
        return result.start
    }

    @discardableResult
    func setDailyPlanningCutoff(minutes: Int, on date: Date) -> Int {
        // Delegate computation to PlanningService (P2-2)
        let result = planningService.withCutoffMinutes(minutes, on: date, in: dailyPlanningStates)
        dailyPlanningStates = result.states
        persistDailyPlanningChange(on: date, cutoff: result.cutoff)
        return result.cutoff
    }

    /// P1-4: persist a single date's daily-planning change with O(1) single-record
    /// writes (state and/or cutoff calendar event), never a full-array save. Each
    /// call concerns exactly one date, so other dates persist via their own calls.
    private func persistDailyPlanningChange(on date: Date, cutoff: Int) {
        let day = businessCalendar.day(containing: date)
        let state = dailyPlanningStates.first(where: { $0.day == day })
        if dailyPlanningCutoffEvent(on: date) != nil {
            let eventID = upsertDailyPlanningCutoffEvent(on: date, minutes: cutoff, persistImmediately: false)
            let event = calendarEvents.first(where: { $0.id == eventID })
            switch (state, event) {
            case let (state?, event?):
                persistDailyPlanAndCalendarEventRecord(state: state, event: event)
            case let (state?, nil):
                persistDailyPlanningStateRecord(state)
            case let (nil, event?):
                persistCalendarEventRecord(event)
            case (nil, nil):
                break
            }
        } else if let state {
            persistDailyPlanningStateRecord(state)
        }
    }

    /// Ensures every task in a daily plan has a concrete clock time. A newly
    /// assigned pool task receives a one-hour default and is inserted after
    /// the preceding task; overlapping following tasks are shifted forward.
    func ensureDailyPlanningTaskSchedule(
        on date: Date,
        newlyAssigned: TaskReference? = nil
    ) {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.date(
            byAdding: .minute,
            value: dailyPlanningStartMinutes(on: day),
            to: day
        ) ?? day
        var cascadesForward = false
        var changed = false

        for entry in tasks(on: day) {
            let reference = TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
            let isNewlyAssigned = reference == newlyAssigned
            let duration = isNewlyAssigned
                ? 60
                : max(entry.task.estimatedMinutes, 1)
            let normalizedExplicitStart = entry.task.startTime.flatMap { startTime in
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

            if entry.task.startTime != resolvedStart
                || (isNewlyAssigned && entry.task.estimatedMinutes != duration) {
                updateTask(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    persistImmediately: false
                ) { task in
                    task.startTime = resolvedStart
                    if isNewlyAssigned {
                        task.estimatedMinutes = duration
                    }
                }
                changed = true
            }
            cursor = calendar.date(
                byAdding: .minute,
                value: duration,
                to: resolvedStart
            ) ?? resolvedStart
        }

        if changed { persist() }
    }

    func nextDailyPlanningTaskStart(on date: Date) -> Date {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.date(
            byAdding: .minute,
            value: dailyPlanningStartMinutes(on: day),
            to: day
        ) ?? day
        for entry in tasks(on: day) {
            let explicit = entry.task.startTime.flatMap { startTime in
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
                value: max(entry.task.estimatedMinutes, 1),
                to: start
            ) ?? start
        }
        return cursor
    }

    @discardableResult
    func addDailyPlanningCutoffToCalendar(on date: Date) -> UUID {
        upsertDailyPlanningCutoffEvent(
            on: date,
            minutes: dailyPlanningCutoffMinutes(on: date)
        )
    }

    func dailyPlanningCutoffEvent(on date: Date) -> CalendarEvent? {
        let sourceKey = dailyPlanningCutoffSourceKey(for: date)
        return calendarEvents.first { $0.sourceKey == sourceKey }
    }

    func rolloverTaskManually(
        goalID: UUID,
        taskID: UUID,
        from date: Date,
        to targetDate: Date? = nil
    ) {
        let calendar = businessCalendar.calendar
        let sourceDay = calendar.startOfDay(for: date)
        let destinationDay = calendar.startOfDay(
            for: targetDate
                ?? calendar.date(byAdding: .day, value: 1, to: sourceDay)
                ?? sourceDay
        )
        guard let task = task(goalID: goalID, taskID: taskID),
              task.status != .completed,
              !task.isArchived,
              !task.isDeleted,
              (task.plannedDate.map({ calendar.isDate($0, inSameDayAs: sourceDay) }) == true
                || task.isAssigned(on: sourceDay, calendar: calendar)) else { return }

        updateTask(goalID: goalID, taskID: taskID) { item in
            if item.hasExecutionProgress,
               !item.completionCredits.contains(where: {
                   calendar.isDate($0.date, inSameDayAs: sourceDay)
               }) {
                item.completionCredits.append(
                    CompletionCredit(
                        date: sourceDay,
                        reason: item.actualMinutes > 0 ? .actualTimeLogged : .subtaskCompleted,
                        minutes: item.actualMinutes > 0 ? item.actualMinutes : nil
                    )
                )
            }

            if item.plannedDate == nil || item.sourceType == .weeklyObjective {
                item.assignedDates.removeAll {
                    calendar.isDate($0, inSameDayAs: sourceDay)
                }
                if !item.isAssigned(on: destinationDay, calendar: calendar) {
                    item.assignedDates.append(destinationDay)
                }
            } else {
                item.plannedDate = destinationDay
            }
            item.rolloverCount += 1
            item.startTime = nil
            item.executionWeekStart = nil
        }
    }

    func autoScheduleHighlightedTask() {
        guard let highlightedTask, let task = task(goalID: highlightedTask.goalID, taskID: highlightedTask.taskID) else { return }
        let date = activeDay
        let calendar = businessCalendar.calendar
        let startHour = 14
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = startHour
        components.minute = 0
        setTaskSchedule(goalID: highlightedTask.goalID, taskID: highlightedTask.taskID, date: date, startTime: calendar.date(from: components), minutes: task.estimatedMinutes)
        setTaskCalendarPlacement(
            goalID: highlightedTask.goalID,
            taskID: highlightedTask.taskID,
            placement: .committed
        )
    }

}
