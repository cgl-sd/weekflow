import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@Test func stageFourWeeklyPoolAssignmentStaysInPoolAndSynchronizesTomorrow() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageFourAssignment-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageFourCalendar()
    let sunday = stageFourSunday(calendar: calendar)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    let source = try #require(store.taskPool.first)

    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: tomorrow)
    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: tomorrow)

    let updated = try #require(store.goals.first(where: { $0.id == source.goal.id })?.tasks.first(where: { $0.id == source.task.id }))
    #expect(updated.plannedDate == nil)
    #expect(updated.assignedDates.count == 1)
    #expect(store.taskPool.contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: tomorrow).contains { $0.task.id == source.task.id })

    store.removeTaskAssignment(goalID: source.goal.id, taskID: source.task.id, from: tomorrow)
    #expect(store.taskPool.contains { $0.task.id == source.task.id })
    #expect(!store.tasks(on: tomorrow).contains { $0.task.id == source.task.id })
}

@Test func stageFourTomorrowManualTaskCanBeAddedAndDeletedFromSharedStore() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageFourManual-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let goal = try #require(store.activeGoals.first)
    let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
    let taskID = try #require(store.addTask(
        to: goal.id,
        title: "明日手动任务",
        plannedDate: tomorrow,
        dueDate: tomorrow,
        minutes: 45,
        notes: "",
        milestoneID: nil,
        channelID: "work"
    ))

    #expect(store.tasks(on: tomorrow).contains { $0.task.id == taskID })
    store.deleteTask(goalID: goal.id, taskID: taskID)
    #expect(!store.tasks(on: tomorrow).contains { $0.task.id == taskID })
    #expect(store.deletedTasks.contains { $0.task.id == taskID })

    store.restoreDeletedTask(goalID: goal.id, taskID: taskID)
    #expect(store.tasks(on: .now).contains { $0.task.id == taskID })
    #expect(!store.tasks(on: tomorrow).contains { $0.task.id == taskID })
    #expect(!store.deletedTasks.contains { $0.task.id == taskID })
}

@Test func stageFourLegacyTaskDecodesWithoutDailyAssignments() throws {
    let task = WeekTask(title: "旧任务", plannedDate: .now, estimatedMinutes: 30)
    let encoded = try JSONEncoder().encode(task)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "assignedDates")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(WeekTask.self, from: legacyData)
    #expect(decoded.assignedDates.isEmpty)
    #expect(decoded.title == "旧任务")
}

@MainActor
@Test func stageFourDailyPlanningFirstStepRendersPoolAndTomorrowAtLockedCanvas() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageFourRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageFourCalendar()
    let sunday = stageFourSunday(calendar: calendar)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    let view = DailyPlanningView(
        store: store,
        step: .constant(0),
        showingTaskForm: .constant(false),
        plannedDate: .constant(nil),
        finish: {},
        referenceDate: sunday
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 951, height: 676)
    let window = NSWindow(
        contentRect: hostingView.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    hostingView.layoutSubtreeIfNeeded()

    #expect(store.taskPool.count == 3)
    #expect(WeekflowLayout.primaryActionHeight == 44)
    try writeStageFourViewSnapshotIfRequested(hostingView, name: "每日计划第一步-阶段4")
}

private func stageFourCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func stageFourSunday(calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
}

@MainActor
private func writeStageFourViewSnapshotIfRequested(_ view: NSView, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw StageFourSnapshotError.encodingFailed
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageFourSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageFourSnapshotError: Error {
    case encodingFailed
}
