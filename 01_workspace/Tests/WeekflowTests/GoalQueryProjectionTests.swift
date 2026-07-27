import Foundation
import Testing
@testable import Weekflow

/// R08: the goal/task read-model rules now live in GoalService as pure functions
/// of a goal collection. The store's cached accessors delegate to them, so the
/// service output over `store.goals` must exactly match the store's read model —
/// a single, directly-testable source of query rules.
@MainActor
@Test func goalServiceProjectionsMatchStoreReadModel() throws {
    let store = WeekflowStore(developmentFixture: .stageOne(referenceDate: .now))
    let service = GoalService()
    #expect(service.activeGoals(in: store.goals).map(\.id) == store.activeGoals.map(\.id))
    #expect(service.archivedGoals(in: store.goals).map(\.id) == store.archivedGoals.map(\.id))
    #expect(service.deletedGoals(in: store.goals).map(\.id) == store.deletedGoals.map(\.id))
    #expect(service.activeTasks(in: store.goals).map(\.task.id) == store.activeTasks.map(\.task.id))
    #expect(service.taskPool(in: store.goals).map(\.task.id) == store.taskPool.map(\.task.id))
}

@MainActor
@Test func goalServiceProjectionsSeparateArchivedDeletedAndPool() {
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    var active = WeeklyGoal(title: "进行中", outcome: "o", startDate: day, endDate: day)
    active.tasks = [WeekTask(title: "未分配任务", estimatedMinutes: 10)]
    var archived = WeeklyGoal(title: "已归档", outcome: "o", startDate: day, endDate: day)
    archived.archivedAt = .now
    var deleted = WeeklyGoal(title: "已删除", outcome: "o", startDate: day, endDate: day)
    deleted.deletedAt = .now

    let service = GoalService()
    let goals = [active, archived, deleted]
    #expect(service.activeGoals(in: goals).map(\.title) == ["进行中"])
    #expect(service.archivedGoals(in: goals).map(\.title) == ["已归档"])
    #expect(service.deletedGoals(in: goals).map(\.title) == ["已删除"])
    // The lone unassigned task in the active goal lands in the pool.
    #expect(service.taskPool(in: goals).map(\.task.title) == ["未分配任务"])
}

@Test func goalServiceMakeGoalBuildsProjectedPrimaryTaskOnlyWhenNoSubgoals() {
    let service = GoalService()
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    let goal = service.makeGoal(
        title: "新目标", outcome: "结果", startDate: day, endDate: day,
        channelID: nil, subgoals: [], sortOrder: -1
    )
    #expect(goal.sortOrder == -1)
    let primary = try! #require(goal.tasks.first(where: { $0.id == goal.primaryTaskID }))
    #expect(primary.title == "新目标")
    #expect(primary.sourceType == .weeklyObjective)

    let withSubgoals = service.makeGoal(
        title: "带子目标", outcome: "o", startDate: day, endDate: day,
        channelID: nil, subgoals: [GoalSubgoal(title: "子")], sortOrder: -2
    )
    #expect(withSubgoals.primaryTaskID == nil)
}

@MainActor
@Test func indexedTaskEntryLookupAvoidsRebuildingLifecycleCollections() throws {
    let day = SystemBusinessCalendar.current.date(
        for: LocalDay(year: 2026, month: 7, day: 20)
    )
    let goals = (0..<5_000).map { index in
        var goal = WeeklyGoal(
            title: "目标 \(index)",
            outcome: "索引查询",
            startDate: day,
            endDate: day,
            tasks: [WeekTask(title: "任务 \(index)", estimatedMinutes: 10)]
        )
        if index.isMultiple(of: 3) { goal.archivedAt = .now }
        if index.isMultiple(of: 5) { goal.deletedAt = .now }
        return goal
    }
    let fixture = WeekflowDevelopmentFixture(
        identifier: "indexed-task-entry",
        referenceDate: day,
        goals: goals,
        channels: TaskChannel.defaults,
        calendarEvents: []
    )
    let store = WeekflowStore(developmentFixture: fixture)
    let targetGoal = goals[4_999]
    let targetTask = try #require(targetGoal.tasks.first)

    // Warm the goal index once, then repeated detail redraw lookups should only
    // inspect the selected goal's own tasks, irrespective of lifecycle state.
    _ = try #require(store.taskEntry(goalID: targetGoal.id, taskID: targetTask.id))
    let clock = ContinuousClock()
    let duration = clock.measure {
        for _ in 0..<20_000 {
            _ = store.taskEntry(goalID: targetGoal.id, taskID: targetTask.id)
        }
    }

    #expect(duration < .seconds(2))
    #expect(store.taskEntry(goalID: targetGoal.id, taskID: targetTask.id)?.task.title == targetTask.title)
}
