import Foundation

/// P1-3 fix: encapsulates task-timer settlement domain logic.
///
/// The Store coordinates state and persistence; this coordinator handles the
/// pure computation of timer settlement outcomes (actual time, change records,
/// completion credits) independent of persistence and UI concerns.
struct TimerCoordinator {
    let businessCalendar: any BusinessCalendarProviding

    /// Outcome of settling a task timer session.
    struct SettlementOutcome {
        let newActualSeconds: Int
        let newActualMinutes: Int
        let elapsedMinutes: Int
        let changeRecord: TaskChangeRecord
        let completionCredit: CompletionCredit?
    }

    /// Computes the settlement outcome for a completed timer session.
    /// - Parameters:
    ///   - baseActualSeconds: the task's actualSeconds when the timer started.
    ///   - elapsedSeconds: total seconds elapsed in this session.
    ///   - currentTask: the task's current state (for max-clamping).
    ///   - now: settlement timestamp.
    func settle(
        baseActualSeconds: Int,
        elapsedSeconds: Int,
        currentTask: WeekTask,
        now: Date
    ) -> SettlementOutcome {
        let newActualSeconds = baseActualSeconds + elapsedSeconds
        let newActualMinutes = DurationDisplay.minutes(for: newActualSeconds)
        let clampedMinutes = max(currentTask.actualMinutes, newActualMinutes)
        let clampedSeconds = max(currentTask.actualSeconds, newActualSeconds)

        let changeRecord = TaskChangeRecord(
            date: now,
            field: "实际时间",
            oldValue: DurationDisplay.minutes(for: baseActualSeconds).hourMinuteClockText,
            newValue: clampedMinutes.hourMinuteClockText,
            source: .timer
        )

        let alreadyCredited = currentTask.completionCredits.contains {
            $0.reason == .actualTimeLogged && businessCalendar.calendar.isDate($0.date, inSameDayAs: now)
        }
        let credit: CompletionCredit? = alreadyCredited ? nil : CompletionCredit(
            date: now,
            reason: .actualTimeLogged,
            minutes: DurationDisplay.minutes(for: elapsedSeconds),
            seconds: elapsedSeconds
        )

        return SettlementOutcome(
            newActualSeconds: clampedSeconds,
            newActualMinutes: clampedMinutes,
            elapsedMinutes: DurationDisplay.minutes(for: elapsedSeconds),
            changeRecord: changeRecord,
            completionCredit: credit
        )
    }
}
