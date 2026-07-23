import Foundation
import Testing

@testable import Weekflow

private struct InjectedPersistenceFailure: Error {}

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
