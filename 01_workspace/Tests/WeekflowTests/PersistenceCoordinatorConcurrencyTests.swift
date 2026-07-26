import Foundation
import Testing

@testable import Weekflow

actor PhaseGate {
    private var arrivedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var hasArrived = false
    private var isReleased = false

    func arriveAndWait() async {
        if let continuation = arrivedContinuation {
            arrivedContinuation = nil
            continuation.resume()
        } else {
            hasArrived = true
        }
        if isReleased { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitForArrival() async {
        if hasArrived {
            hasArrived = false
            return
        }
        await withCheckedContinuation { arrivedContinuation = $0 }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
final class ConcurrencyRecorder {
    var commits: [String] = []
    var rollbacks: [String] = []
    var failures: [String] = []
}

private struct TestWriteFailure: Error {}

@MainActor
@Test func crossDomainWritesCommitInGlobalEnqueueOrder() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()

    coordinator.enqueue(
        domain: "calendarEvents",
        label: "旧日历快照",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("old-calendar") },
        rollback: {}
    )
    await gate.waitForArrival()
    coordinator.enqueue(
        domain: "dailyPlanCalendar",
        label: "新组合快照",
        operation: {},
        commit: { recorder.commits.append("new-combined") },
        rollback: {}
    )
    await gate.release()
    await coordinator.flush()

    #expect(recorder.commits == ["old-calendar", "new-combined"])
}

@MainActor
@Test func oneDomainFailureFreezesAndDropsAllLaterWrites() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { label, _ in recorder.failures.append(label) }

    coordinator.enqueue(
        domain: "goals",
        label: "失败写入",
        operation: { throw TestWriteFailure() },
        commit: { recorder.commits.append("failed") },
        rollback: { recorder.rollbacks.append("failed") }
    )
    coordinator.enqueue(
        domain: "calendarEvents",
        label: "不得执行",
        operation: {},
        commit: { recorder.commits.append("later") },
        rollback: { recorder.rollbacks.append("later") }
    )
    await coordinator.flush()

    #expect(!coordinator.persistenceEnabled)
    #expect(recorder.failures == ["失败写入"])
    #expect(recorder.rollbacks == ["failed"])
    #expect(recorder.commits.isEmpty)
}

@MainActor
@Test func sameDomainCoalescesAtTheGlobalQueueTail() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()

    coordinator.enqueue(
        domain: "goals", label: "snap1",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("snap1") },
        rollback: {}
    )
    await gate.waitForArrival()
    coordinator.enqueue(
        domain: "calendarEvents", label: "calendar",
        operation: {},
        commit: { recorder.commits.append("calendar") },
        rollback: {}
    )
    coordinator.enqueue(
        domain: "goals", label: "snap2",
        operation: {},
        commit: { recorder.commits.append("snap2") },
        rollback: {}
    )
    coordinator.enqueue(
        domain: "goals", label: "snap3",
        operation: {},
        commit: { recorder.commits.append("snap3") },
        rollback: {}
    )
    await gate.release()
    await coordinator.flush()

    #expect(recorder.commits == ["snap1", "calendar", "snap3"])
}

@MainActor
@Test func syncBarrierRaisedMidWriteSuppressesStaleCommit() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()

    coordinator.enqueue(
        domain: "goals", label: "old",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("old") },
        rollback: {}
    )
    await gate.waitForArrival()
    coordinator.beginSyncWrite()
    await gate.release()
    await coordinator.flush()
    coordinator.endSyncWrite()

    #expect(recorder.commits.isEmpty)
}

@MainActor
@Test func terminationBarrierInvalidatesClaimedAndPendingSnapshots() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()

    coordinator.enqueue(
        domain: "goals", label: "inflight",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("inflight") },
        rollback: {}
    )
    await gate.waitForArrival()
    coordinator.enqueue(
        domain: "goals", label: "queued",
        operation: {},
        commit: { recorder.commits.append("queued") },
        rollback: {}
    )

    coordinator.cancelAllPending()
    coordinator.beginSyncWrite()
    await gate.release()
    await coordinator.flush()
    coordinator.endSyncWrite()

    #expect(recorder.commits.isEmpty)
}

@MainActor
@Test func blockingDrainWaitsForInvalidatedDiskOperationWithoutMainActorDeadlock() {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    coordinator.enqueue(
        domain: "goals", label: "claimed",
        operation: {
            started.signal()
            // Swift 6.2 forbids a blocking DispatchSemaphore.wait() directly in an
            // async context. Block a background thread and suspend instead; the
            // operation stays in-flight until `release` is signalled, preserving the
            // drain-ordering behaviour under test without a MainActor deadlock.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    release.wait()
                    continuation.resume()
                }
            }
        },
        commit: { recorder.commits.append("claimed") },
        rollback: { recorder.rollbacks.append("claimed") }
    )
    #expect(started.wait(timeout: .now() + 2) == .success)
    coordinator.beginSyncWrite(invalidating: ["goals"])
    release.signal()
    #expect(coordinator.drainInvalidatedWriteBlocking(timeout: 2))
    coordinator.endSyncWrite()

    #expect(recorder.commits.isEmpty)
    #expect(recorder.rollbacks.isEmpty)
}

@MainActor
@Test func domainScopedBarrierDoesNotDiscardUnrelatedPendingWrites() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()

    coordinator.enqueue(
        domain: "goals", label: "old-goals",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("old-goals") },
        rollback: {}
    )
    await gate.waitForArrival()
    coordinator.enqueue(
        domain: "channels", label: "channels",
        operation: {},
        commit: { recorder.commits.append("channels") },
        rollback: {}
    )

    coordinator.cancelPending(for: "goals")
    coordinator.beginSyncWrite(invalidating: ["goals", "goalsTimer"])
    await gate.release()
    coordinator.endSyncWrite()
    await coordinator.flush()

    #expect(recorder.commits == ["channels"])
}

@MainActor
@Test func flushWaitsForWriteEnqueuedByCommitCallback() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()

    coordinator.enqueue(
        domain: "first", label: "first",
        operation: {},
        commit: {
            recorder.commits.append("first")
            coordinator.enqueue(
                domain: "second", label: "second",
                operation: {},
                commit: { recorder.commits.append("second") },
                rollback: {}
            )
        },
        rollback: {}
    )
    await coordinator.flush()

    #expect(recorder.commits == ["first", "second"])
}

@MainActor
@Test func writerRestartsAfterExplicitReenable() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()

    coordinator.enqueue(
        domain: "goals", label: "失败",
        operation: { throw TestWriteFailure() },
        commit: {}, rollback: {}
    )
    await coordinator.flush()
    coordinator.reenable()
    coordinator.enqueue(
        domain: "goals", label: "恢复",
        operation: {},
        commit: { recorder.commits.append("recovered") },
        rollback: {}
    )
    await coordinator.flush()

    #expect(recorder.commits == ["recovered"])
}

@MainActor
@Test func atomicDailyPlanCalendarWriteRollsBackBothEntitiesOnFailure() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    coordinator.setOnFailure { label, _ in recorder.failures.append(label) }
    coordinator.enqueue(
        domain: "dailyPlanCalendar", label: "每日计划与日历事件",
        operation: { throw TestWriteFailure() },
        commit: { recorder.commits.append("both") },
        rollback: { recorder.rollbacks.append("both") }
    )
    await coordinator.flush()

    #expect(recorder.commits.isEmpty)
    #expect(recorder.rollbacks == ["both"])
    #expect(recorder.failures == ["每日计划与日历事件"])
}

@MainActor
@Test func focusCrashRecoveryCapsOfflineTimeInsteadOfCountingAllOfIt() throws {
    let suite = "WeekflowFocusOfflineCap-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let twoHoursAgo = Date.now.addingTimeInterval(-7200)
    let session = FocusTimerSession(
        modeID: "meditation",
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
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: NoopFocusNotificationSchedulerForCoordinatorTests()
    )
    #expect(timer.remainingSeconds == 3600 - 120)
    #expect(!timer.isRunning)
}

@MainActor
@Test func duplicateIDsAreRejectedBeforePersistence() throws {
    let day = SystemBusinessCalendar.current.date(
        for: LocalDay(year: 2026, month: 7, day: 20)
    )
    let goalA = WeeklyGoal(title: "A", outcome: "a", startDate: day, endDate: day)
    var goalB = WeeklyGoal(title: "B", outcome: "b", startDate: day, endDate: day)
    goalB.id = goalA.id
    #expect(throws: PersistenceValidationError.self) {
        try PersistenceIdentityValidator.validate(goals: [goalA, goalB])
    }
}

// MARK: - P0-1: a full-snapshot sync write must supersede per-task (`task:<uuid>`) writes

@MainActor
@Test func cancelPendingByPrefixRemovesNotYetStartedSingleTaskWrites() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()
    // Block the single writer so the task: write stays pending.
    coordinator.enqueue(
        domain: "goals", label: "阻塞写",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("blocker") },
        rollback: {}
    )
    await gate.waitForArrival()
    coordinator.enqueue(
        domain: "task:ABC", label: "单任务编辑",
        operation: {},
        commit: { recorder.commits.append("task") },
        rollback: {}
    )
    // A full-snapshot sync write cancels the pending per-task edit.
    coordinator.cancelPending(matchingPrefix: "task:")
    await gate.release()
    await coordinator.flush()
    // blocker committed; the pending task: write was cancelled before running.
    #expect(recorder.commits == ["blocker"])
    #expect(recorder.rollbacks.isEmpty)
}

@MainActor
@Test func syncBarrierInvalidatesInFlightSingleTaskWriteByPrefix() async {
    let coordinator = PersistenceCoordinator()
    let recorder = ConcurrencyRecorder()
    let gate = PhaseGate()
    coordinator.enqueue(
        domain: "task:ABC", label: "单任务编辑",
        operation: { await gate.arriveAndWait() },
        commit: { recorder.commits.append("task") },
        rollback: { recorder.rollbacks.append("task") }
    )
    await gate.waitForArrival()   // the task: write is now in-flight (operating)
    // A full-snapshot sync write supersedes it via prefix invalidation.
    coordinator.cancelPending(matchingPrefix: "task:")
    coordinator.beginSyncWrite(invalidating: ["goals"], invalidatingPrefixes: ["task:"])
    await gate.release()
    await coordinator.flush()
    coordinator.endSyncWrite()
    // The in-flight task: write was invalidated → neither commit nor rollback fires.
    #expect(recorder.commits.isEmpty)
    #expect(recorder.rollbacks.isEmpty)
}

@MainActor
private final class NoopFocusNotificationSchedulerForCoordinatorTests: FocusNotificationScheduling {
    func requestPermission() {}
    func sendCompletion(modeTitle: String, minutes: Int) {}
}
