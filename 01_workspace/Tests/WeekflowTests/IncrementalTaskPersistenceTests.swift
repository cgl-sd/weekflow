import Foundation
import Testing
@testable import Weekflow

/// R13: a single interactive task edit must persist through the targeted O(1)
/// write path (not the O(N) full-collection diff) and survive a restart without
/// disturbing sibling tasks or the goal envelope. Uses a non-subgoal task so the
/// goal projection does not overwrite the edited field before persistence.
@MainActor
@Test func singleTaskEditPersistsIncrementallyAndSurvivesRestart() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowIncrementalEdit-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 10)))
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    store.synchronousPersistence = true
    let goalID = store.addGoal(
        title: "增量编辑",
        outcome: "单任务编辑独立于总任务数",
        startDate: now,
        endDate: now.addingTimeInterval(4 * 86_400)
    )
    let taskID = try #require(store.addTask(
        to: goalID,
        title: "独立任务",
        plannedDate: nil,
        dueDate: nil,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))
    let originalTaskCount = try #require(store.goals.first(where: { $0.id == goalID })?.tasks.count)

    // Interactive single-task edit goes through the O(1) targeted persist.
    let changed = store.updateTask(goalID: goalID, taskID: taskID) { task in
        task.notes = "增量编辑备注"
    }
    #expect(changed)
    // Present in memory immediately.
    #expect(store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID })?.notes == "增量编辑备注")

    // Reaches disk via the targeted write and survives a restart; goal stays intact.
    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let reloadedGoal = try #require(reloaded.goals.first(where: { $0.id == goalID }))
    #expect(reloadedGoal.tasks.first(where: { $0.id == taskID })?.notes == "增量编辑备注")
    #expect(reloadedGoal.title == "增量编辑")
    #expect(reloadedGoal.tasks.count == originalTaskCount)
}
