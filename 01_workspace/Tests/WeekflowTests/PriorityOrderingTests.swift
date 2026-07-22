import Foundation
import Testing
@testable import Weekflow

@MainActor
@Test func changingTaskToUrgentMovesItToTheAbsoluteTop() throws {
    let (store, goal, date) = makePriorityOrderingStore()
    let target = try #require(goal.tasks.first(where: { $0.title == "待提升" }))

    store.setTaskPriority(
        goalID: goal.id,
        taskID: target.id,
        priority: .must,
        on: date
    )

    #expect(store.tasks(on: date).map(\.task.title) == [
        "待提升", "已有紧急", "已有优先", "普通任务", "低优先级"
    ])
}

@MainActor
@Test func changingTaskToPriorityPlacesItAfterUrgentAndBeforeExistingPriority() throws {
    let (store, goal, date) = makePriorityOrderingStore()
    let target = try #require(goal.tasks.first(where: { $0.title == "待提升" }))

    store.setTaskPriority(
        goalID: goal.id,
        taskID: target.id,
        priority: .should,
        on: date
    )

    #expect(store.tasks(on: date).map(\.task.title) == [
        "已有紧急", "待提升", "已有优先", "普通任务", "低优先级"
    ])
}

@MainActor
@Test func loweringTaskPriorityKeepsItsCurrentPosition() throws {
    let (store, goal, date) = makePriorityOrderingStore()
    let target = try #require(goal.tasks.first(where: { $0.title == "已有紧急" }))
    let originalOrder = store.tasks(on: date).map(\.task.title)

    store.setTaskPriority(
        goalID: goal.id,
        taskID: target.id,
        priority: .later,
        on: date
    )

    #expect(store.tasks(on: date).map(\.task.title) == originalOrder)
    #expect(store.tasks(on: date).first?.task.priority == .later)
}

@MainActor
@Test func laterPromotionMovesOnlyThePromotedTaskAndPreservesOtherRelativeOrder() throws {
    let (store, goal, date) = makePriorityOrderingStore()
    let demoted = try #require(goal.tasks.first(where: { $0.title == "已有紧急" }))
    let promoted = try #require(goal.tasks.first(where: { $0.title == "待提升" }))

    store.setTaskPriority(goalID: goal.id, taskID: demoted.id, priority: .later, on: date)
    let orderBeforePromotion = store.tasks(on: date).map(\.task.title)

    store.setTaskPriority(goalID: goal.id, taskID: promoted.id, priority: .should, on: date)
    let orderAfterPromotion = store.tasks(on: date).map(\.task.title)

    #expect(orderAfterPromotion.first == "待提升")
    #expect(orderAfterPromotion.filter { $0 != "待提升" } == orderBeforePromotion.filter { $0 != "待提升" })
}

@MainActor
@Test func sortingByStartTimeKeepsUnscheduledTasksInTheirOriginalSlots() {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStartTimeOrdering-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let calendar = Calendar.current
    let date = calendar.startOfDay(for: .now)
    let time: (Int) -> Date = { hour in
        calendar.date(byAdding: .hour, value: hour, to: date) ?? date
    }
    var goal = WeeklyGoal(title: "开始时间排序", outcome: "", startDate: date, endDate: date)
    goal.tasks = [
        WeekTask(title: "晚开始", plannedDate: date, startTime: time(15), estimatedMinutes: 30, sortOrder: 0),
        WeekTask(title: "无时间 A", plannedDate: date, estimatedMinutes: 30, sortOrder: 1),
        WeekTask(title: "早开始", plannedDate: date, startTime: time(9), estimatedMinutes: 30, sortOrder: 2),
        WeekTask(title: "无时间 B", plannedDate: date, estimatedMinutes: 30, sortOrder: 3),
        WeekTask(title: "中间开始", plannedDate: date, startTime: time(12), estimatedMinutes: 30, sortOrder: 4)
    ]
    store.goals = [goal]
    store.selectedGoalID = goal.id

    store.sortTasksByStartTime(on: date)

    #expect(store.tasks(on: date).map(\.task.title) == [
        "早开始", "无时间 A", "中间开始", "无时间 B", "晚开始"
    ])
}

@MainActor
private func makePriorityOrderingStore() -> (WeekflowStore, WeeklyGoal, Date) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPriorityOrdering-\(UUID().uuidString)", isDirectory: true)
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let date = Calendar.current.startOfDay(for: .now)
    var goal = WeeklyGoal(title: "优先级排序", outcome: "", startDate: date, endDate: date)
    goal.tasks = [
        WeekTask(title: "已有紧急", plannedDate: date, estimatedMinutes: 30, priority: .must, sortOrder: 0),
        WeekTask(title: "已有优先", plannedDate: date, estimatedMinutes: 30, priority: .should, sortOrder: 1),
        WeekTask(title: "普通任务", plannedDate: date, estimatedMinutes: 30, priority: .none, sortOrder: 2),
        WeekTask(title: "低优先级", plannedDate: date, estimatedMinutes: 30, priority: .later, sortOrder: 3),
        WeekTask(title: "待提升", plannedDate: date, estimatedMinutes: 30, priority: .none, sortOrder: 4)
    ]
    store.goals = [goal]
    store.selectedGoalID = goal.id
    return (store, goal, date)
}
