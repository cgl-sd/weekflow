import Foundation

/// Encapsulates task-linked timer state and logic. Extracted from
/// WeekflowStore to satisfy P2-2 (Store split) – the timer business logic
/// is independently testable and does not depend on SwiftUI.
///
/// The Store delegates timer operations to this service and publishes the
/// resulting state changes to the UI layer.
@MainActor
@Observable
final class TaskTimerService {
    private(set) var activeSession: TaskTimerSession?
    private(set) var pendingRecovery: InterruptedTaskTimerRecovery?

    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private var startedInstant: ContinuousClock.Instant?
    @ObservationIgnored private let businessCalendar: any BusinessCalendarProviding

    init(businessCalendar: any BusinessCalendarProviding = BusinessCalendar()) {
        self.businessCalendar = businessCalendar
    }

    // MARK: - Queries

    func isRunning(goalID: UUID, taskID: UUID) -> Bool {
        activeSession?.matches(goalID: goalID, taskID: taskID) == true
    }

    func startedAt(goalID: UUID, taskID: UUID) -> Date? {
        guard activeSession?.matches(goalID: goalID, taskID: taskID) == true else { return nil }
        return activeSession?.startedAt
    }

    func liveActualSeconds(goalID: UUID, taskID: UUID, baseActualSeconds: Int, at date: Date = .now) -> Int {
        guard let session = activeSession,
              session.matches(goalID: goalID, taskID: taskID) else { return baseActualSeconds }
        let elapsedSeconds = max(Int(date.timeIntervalSince(session.startedAt)), 0)
        return max(baseActualSeconds, session.baseActualSeconds + elapsedSeconds)
    }

    func liveActualMinutes(goalID: UUID, taskID: UUID, baseActualSeconds: Int, at date: Date = .now) -> Int {
        DurationDisplay.minutes(for: liveActualSeconds(goalID: goalID, taskID: taskID, baseActualSeconds: baseActualSeconds, at: date))
    }

    // MARK: - Commands

    /// Returns the elapsed seconds for the previous session if one was active.
    func start(
        goalID: UUID,
        taskID: UUID,
        baseActualSeconds: Int,
        now: Date = .now,
        useMonotonicClock: Bool = true
    ) -> (settledGoalID: UUID, settledTaskID: UUID, settledSeconds: Int)? {
        var settled: (UUID, UUID, Int)?
        if let existing = activeSession {
            if existing.matches(goalID: goalID, taskID: taskID) { return nil }
            let elapsedSeconds = elapsedSinceStart(of: existing, useMonotonicClock: useMonotonicClock, now: now)
            settled = (existing.goalID, existing.taskID, elapsedSeconds)
        }
        activeSession = TaskTimerSession(
            goalID: goalID,
            taskID: taskID,
            startedAt: now,
            baseActualSeconds: baseActualSeconds,
            lastCheckpointAt: now
        )
        startedInstant = useMonotonicClock ? clock.now : nil
        if let settled {
            return (settled.0, settled.1, settled.2)
        }
        return nil
    }

    /// Pauses the timer and returns the cleared session with elapsed seconds,
    /// or nil if not running.
    func pause(goalID: UUID, taskID: UUID, now: Date = .now, useMonotonicClock: Bool = true) -> (session: TaskTimerSession, elapsedSeconds: Int)? {
        guard let session = activeSession, session.matches(goalID: goalID, taskID: taskID) else { return nil }
        let elapsedSeconds = elapsedSinceStart(of: session, useMonotonicClock: useMonotonicClock, now: now)
        activeSession = nil
        startedInstant = nil
        return (session, elapsedSeconds)
    }

    /// Checkpoints without stopping. Returns (previousSession, newSession) for persistence.
    func checkpoint(at date: Date = .now) -> (previous: TaskTimerSession, updated: TaskTimerSession)? {
        guard var session = activeSession else { return nil }
        let previous = session
        let elapsedSeconds = elapsedSinceStart(of: session, useMonotonicClock: true, now: date)
        let checkpointSeconds = session.baseActualSeconds + elapsedSeconds
        session.baseActualSeconds = checkpointSeconds
        session.startedAt = date
        session.lastCheckpointAt = date
        activeSession = session
        startedInstant = clock.now
        return (previous, session)
    }

    /// Resolves an interrupted session detected at startup.
    func setRecovery(_ recovery: InterruptedTaskTimerRecovery?) {
        pendingRecovery = recovery
    }

    func resolveRecovery(includeElapsedTime: Bool) -> (session: TaskTimerSession, elapsedSeconds: Int)? {
        guard let recovery = pendingRecovery else { return nil }
        pendingRecovery = nil
        if includeElapsedTime {
            activeSession = recovery.session
            return (recovery.session, recovery.elapsedSeconds)
        } else {
            activeSession = nil
            startedInstant = nil
            return nil
        }
    }

    /// Restores a persisted session (e.g., after crash recovery).
    ///
    /// P0-4 Fix: Rebase the session on restore to ensure UI and monotonic
    /// calculations are consistent. The offline elapsed time is added to
    /// `baseActualSeconds` and `startedAt` is reset to now.
    func restore(session: TaskTimerSession?, now: Date = .now) {
        guard var session else {
            activeSession = nil
            startedInstant = nil
            return
        }
        // Calculate offline elapsed time and add to base
        let offlineElapsed = max(Int(now.timeIntervalSince(session.startedAt)), 0)
        session.baseActualSeconds += offlineElapsed
        session.startedAt = now
        session.lastCheckpointAt = now
        activeSession = session
        startedInstant = clock.now
    }

    func clear() {
        activeSession = nil
        startedInstant = nil
    }

    // MARK: - Private

    private func elapsedSinceStart(
        of session: TaskTimerSession,
        useMonotonicClock: Bool,
        now: Date
    ) -> Int {
        if useMonotonicClock, let startedInstant {
            return max(Int(startedInstant.duration(to: clock.now).components.seconds), 0)
        }
        return max(Int(now.timeIntervalSince(session.startedAt)), 0)
    }
}
