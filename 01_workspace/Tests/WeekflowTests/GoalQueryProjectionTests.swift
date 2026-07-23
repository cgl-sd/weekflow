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
