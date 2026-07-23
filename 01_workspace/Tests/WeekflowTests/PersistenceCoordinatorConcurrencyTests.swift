import Foundation
import Testing
@testable import Weekflow

// MARK: - Deterministic concurrency scaffolding
//
// Section 五 of the review requires concurrency tests that do NOT rely on random
// sleeps. `PhaseGate` gives exact control over an async operation: the operation
// announces arrival (then suspends), the test observes arrival and releases it in
// a chosen order. This makes completion order fully deterministic.

/// Two-phase gate: operation side calls `arriveAndWait()` (announce + suspend);
/// test side calls `waitForArrival()` then `release()`.
actor PhaseGate {
    private var arrivedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var hasArrived = false
    private var isReleased = false

    func arriveAndWait() async {
        if let c = arrivedContinuation { arrivedContinuation = nil; c.resume() }
        else { hasArrived = true }
        if isReleased { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitForArrival() async {
        if hasArrived { hasArrived = false; return }
        await withCheckedContinuation { arrivedContinuation = $0 }
    }

    func release() {
        if let c = releaseContinuation { releaseContinuation = nil; c.resume() }
        else { isReleased = true }
    }
}

/// MainActor-isolated recorder so commit/rollback/failure closures (all
/// `@MainActor`) can record without data races.
@MainActor
final class ConcurrencyRecorder {
    var commits: [String] = []
    var rollbacks: [String] = []
    var failures: [String] = []
}

private struct TestWriteFailure: Error {}

// MARK: - Test 1: per-domain revisions commit independently

@MainActor
@Test func perDomainRevisionsCommitIndependentlyRegardlessOfCompletionOrder() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { _, _ in }
    let channelsGate = PhaseGate()
    let calendarGate = PhaseGate()

    coordinator.enqueue(
        domain: "channels", label: "频道",
        operation: { await channelsGate.arriveAndWait() },
        commit: { recorder.commits.append("channels") },
        rollback: { recorder.rollbacks.append("channels") }
    )
    coordinator.enqueue(
        domain: "calendarEvents", label: "日历",
        operation: { await calendarGate.arriveAndWait() },
        commit: { recorder.commits.append("calendarEvents") },
        rollback: { recorder.rollbacks.append("calendarEvents") }
    )

    await calendarGate.waitForArrival()
    await channelsGate.waitForArrival()
    // Force calendar to complete FIRST. Under the old shared-global-revision bug,
    // this would advance the global committed revision and suppress channels.
    await calendarGate.release()
    await channelsGate.release()
    await coordinator.flush()

    // Both domains must commit independently (P0-1 fix).
    #expect(recorder.commits.contains("calendarEvents"))
    #expect(recorder.commits.contains("channels"))
    #expect(recorder.rollbacks.isEmpty)
}

// MARK: - Test 2: another domain's commit must not silence this domain's failure

@MainActor
@Test func crossDomainCommitDoesNotSuppressAnotherDomainsFailure() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { label, _ in recorder.failures.append(label) }
    let channelsGate = PhaseGate()
    let calendarGate = PhaseGate()

    // channels will FAIL after calendar commits.
    coordinator.enqueue(
        domain: "channels", label: "频道",
        operation: { await channelsGate.arriveAndWait(); throw TestWriteFailure() },
        commit: { recorder.commits.append("channels") },
        rollback: { recorder.rollbacks.append("channels") }
    )
    coordinator.enqueue(
        domain: "calendarEvents", label: "日历",
        operation: { await calendarGate.arriveAndWait() },
        commit: { recorder.commits.append("calendarEvents") },
        rollback: { recorder.rollbacks.append("calendarEvents") }
    )

    await calendarGate.waitForArrival()
    await channelsGate.waitForArrival()
    await calendarGate.release()   // calendar commits first (advances only its own domain)
    await channelsGate.release()   // channels now fails
    await coordinator.flush()

    // channels' failure must be reported, not suppressed by calendar's commit.
    #expect(recorder.failures.contains("频道"))
    #expect(recorder.rollbacks.contains("channels"))
    #expect(coordinator.persistenceEnabled == false)
    #expect(recorder.commits.contains("calendarEvents"))
}

// MARK: - Test 3: same-domain writes coalesce; only the latest becomes baseline

@MainActor
@Test func sameDomainCoalescesToTheLatestSnapshotBaseline() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { _, _ in }
    let gate = PhaseGate()

    // First write is held in-flight so the 2nd and 3rd coalesce behind it.
    coordinator.enqueue(
        domain: "goals", label: "snap1",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("snap1") },
        rollback: { recorder.rollbacks.append("snap1") }
    )
    await gate.waitForArrival()
    coordinator.enqueue(
        domain: "goals", label: "snap2",
        operation: {},
        commit: { recorder.commits.append("snap2") },
        rollback: { recorder.rollbacks.append("snap2") }
    )
    coordinator.enqueue(
        domain: "goals", label: "snap3",
        operation: {},
        commit: { recorder.commits.append("snap3") },
        rollback: { recorder.rollbacks.append("snap3") }
    )
    await gate.release()
    await coordinator.flush()

    // snap2 was coalesced away; the final baseline must be the latest (snap3).
    #expect(!recorder.commits.contains("snap2"))
    #expect(recorder.commits.last == "snap3")
}

// MARK: - Test 4: sync barrier raised mid-write skips the stale commit

@MainActor
@Test func syncBarrierRaisedMidWriteSkipsStaleCommit() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { _, _ in }
    let gate = PhaseGate()

    coordinator.enqueue(
        domain: "goals", label: "g",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("g") },
        rollback: { recorder.rollbacks.append("g") }
    )
    // The operation is now suspended AFTER the barrier pre-check passed.
    await gate.waitForArrival()
    coordinator.beginSyncWrite()   // raise the barrier while the write is in flight
    await gate.release()
    await coordinator.flush()
    coordinator.endSyncWrite()

    // The stale commit must be suppressed by the barrier's post-operation check.
    #expect(recorder.commits.isEmpty)
    #expect(recorder.rollbacks.isEmpty)
}

// MARK: - Test 5: termination barrier prevents a stale async snapshot from committing

@MainActor
@Test func terminationBarrierPreventsStaleAsyncSnapshotFromCommitting() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { _, _ in }
    let gate = PhaseGate()

    // In-flight goal write.
    coordinator.enqueue(
        domain: "goals", label: "inflight",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("inflight") },
        rollback: { recorder.rollbacks.append("inflight") }
    )
    await gate.waitForArrival()
    // A second same-domain write queued behind it (not yet executing).
    coordinator.enqueue(
        domain: "goals", label: "queued",
        operation: {},
        commit: { recorder.commits.append("queued") },
        rollback: { recorder.rollbacks.append("queued") }
    )

    // Mirror persistForTermination: cancel pending + raise barrier, then the
    // authoritative synchronous snapshot would be written here.
    coordinator.cancelAllPending()
    coordinator.beginSyncWrite()
    await gate.release()
    coordinator.endSyncWrite()
    await coordinator.flush()

    // Neither stale async write may commit after the termination snapshot.
    #expect(!recorder.commits.contains("inflight"))
    #expect(!recorder.commits.contains("queued"))
}

// MARK: - Test 6: atomic plan+calendar write rolls back both on failure

@MainActor
@Test func atomicDailyPlanCalendarWriteRollsBackBothEntitiesOnFailure() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { label, _ in recorder.failures.append(label) }

    // persistDailyPlanAndCalendarEvents enqueues ONE operation + ONE rollback on
    // the dedicated "dailyPlanCalendar" domain. A failure must trigger the single
    // rollback that restores BOTH entities — never a half-committed state.
    coordinator.enqueue(
        domain: "dailyPlanCalendar", label: "每日计划与日历事件",
        operation: { throw TestWriteFailure() },   // plan "written", calendar fails
        commit: { recorder.commits.append("both") },
        rollback: { recorder.rollbacks.append("both") }
    )
    await coordinator.flush()

    #expect(recorder.commits.isEmpty)
    #expect(recorder.rollbacks == ["both"])
    #expect(recorder.failures.contains("每日计划与日历事件"))
    #expect(coordinator.persistenceEnabled == false)
}

// MARK: - Test 7: focus crash recovery caps offline time

@MainActor
@Test func focusCrashRecoveryCapsOfflineTimeInsteadOfCountingAllOfIt() throws {
    let suite = "WeekflowFocusOfflineCap-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    // Snapshot persisted 2 hours ago while actively running.
    let twoHoursAgo = Date.now.addingTimeInterval(-7200)
    let session = FocusTimerSession(
        mode: .meditation,
        totalSeconds: 3600,
        remainingSeconds: 3600,
        unloggedSeconds: 0,
        hasStarted: true,
        isRunning: true,
        linkedTask: nil,
        linkedTaskTitle: nil,
        lastCheckpointAt: twoHoursAgo
    )
    defaults.set(try JSONEncoder().encode(session), forKey: "weekflow.focus.activeSession.v1")

    let timer = FocusTimerService(defaults: defaults, notificationScheduler: NoopFocusNotificationSchedulerForCoordinatorTests())

    // Offline is ~7200s but recovery must cap at 120s (same as runtime reconcile).
    #expect(timer.remainingSeconds == 3600 - 120)
    #expect(!timer.isRunning)
}

// MARK: - Test 8: duplicate IDs must not trap

@MainActor
@Test func duplicateIDsDoNotTrapInLookupOrDifference() {
    // Direct guarantee of the keepingFirst helper (Phase 2-2 fix).
    let pairs = [("a", 1), ("b", 2), ("a", 3), ("a", 4)]
    let dict = Dictionary(keepingFirst: pairs)
    #expect(dict["a"] == 1)   // keeps FIRST deterministically, never traps
    #expect(dict["b"] == 2)
    #expect(dict.count == 2)

    // Duplicate goal IDs flowing through the persistence diff must not trap.
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    var goalA = WeeklyGoal(title: "A", outcome: "a", startDate: day, endDate: day)
    var goalB = WeeklyGoal(title: "B", outcome: "b", startDate: day, endDate: day)
    goalB.id = goalA.id   // force a duplicate ID
    let changes = PersistenceGoalChangeSet.difference(before: [], after: [goalA, goalB])
    // The guarantee is that this does NOT trap: the ID-keyed lookup dictionaries
    // are built with `keepingFirst` instead of `uniqueKeysWithValues`. Both input
    // goals are still processed into upserts (a later save collapses same-ID
    // records), so the diff completes normally rather than crashing the process.
    #expect(changes.goalsToUpsert.count == 2)
    #expect(!changes.isEmpty)
}

// MARK: - Helpers

@MainActor
private final class NoopFocusNotificationSchedulerForCoordinatorTests: FocusNotificationScheduling {
    func requestPermission() {}
    func sendCompletion(mode: FocusMode, minutes: Int) {}
}
