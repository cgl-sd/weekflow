import Foundation
import Testing
@testable import Weekflow

@Test func legacyJSONMigratesOnceIntoNormalizedStoreAndRemainsRecoverable() throws {
    let folder = migrationTestFolder("LegacyImport")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let day = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 20)))
    var task = WeekTask(
        title: "迁移任务",
        plannedDate: day,
        assignedDates: [day, day],
        estimatedMinutes: 45,
        actualMinutes: 20,
        channelID: "work"
    )
    task.updatedAt = day
    let goal = WeeklyGoal(
        title: "迁移周目标",
        outcome: "保留所有关系",
        startDate: day,
        endDate: day.addingTimeInterval(6 * 86_400),
        tasks: [task]
    )
    let summary = DailySummary(date: day, content: "迁移回顾", updatedAt: day)
    let focus = FocusRecord(date: day, mode: .study, minutes: 30, sessionCount: 2)
    let originalGoals = try JSONEncoder.weekflow.encode([goal])
    try originalGoals.write(to: folder.appendingPathComponent("weekflow.json"))
    try JSONEncoder.weekflow.encode(TaskChannel.defaults).write(to: folder.appendingPathComponent("channels.json"))
    try JSONEncoder.weekflow.encode([focus]).write(to: folder.appendingPathComponent("focus-records.json"))
    try JSONEncoder.weekflow.encode([summary]).write(to: folder.appendingPathComponent("daily-summaries.json"))

    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)

    #expect(FileManager.default.fileExists(atPath: storage.databaseURL.path))
    #expect(try Data(contentsOf: folder.appendingPathComponent("weekflow.json")) == originalGoals)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("LegacyJSONBackup/weekflow.json").path))
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("LegacyJSONBackup/migration.txt").path))
    #expect(store.goals.count == 1)
    #expect(store.goals[0].tasks.count == 1)
    #expect(store.goals[0].tasks[0].assignedDates.count == 1)
    #expect(store.focusRecords == [focus])
    #expect(store.dailySummaries == [summary])

    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    #expect(reloaded.goals == store.goals)
    #expect(reloaded.channels == store.channels)
    #expect(reloaded.focusRecords == store.focusRecords)
    let diagnosticsResult = try storage.diagnostics()
    let diagnostics = try #require(diagnosticsResult)
    #expect(diagnostics.goalCount == 1)
    #expect(diagnostics.taskCount == 1)
    #expect(diagnostics.assignmentCount == 1)
}

@Test func automaticDistributionUndoSurvivesApplicationRestart() throws {
    let folder = migrationTestFolder("AutomaticUndo")
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10)))
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    _ = store.addGoal(
        title: "可撤销分配",
        outcome: "重启后仍可撤销",
        startDate: now,
        endDate: now.addingTimeInterval(4 * 86_400),
        subgoals: [GoalSubgoal(title: "任务一"), GoalSubgoal(title: "任务二")]
    )

    store.autoDistributeTaskPool(now: now)
    #expect(store.canUndoAutomaticDistribution)
    #expect(store.weeklyPlanningPoolEntries.allSatisfy { !$0.task.assignedDates.isEmpty })

    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    #expect(reloaded.canUndoAutomaticDistribution)
    reloaded.undoAutomaticDistribution()
    #expect(!reloaded.canUndoAutomaticDistribution)
    #expect(reloaded.weeklyPlanningPoolEntries.allSatisfy { $0.task.assignedDates.isEmpty })

    let verified = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    #expect(!verified.canUndoAutomaticDistribution)
    #expect(verified.weeklyPlanningPoolEntries.allSatisfy { $0.task.assignedDates.isEmpty })
}

@Test func manuallyMovedAutomaticAssignmentStaysManualAcrossRestart() throws {
    let folder = migrationTestFolder("AutomaticManualDetach")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = Calendar.current
    let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10)))
    let movedDay = try #require(calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)))
    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)
    let goalID = store.addGoal(
        title: "手工调整自动分配",
        outcome: "只撤销未调整项",
        startDate: now,
        endDate: now.addingTimeInterval(4 * 86_400),
        subgoals: [GoalSubgoal(title: "保留"), GoalSubgoal(title: "撤销")]
    )
    store.autoDistributeTaskPool(now: now)
    let entries = store.weeklyPlanningPoolEntries.filter { $0.goal.id == goalID }
    let movedTask = try #require(entries.first?.task)
    let originalDay = try #require(movedTask.assignedDates.first)
    store.relocateTask(goalID: goalID, taskID: movedTask.id, from: originalDay, to: movedDay)

    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    #expect(reloaded.canUndoAutomaticDistribution)
    reloaded.undoAutomaticDistribution()
    let tasks = try #require(reloaded.goals.first(where: { $0.id == goalID })?.tasks)
    #expect(tasks.first(where: { $0.id == movedTask.id })?.isAssigned(on: movedDay) == true)
    #expect(tasks.filter { $0.id != movedTask.id }.allSatisfy { $0.assignedDates.isEmpty })
}

@Test func normalizedStoreHandlesLargeLocalHistoryWithinBoundedTimeAndSpace() throws {
    let folder = migrationTestFolder("Scale")
    defer { try? FileManager.default.removeItem(at: folder) }
    let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let tasks = (0..<500).map { index in
        WeekTask(
            title: "任务 \(index)",
            plannedDate: day.addingTimeInterval(Double(index % 7) * 86_400),
            estimatedMinutes: 30 + index % 90,
            actualMinutes: index % 45,
            description: "用于验证大量本地数据的读取与紧凑存储 \(index)",
            channelID: index.isMultiple(of: 2) ? "work" : "research",
            sourceType: .native
        )
    }
    let goal = WeeklyGoal(
        title: "大数据性能验证",
        outcome: "500 项任务",
        startDate: day,
        endDate: day.addingTimeInterval(6 * 86_400),
        tasks: tasks
    )
    let storage = LocalStorage(baseDirectory: folder)

    let writeStart = ContinuousClock.now
    try storage.save([goal])
    let writeDuration = writeStart.duration(to: .now)
    let readStart = ContinuousClock.now
    let loaded = try storage.load()
    let readDuration = readStart.duration(to: .now)

    #expect(loaded?.first?.tasks.count == 500)
    #expect(writeDuration < .seconds(5))
    #expect(readDuration < .seconds(2))
    let diagnosticsBeforeNoOpResult = try storage.diagnostics()
    let diagnosticsBeforeNoOp = try #require(diagnosticsBeforeNoOpResult)
    try storage.save([goal])
    let diagnosticsAfterNoOpResult = try storage.diagnostics()
    let diagnosticsAfterNoOp = try #require(diagnosticsAfterNoOpResult)
    #expect(diagnosticsAfterNoOp.transactionCount == diagnosticsBeforeNoOp.transactionCount)

    var editedGoal = try #require(loaded?.first)
    editedGoal.tasks[0].title = "只更新这一项"
    let incrementalStart = ContinuousClock.now
    try storage.save([editedGoal])
    let incrementalDuration = incrementalStart.duration(to: .now)
    let diagnosticsAfterIncrementalResult = try storage.diagnostics()
    let diagnosticsAfterIncremental = try #require(diagnosticsAfterIncrementalResult)
    #expect(incrementalDuration < .seconds(2))
    #expect(diagnosticsAfterIncremental.transactionCount == diagnosticsAfterNoOp.transactionCount + 1)
    #expect(diagnosticsAfterIncremental.operationCount == diagnosticsAfterNoOp.operationCount + 1)

    let databaseBytes = try FileManager.default.contentsOfDirectory(
        at: storage.dataDirectoryURL,
        includingPropertiesForKeys: [.fileSizeKey]
    )
    .filter { $0.lastPathComponent.hasPrefix("Weekflow.store") }
    .reduce(0) { partial, url in
        partial + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    #expect(databaseBytes < 15 * 1_024 * 1_024)
    #expect(diagnosticsAfterNoOp.assignmentCount == 500)
}

private func migrationTestFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDataArchitecture-\(name)-\(UUID().uuidString)", isDirectory: true)
}
