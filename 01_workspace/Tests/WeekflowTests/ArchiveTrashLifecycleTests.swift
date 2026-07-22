import Foundation
import Testing
@testable import Weekflow

@MainActor
@Test func taskArchiveAndTrashLifecycleKeepsCompletionSeparateAndRestoresToToday() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowArchiveLifecycle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let goalID = store.addGoal(title: "归档测试", outcome: "", endDate: .now)
    let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))
    let taskID = try #require(store.addTask(
        to: goalID,
        title: "手动归档任务",
        plannedDate: yesterday,
        dueDate: nil,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))

    store.archiveTask(goalID: goalID, taskID: taskID)
    let manuallyArchived = try #require(store.archivedTasks.first { $0.task.id == taskID }).task
    #expect(manuallyArchived.status == .planned)
    #expect(manuallyArchived.archivedAt != nil)

    store.deleteTask(goalID: goalID, taskID: taskID)
    #expect(!store.archivedTasks.contains { $0.task.id == taskID })
    #expect(store.deletedTasks.contains { $0.task.id == taskID })

    store.restoreDeletedTask(goalID: goalID, taskID: taskID)
    let restored = try #require(store.tasks(on: .now).first { $0.task.id == taskID }).task
    #expect(restored.status == .planned)
    #expect(restored.archivedAt == nil)
    #expect(restored.assignedDates.isEmpty)

    store.deleteTask(goalID: goalID, taskID: taskID)
    store.permanentlyDeleteTask(goalID: goalID, taskID: taskID)
    #expect(store.goals.first(where: { $0.id == goalID })?.tasks.contains(where: { $0.id == taskID }) == false)

    let completedID = try #require(store.addTask(
        to: goalID,
        title: "完成后自动归档",
        plannedDate: .now,
        dueDate: nil,
        minutes: 20,
        notes: "",
        milestoneID: nil
    ))
    store.toggleTask(goalID: goalID, taskID: completedID)
    let completed = try #require(store.archivedTasks.first { $0.task.id == completedID }).task
    #expect(completed.status == .completed)
    #expect(completed.archivedAt != nil)
    #expect(!store.tasks(on: .now).contains { $0.task.id == completedID })
}

@MainActor
@Test func weeklyGoalArchiveAndTrashLifecycleSupportsRecoveryAndPermanentDeletion() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowGoalTrashLifecycle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let goalID = store.addGoal(title: "可恢复周目标", outcome: "", endDate: .now)

    store.archiveGoal(id: goalID)
    #expect(store.archivedGoals.contains { $0.id == goalID })
    store.deleteGoal(id: goalID)
    #expect(!store.archivedGoals.contains { $0.id == goalID })
    #expect(store.deletedGoals.contains { $0.id == goalID })

    store.restoreDeletedGoal(id: goalID)
    #expect(store.activeGoals.contains { $0.id == goalID })
    store.deleteGoal(id: goalID)
    store.permanentlyDeleteGoal(id: goalID)
    #expect(!store.goals.contains { $0.id == goalID })
}

@MainActor
@Test func archiveAndTrashViewsUseCollapsibleGroupsAndCustomDeleteConfirmation() throws {
    let archiveURL = sourceRoot().appendingPathComponent("Views/ArchiveSummaryView.swift")
    let trashURL = sourceRoot().appendingPathComponent("Views/TrashSummaryView.swift")
    let archiveSource = try String(contentsOf: archiveURL, encoding: .utf8)
    let trashSource = try String(contentsOf: trashURL, encoding: .utf8)

    #expect(archiveSource.contains("ArchiveDisclosureSection"))
    #expect(archiveSource.contains("已归档的任务"))
    #expect(archiveSource.contains("ArchiveCapsuleActions"))
    #expect(archiveSource.contains("in: Capsule()"))
    #expect(trashSource.contains("requiresDestructiveConfirmation: true"))
    #expect(!trashSource.contains("TaskControlMenuAnchor"))
    #expect(archiveSource.contains("彻底删除"))
    #expect(archiveSource.contains("WindowOutsideClickMonitor("))
    #expect(archiveSource.contains("cancelDestructiveConfirmation"))
    #expect(!archiveSource.contains("color: WeekflowPalette.objective"))
    #expect(trashSource.contains("destructiveTitle: \"删除\""))
}

private func sourceRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Weekflow")
}
