import Foundation
import Observation

// Task timer start/pause/settle/recovery operations.

extension WeekflowStore {
    // MARK: - Task Timer (delegated to TaskTimerService – P2-2)

    func isTaskTimerRunning(goalID: UUID, taskID: UUID) -> Bool {
        taskTimerService.isRunning(goalID: goalID, taskID: taskID)
    }

    func taskTimerStartedAt(goalID: UUID, taskID: UUID) -> Date? {
        taskTimerService.startedAt(goalID: goalID, taskID: taskID)
    }

    func liveTaskActualMinutes(goalID: UUID, taskID: UUID, at date: Date = .now) -> Int {
        guard let current = task(goalID: goalID, taskID: taskID) else { return 0 }
        return taskTimerService.liveActualMinutes(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: current.actualSeconds, at: date
        )
    }

    func startTaskTimer(goalID: UUID, taskID: UUID) {
        startTaskTimer(goalID: goalID, taskID: taskID, now: .now, useMonotonicClock: true)
    }

    func startTaskTimer(goalID: UUID, taskID: UUID, now: Date) {
        startTaskTimer(goalID: goalID, taskID: taskID, now: now, useMonotonicClock: false)
    }

    func startTaskTimer(
        goalID: UUID,
        taskID: UUID,
        now: Date,
        useMonotonicClock: Bool
    ) {
        guard let current = task(goalID: goalID, taskID: taskID) else { return }
        let rollbackSession = taskTimerService.activeSession
        let settled = taskTimerService.start(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: current.actualSeconds,
            now: now, useMonotonicClock: useMonotonicClock
        )
        if let settled {
            _ = settleTaskTimer(
                goalID: settled.settledGoalID,
                taskID: settled.settledTaskID,
                baseActualSeconds: rollbackSession?.baseActualSeconds ?? 0,
                elapsedSeconds: settled.settledSeconds,
                now: now,
                persistImmediately: false
            )
        }
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: false) { task in
            task.status = .inProgress
            task.archivedAt = nil
        }
        persistTaskAndActiveTimer(rollbackSession: rollbackSession)
    }

    @discardableResult
    func pauseTaskTimer(goalID: UUID, taskID: UUID) -> Int {
        guard let result = taskTimerService.pause(goalID: goalID, taskID: taskID) else { return 0 }
        return settleTaskTimer(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: result.session.baseActualSeconds,
            elapsedSeconds: result.elapsedSeconds,
            now: .now,
            rollbackSession: result.session
        )
    }

    @discardableResult
    func pauseTaskTimer(goalID: UUID, taskID: UUID, now: Date) -> Int {
        guard let result = taskTimerService.pause(
            goalID: goalID, taskID: taskID, now: now, useMonotonicClock: false
        ) else { return 0 }
        return settleTaskTimer(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: result.session.baseActualSeconds,
            elapsedSeconds: result.elapsedSeconds,
            now: now,
            rollbackSession: result.session
        )
    }

    func settleTaskTimer(
        goalID: UUID,
        taskID: UUID,
        baseActualSeconds: Int,
        elapsedSeconds: Int,
        now: Date,
        persistImmediately: Bool = true,
        rollbackSession: TaskTimerSession? = nil
    ) -> Int {
        guard let current = task(goalID: goalID, taskID: taskID) else { return 0 }
        // P1-3 fix: delegate settlement computation to TimerCoordinator.
        let outcome = timerCoordinator.settle(
            baseActualSeconds: baseActualSeconds,
            elapsedSeconds: elapsedSeconds,
            currentTask: current,
            now: now
        )
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: false) { task in
            task.actualMinutes = outcome.newActualMinutes
            task.actualSeconds = outcome.newActualSeconds
            task.status = .planned
            task.changeRecords.append(outcome.changeRecord)
            if let credit = outcome.completionCredit {
                task.completionCredits.append(credit)
            }
        }
        if persistImmediately {
            persistTaskAndActiveTimer(rollbackSession: rollbackSession)
        }
        return outcome.elapsedMinutes
    }

    func toggleTaskTimer(goalID: UUID, taskID: UUID) {
        if isTaskTimerRunning(goalID: goalID, taskID: taskID) {
            pauseTaskTimer(goalID: goalID, taskID: taskID)
        } else {
            startTaskTimer(goalID: goalID, taskID: taskID)
        }
    }

    func toggleTaskTimer(goalID: UUID, taskID: UUID, now: Date) {
        if isTaskTimerRunning(goalID: goalID, taskID: taskID) {
            pauseTaskTimer(goalID: goalID, taskID: taskID, now: now)
        } else {
            startTaskTimer(goalID: goalID, taskID: taskID, now: now)
        }
    }

    func resolveInterruptedTimer(includeElapsedTime: Bool, now: Date = .now) {
        guard let recovery = taskTimerService.pendingRecovery else { return }
        if includeElapsedTime {
            taskTimerService.setRecovery(nil)
            _ = settleTaskTimer(
                goalID: recovery.session.goalID,
                taskID: recovery.session.taskID,
                baseActualSeconds: recovery.session.baseActualSeconds,
                elapsedSeconds: recovery.elapsedSeconds,
                now: now
            )
        } else {
            taskTimerService.setRecovery(nil)
            taskTimerService.clear()
            updateTask(
                goalID: recovery.session.goalID,
                taskID: recovery.session.taskID,
                persistImmediately: false
            ) { task in
                if task.status == .inProgress { task.status = .planned }
            }
            persistTaskAndActiveTimer(rollbackSession: recovery.session)
        }
    }

    func synchronizeActiveTaskTimer(at date: Date = .now) {
        guard let session = taskTimerService.activeSession,
              let current = task(goalID: session.goalID, taskID: session.taskID) else { return }
        let liveMinutes = liveTaskActualMinutes(goalID: session.goalID, taskID: session.taskID, at: date)
        guard liveMinutes > current.actualMinutes else { return }
        updateTask(goalID: session.goalID, taskID: session.taskID) { task in
            task.actualMinutes = liveMinutes
            task.status = .inProgress
        }
    }

    func checkpointActiveTaskTimer(at date: Date = .now) {
        guard let result = taskTimerService.checkpoint(at: date) else { return }
        let checkpointSeconds = result.updated.baseActualSeconds
        updateTask(
            goalID: result.updated.goalID,
            taskID: result.updated.taskID,
            persistImmediately: false
        ) { task in
            task.actualSeconds = max(task.actualSeconds, checkpointSeconds)
            task.actualMinutes = DurationDisplay.minutes(for: task.actualSeconds)
            task.status = .inProgress
        }
        persistTaskAndActiveTimer(rollbackSession: result.previous)
    }

    func recordFocusMinutes(for reference: TaskReference, minutes: Int, now: Date = .now) {
        recordFocusSeconds(for: reference, seconds: minutes * 60, now: now)
    }

    func recordFocusSeconds(for reference: TaskReference, seconds: Int, now: Date = .now) {
        guard seconds > 0, let current = task(goalID: reference.goalID, taskID: reference.taskID) else { return }
        let newActualSeconds = current.actualSeconds + seconds
        let newActualMinutes = DurationDisplay.minutes(for: newActualSeconds)
        updateTask(goalID: reference.goalID, taskID: reference.taskID) { task in
            task.actualMinutes = newActualMinutes
            task.actualSeconds = newActualSeconds
            task.changeRecords.append(TaskChangeRecord(
                date: now,
                field: "实际时间",
                oldValue: current.actualMinutes.hourMinuteClockText,
                newValue: newActualMinutes.hourMinuteClockText,
                source: .timer
            ))
        }
    }

    func recordFocusSession(mode: FocusMode, minutes: Int, date: Date = .now) {
        recordFocusSession(mode: mode, seconds: minutes * 60, date: date)
    }

    func recordFocusSession(mode: FocusMode, seconds: Int, date: Date = .now) {
        guard seconds > 0 else { return }
        let calendar = businessCalendar.calendar
        if let index = focusRecords.firstIndex(where: {
            $0.mode == mode && calendar.isDate($0.date, inSameDayAs: date)
        }) {
            focusRecords[index].seconds += seconds
            focusRecords[index].sessionCount += 1
            focusRecords[index].date = date
        } else {
            focusRecords.append(FocusRecord(
                date: date,
                mode: mode,
                seconds: seconds
            ))
        }
        persistFocusRecords()
    }

    func focusMinutes(on date: Date) -> [FocusMode: Int] {
        Dictionary(grouping: focusRecords.filter {
            businessCalendar.calendar.isDate($0.date, inSameDayAs: date)
        }, by: \.mode)
        .mapValues { $0.reduce(0) { $0 + $1.minutes } }
    }

    func dailySummary(on date: Date) -> DailySummary? {
        dailySummaries.first { businessCalendar.calendar.isDate($0.date, inSameDayAs: date) }
    }

    func saveDailySummary(_ content: String, on date: Date = .now) {
        let day = businessCalendar.calendar.startOfDay(for: date)
        if let index = dailySummaries.firstIndex(where: {
            businessCalendar.calendar.isDate($0.date, inSameDayAs: day)
        }) {
            dailySummaries[index].content = content
            dailySummaries[index].updatedAt = .now
        } else {
            dailySummaries.append(DailySummary(date: day, content: content))
        }
        persistDailySummaries()
    }

}
