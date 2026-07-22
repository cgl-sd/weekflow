import AppKit
import Testing
@testable import Weekflow

@MainActor
@Test func providerDropAssignsWeeklyPoolTaskWithoutRemovingItsSource() async throws {
    let context = try makeStageThirteenContext("PoolAssignment")
    defer { try? FileManager.default.removeItem(at: context.folder) }
    let source = try #require(context.store.taskPool.first)
    let target = try #require(context.calendar.date(byAdding: .day, value: 1, to: context.referenceDate))
    let provider = NSItemProvider(
        object: TaskDragToken(goalID: source.goal.id, taskID: source.task.id).value as NSString
    )

    let handled = await performTaskDrop(provider) { token in
        context.store.relocateTask(
            goalID: token.goalID,
            taskID: token.taskID,
            from: token.sourceDate,
            to: target
        )
    }

    #expect(handled)
    #expect(context.store.tasks(on: target).contains { $0.task.id == source.task.id })
    #expect(context.store.taskPool.contains { $0.task.id == source.task.id })
}

@MainActor
@Test func providerDropMovesOnlyTheOriginatingDailyAssignment() async throws {
    let context = try makeStageThirteenContext("MoveAssignment")
    defer { try? FileManager.default.removeItem(at: context.folder) }
    let source = try #require(context.store.taskPool.first)
    let monday = try #require(context.calendar.date(byAdding: .day, value: 1, to: context.referenceDate))
    let tuesday = try #require(context.calendar.date(byAdding: .day, value: 2, to: context.referenceDate))
    let friday = try #require(context.calendar.date(byAdding: .day, value: 5, to: context.referenceDate))
    context.store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: monday)
    context.store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: tuesday)
    let provider = NSItemProvider(
        object: TaskDragToken(
            goalID: source.goal.id,
            taskID: source.task.id,
            sourceDate: monday
        ).value as NSString
    )

    let handled = await performTaskDrop(provider) { token in
        context.store.relocateTask(
            goalID: token.goalID,
            taskID: token.taskID,
            from: token.sourceDate,
            to: friday
        )
    }

    #expect(handled)
    #expect(!context.store.tasks(on: monday).contains { $0.task.id == source.task.id })
    #expect(context.store.tasks(on: tuesday).contains { $0.task.id == source.task.id })
    #expect(context.store.tasks(on: friday).contains { $0.task.id == source.task.id })
    #expect(context.store.taskPool.contains { $0.task.id == source.task.id })
}

@MainActor
@Test func providerDropStillAcceptsLegacyTokensWithoutSourceDate() async throws {
    let context = try makeStageThirteenContext("LegacyToken")
    defer { try? FileManager.default.removeItem(at: context.folder) }
    let source = try #require(context.store.taskPool.first)
    let target = try #require(context.calendar.date(byAdding: .day, value: 3, to: context.referenceDate))
    let legacyValue = "weekflow-task|\(source.goal.id.uuidString)|\(source.task.id.uuidString)"
    let provider = NSItemProvider(object: legacyValue as NSString)

    let handled = await performTaskDrop(provider) { token in
        #expect(token.sourceDate == nil)
        context.store.relocateTask(
            goalID: token.goalID,
            taskID: token.taskID,
            from: token.sourceDate,
            to: target
        )
    }

    #expect(handled)
    #expect(context.store.tasks(on: target).contains { $0.task.id == source.task.id })
    #expect(context.store.taskPool.contains { $0.task.id == source.task.id })
}

@MainActor
@Test func unsupportedDropProviderIsRejectedSynchronously() {
    var performed = false
    let handled = TaskDropCoordinator.handle(providers: [NSItemProvider()]) { _ in
        performed = true
    }

    #expect(!handled)
    #expect(!performed)
}

@MainActor
private func performTaskDrop(
    _ provider: NSItemProvider,
    action: @escaping @MainActor (TaskDragToken) -> Void
) async -> Bool {
    await withCheckedContinuation { continuation in
        let accepted = TaskDropCoordinator.handle(providers: [provider]) { token in
            action(token)
            continuation.resume(returning: true)
        }
        if !accepted {
            continuation.resume(returning: false)
        }
    }
}

@MainActor
private func makeStageThirteenContext(_ suffix: String) throws -> StageThirteenContext {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageThirteen-\(suffix)-\(UUID().uuidString)", isDirectory: true)
    let calendar = Calendar.current
    let referenceDate = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 12))
    )
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: referenceDate, calendar: calendar)
    )
    return StageThirteenContext(
        folder: folder,
        calendar: calendar,
        referenceDate: calendar.startOfDay(for: referenceDate),
        store: store
    )
}

private struct StageThirteenContext {
    let folder: URL
    let calendar: Calendar
    let referenceDate: Date
    let store: WeekflowStore
}
