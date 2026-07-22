import Foundation
import Testing
@testable import Weekflow

private enum InjectedPersistenceFailure: LocalizedError {
    case databaseLocked, diskFull, readOnly, interrupted
    var errorDescription: String? { String(describing: self) }
}

@MainActor
@Test func everyTransactionStepRollsBackWithoutPartialCommit() throws {
    for point in PersistenceFaultPoint.allCases {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeekflowTransaction-\(point.rawValue)-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let baseline = transactionSnapshot(title: "before", startMinutes: 8 * 60)
        try LocalStorage(baseDirectory: folder).saveApplicationSnapshot(baseline)

        let faulted = LocalStorage(baseDirectory: folder) { encountered in
            if encountered == point { throw InjectedPersistenceFailure.interrupted }
        }
        #expect(throws: InjectedPersistenceFailure.self) {
            try faulted.saveApplicationSnapshot(
                transactionSnapshot(title: "after", startMinutes: 10 * 60)
            )
        }

        let reopened = LocalStorage(baseDirectory: folder)
        let actual = WeekflowPersistenceSnapshot(
            goals: try reopened.load() ?? [],
            channels: try reopened.loadChannels() ?? [],
            calendarEvents: try reopened.loadCalendarEvents() ?? [],
            dailyPlanningStates: try reopened.loadDailyPlanningStates() ?? [],
            focusRecords: try reopened.loadFocusRecords() ?? [],
            dailySummaries: try reopened.loadDailySummaries() ?? []
        )
        #expect(actual.canonicalized == baseline.canonicalized)
    }
}

@MainActor
@Test func lockedDiskFullAndReadOnlyFailuresPreserveCommittedState() throws {
    for failure in [
        InjectedPersistenceFailure.databaseLocked,
        .diskFull,
        .readOnly
    ] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeekflowStorageFailure-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let baseline = transactionSnapshot(title: "durable", startMinutes: 480)
        try LocalStorage(baseDirectory: folder).saveApplicationSnapshot(baseline)
        let faulted = LocalStorage(baseDirectory: folder) { point in
            if point == .beforeFinalSave { throw failure }
        }
        #expect(throws: InjectedPersistenceFailure.self) {
            try faulted.saveApplicationSnapshot(
                transactionSnapshot(title: "must rollback", startMinutes: 600)
            )
        }
        #expect(try LocalStorage(baseDirectory: folder).load()?.first?.title == "durable")
    }
}

@MainActor
@Test func dailyPlanAndCalendarEventRollbackTogetherInStoreMemory() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDailyAtomic-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 23))
    var store: WeekflowStore? = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    _ = store?.setDailyPlanningCutoff(minutes: 18 * 60, on: day)
    _ = store?.addDailyPlanningCutoffToCalendar(on: day)
    store = nil

    let faultedStorage = LocalStorage(baseDirectory: folder) { point in
        if point == .afterDailyPlanWrite { throw InjectedPersistenceFailure.diskFull }
    }
    let faultedStore = WeekflowStore(storage: faultedStorage)
    _ = faultedStore.setDailyPlanningCutoff(minutes: 20 * 60, on: day)
    #expect(faultedStore.persistenceIssue != nil)
    #expect(faultedStore.dailyPlanningCutoffMinutes(on: day) == 18 * 60)
    #expect(faultedStore.dailyPlanningCutoffEvent(on: day)?.startDate
        == SystemBusinessCalendar.current.date(for: LocalTime(minutesSinceMidnight: 18 * 60), on: LocalDay(year: 2026, month: 7, day: 23)))

    let reopened = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    #expect(reopened.dailyPlanningCutoffMinutes(on: day) == 18 * 60)
}

@MainActor
@Test func switchingActiveTasksRollsBackBothTimersAndTasksAsOneUnit() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTimerSwitchAtomic-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    var seed: WeekflowStore? = WeekflowStore(storage: storage)
    let goalID = seed!.addGoal(title: "原子计时", outcome: "", endDate: .now)
    let firstTaskID = try #require(seed?.goals.first(where: { $0.id == goalID })?.tasks.first?.id)
    let secondTaskID = try #require(seed?.addTask(
        to: goalID,
        title: "第二项",
        plannedDate: .now,
        dueDate: nil,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))
    let startedAt = Date.now.addingTimeInterval(-10)
    seed?.startTaskTimer(goalID: goalID, taskID: firstTaskID, now: startedAt)
    seed = nil

    let faulted = LocalStorage(baseDirectory: folder) { point in
        if point == .afterTaskWrite { throw InjectedPersistenceFailure.diskFull }
    }
    let store = WeekflowStore(storage: faulted)
    store.startTaskTimer(goalID: goalID, taskID: secondTaskID, now: startedAt.addingTimeInterval(10))

    #expect(store.persistenceIssue != nil)
    #expect(store.activeTaskTimer?.taskID == firstTaskID)
    #expect(store.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == firstTaskID })?.status == .inProgress)
    #expect(store.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == secondTaskID })?.status != .inProgress)

    let reopened = WeekflowStore(storage: storage)
    #expect(reopened.activeTaskTimer?.taskID == firstTaskID)
    #expect(reopened.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == secondTaskID })?.status != .inProgress)
}

private func transactionSnapshot(title: String, startMinutes: Int) -> WeekflowPersistenceSnapshot {
    let day = LocalDay(year: 2026, month: 7, day: 23)
    let date = SystemBusinessCalendar.current.date(for: day)
    let task = WeekTask(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000222")!,
        title: title,
        plannedDate: date,
        assignedDates: [date],
        estimatedMinutes: 30,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let goal = WeeklyGoal(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000111")!,
        title: title,
        outcome: "atomic",
        startDate: date,
        endDate: date,
        tasks: [task]
    )
    return WeekflowPersistenceSnapshot(
        goals: [goal],
        channels: TaskChannel.defaults,
        calendarEvents: [CalendarEvent(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000333")!,
            title: title,
            startDate: SystemBusinessCalendar.current.date(
                for: LocalTime(minutesSinceMidnight: 18 * 60),
                on: day
            ),
            durationMinutes: 30,
            colorName: "purple"
        )],
        dailyPlanningStates: [DailyPlanningState(
            date: date,
            startMinutes: startMinutes,
            cutoffMinutes: 18 * 60
        )]
    )
}
