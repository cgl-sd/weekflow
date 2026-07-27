import Foundation
import Testing

@testable import Weekflow

private struct InjectedPersistenceFailure: Error {}

private final class OneShotPersistenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didBlock = false
    private let arrived = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    func intercept(_ point: PersistenceFaultPoint) {
        guard point == .afterTaskWrite else { return }
        let shouldBlock = lock.withLock {
            guard !didBlock else { return false }
            didBlock = true
            return true
        }
        guard shouldBlock else { return }
        arrived.signal()
        release.wait()
    }

    func waitForArrival(timeout: TimeInterval = 2) -> Bool {
        arrived.wait(timeout: .now() + timeout) == .success
    }

    func resume() {
        release.signal()
    }
}

@Test func startupPreloadCacheIsConsumedOnlyOnce() throws {
    let goal = WeeklyGoal(
        title: "启动快照",
        outcome: "只消费一次",
        startDate: .now,
        endDate: .now
    )
    var preload = LocalStoragePreload(goals: [goal])
    preload.consumableKeys.insert(.goals)
    let cache = LocalStoragePreloadCache(preload)

    switch try cache.take(.goals, \.goals) {
    case .value(let value): #expect(value?.map(\.id) == [goal.id])
    case .unavailable: Issue.record("first preload read was unexpectedly unavailable")
    }
    switch try cache.take(.goals, \.goals) {
    case .unavailable: break
    case .value: Issue.record("preload value was returned more than once")
    }
}

@MainActor
@Test func timerWriteCommitDoesNotMarkNewerDebouncedEditAsPersisted() async throws {
    let folder = hardeningFolder("TimerSnapshotBaseline")
    defer { try? FileManager.default.removeItem(at: folder) }

    var seed: WeekflowStore? = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    seed?.synchronousPersistence = true
    let seedStore = try #require(seed)
    let goalID = seedStore.addGoal(title: "计时基线", outcome: "", endDate: .now)
    let taskID = try #require(seed?.goals.first(where: { $0.id == goalID })?.tasks.first?.id)
    seed = nil

    let gate = OneShotPersistenceGate()
    let storage = LocalStorage(baseDirectory: folder) { point in
        gate.intercept(point)
    }
    let store = WeekflowStore(storage: storage)
    let goalIndex = try #require(store.goals.firstIndex(where: { $0.id == goalID }))
    let taskIndex = try #require(store.goals[goalIndex].tasks.firstIndex(where: { $0.id == taskID }))

    store.goals[goalIndex].tasks[taskIndex].notes = "已进入写盘的快照"
    store.persistTaskAndActiveTimer(rollbackSession: nil, affectedGoalIDs: [goalID])
    #expect(gate.waitForArrival())

    // Simulate a text edit still inside its debounce window while the timer
    // transaction is in flight. It has changed memory but has not enqueued its
    // own write yet.
    store.goals[goalIndex].tasks[taskIndex].notes = "写盘期间产生的较新编辑"
    gate.resume()
    await store.persistenceCoordinator.flush()

    store.persist()
    await store.persistenceCoordinator.flush()

    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let reloadedNotes = reloaded.goals
        .first(where: { $0.id == goalID })?.tasks
        .first(where: { $0.id == taskID })?.notes
    #expect(reloadedNotes == "写盘期间产生的较新编辑")
}

@Test func taskDetailDebouncedAutosaveRequestsDurablePersistence() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: packageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/TaskDetailActions.swift"
        ),
        encoding: .utf8
    )
    let saveStart = try #require(source.range(of: "func save(_ entry:"))
    let saveEnd = try #require(source.range(
        of: "func editedTaskSnapshot(",
        range: saveStart.upperBound..<source.endIndex
    ))
    let saveSection = source[saveStart.lowerBound..<saveEnd.lowerBound]

    #expect(saveSection.contains("persistImmediately: true"))
    #expect(!saveSection.contains("persistImmediately: false"))
}

@MainActor
@Test func duplicateGoalSaveFailsBeforeChangingTheDatabase() throws {
    let folder = hardeningFolder("DuplicateGoal")
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    let original = WeeklyGoal(
        title: "原始目标",
        outcome: "数据库保持原样",
        startDate: .now,
        endDate: .now
    )
    try storage.save([original])

    var duplicate = original
    duplicate.title = "重复 ID"
    #expect(throws: PersistenceValidationError.self) {
        try storage.save([original, duplicate])
    }

    let reloaded = try #require(try storage.load())
    #expect(reloaded.count == 1)
    #expect(reloaded[0].title == "原始目标")
}

@MainActor
@Test func applicationSnapshotPersistsTimerInTheSameTransaction() throws {
    let folder = hardeningFolder("SnapshotTimer")
    defer { try? FileManager.default.removeItem(at: folder) }
    let task = WeekTask(title: "计时任务", estimatedMinutes: 30)
    let goal = WeeklyGoal(
        title: "计时目标",
        outcome: "原子退出",
        startDate: .now,
        endDate: .now,
        tasks: [task]
    )
    let session = TaskTimerSession(
        goalID: goal.id,
        taskID: task.id,
        startedAt: .now,
        baseActualSeconds: 120,
        lastCheckpointAt: .now
    )
    do {
        let storage = LocalStorage(baseDirectory: folder)
        try storage.saveApplicationSnapshot(
            WeekflowPersistenceSnapshot(
                goals: [goal],
                activeTimerSession: session
            ))
    }

    var changed = goal
    changed.title = "不得半提交"
    let failing = LocalStorage(baseDirectory: folder) { point in
        if point == .beforeFinalSave { throw InjectedPersistenceFailure() }
    }
    #expect(throws: InjectedPersistenceFailure.self) {
        try failing.saveApplicationSnapshot(
            WeekflowPersistenceSnapshot(
                goals: [changed],
                activeTimerSession: nil
            ))
    }

    let verified = LocalStorage(baseDirectory: folder)
    #expect(try verified.load()?.first?.title == "计时目标")
    #expect(try verified.loadActiveTimerSession() == session)
}

@MainActor
@Test func targetedCalendarUpsertDoesNotDeleteSiblingRecords() throws {
    let folder = hardeningFolder("TargetedCalendar")
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    var first = CalendarEvent(
        title: "一",
        startDate: .now,
        durationMinutes: 30
    )
    let second = CalendarEvent(
        title: "二",
        startDate: .now.addingTimeInterval(3600),
        durationMinutes: 30
    )
    try storage.saveCalendarEvents([first, second])
    first.title = "一（更新）"
    try storage.upsertCalendarEvent(first)

    let loaded = try #require(try storage.loadCalendarEvents())
    #expect(loaded.count == 2)
    #expect(loaded.first(where: { $0.id == first.id })?.title == "一（更新）")
    #expect(loaded.contains(where: { $0.id == second.id }))
}

@MainActor
@Test func payloadNormalizationMarkerIsDatabaseScopedAndIdempotent() throws {
    let folder = hardeningFolder("NormalizationMarker")
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    try storage.save([
        WeeklyGoal(
            title: "规范化",
            outcome: "一次完成",
            startDate: .now,
            endDate: .now
        )
    ])
    _ = try storage.normalizeAllPayloadsIfNeeded(marker: "test.normalization.v1")
    let secondPass = try storage.normalizeAllPayloadsIfNeeded(marker: "test.normalization.v1")
    #expect(secondPass == 0)
}

@MainActor
@Test func payloadNormalizationPreservesTaskSubtasks() throws {
    let folder = hardeningFolder("NormalizationSubtasks")
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    let task = WeekTask(
        title: "包含子任务",
        estimatedMinutes: 30,
        subtasks: [TaskSubtask(title: "必须保留", plannedMinutes: 10)]
    )
    try storage.save([
        WeeklyGoal(
            title: "规范化不丢数据",
            outcome: "子任务仍存在",
            startDate: .now,
            endDate: .now,
            tasks: [task]
        )
    ])

    _ = try storage.normalizeAllPayloadsIfNeeded(marker: "test.subtasks.v1")

    let reloaded = try #require(try storage.load()?.first?.tasks.first)
    #expect(reloaded.subtasks.map(\.title) == ["必须保留"])
}

@Test func frozenSchemaDescriptorsMatchSwiftDataRuntimeSchema() {
    #expect(WeekflowSchemaV1.modelStructure.count == 8)
    #expect(WeekflowSchemaV2.modelStructure.count == 9)
    #expect(
        WeekflowSchemaDescriptor.structure(for: WeekflowSchemaV1.self)
            == WeekflowSchemaV1.modelStructure)
    #expect(
        WeekflowSchemaDescriptor.structure(for: WeekflowSchemaV2.self)
            == WeekflowSchemaV2.modelStructure)
    #expect(
        WeekflowSchemaV2.modelStructure.contains {
            $0.contains("PersistedMigrationAuditRecord")
                && $0.contains("failureReason:String[optional]")
        })
}

private func hardeningFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowHardening-\(name)-\(UUID().uuidString)", isDirectory: true)
}
