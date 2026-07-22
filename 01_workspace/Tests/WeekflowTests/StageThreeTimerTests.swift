import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@Test func stageThreeTaskTimerUsesOneSharedSessionAndWritesBackActualTime() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageThreeTimer-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let initialActual = entry.task.actualMinutes
    let startedAt = Date(timeIntervalSince1970: 20_000)

    store.startTaskTimer(goalID: entry.goal.id, taskID: entry.task.id, now: startedAt)
    #expect(store.isTaskTimerRunning(goalID: entry.goal.id, taskID: entry.task.id))
    #expect(store.taskTimerStartedAt(goalID: entry.goal.id, taskID: entry.task.id) == startedAt)
    #expect(store.liveTaskActualMinutes(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        at: startedAt.addingTimeInterval(125)
    ) == initialActual + 2)

    store.synchronizeActiveTaskTimer(at: startedAt.addingTimeInterval(125))
    var updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(updated.actualMinutes == initialActual + 2)
    #expect(updated.status == .inProgress)

    let elapsed = store.pauseTaskTimer(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        now: startedAt.addingTimeInterval(185)
    )
    updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(elapsed == 4)
    #expect(updated.actualMinutes == initialActual + 4)
    #expect(updated.status == .planned)
    #expect(!store.isTaskTimerRunning(goalID: entry.goal.id, taskID: entry.task.id))
    #expect(updated.changeRecords.last?.source == .timer)
}

@Test func stageThreeCollapsingInlinePanelDoesNotOwnOrStopTimerSession() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageThreeDismiss-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let startedAt = Date(timeIntervalSince1970: 30_000)

    store.toggleTaskTimer(goalID: entry.goal.id, taskID: entry.task.id, now: startedAt)
    // Inline expansion is view-local; the session remains in the Store.
    #expect(store.activeTaskTimer != nil)
    #expect(store.liveTaskActualMinutes(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        at: startedAt.addingTimeInterval(61)
    ) == entry.task.actualMinutes + 1)
}

@MainActor
@Test func taskCardEstimatedDurationUsesQuarterHoursAndStopsAtFourHours() {
    let choices = ScrollDurationPopover.choices(
        range: 15...240,
        step: 15,
        allowsZero: false,
        including: 60
    )

    #expect(choices.first == 15)
    #expect(choices.last == 240)
    #expect(choices.count == 16)
    #expect(!choices.contains(0))
    #expect(!choices.contains(255))
}

@Test func stageThreeStartingAnotherTaskPausesThePreviousSharedSession() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageThreeSwitch-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entries = store.todayTasks
    let first = try #require(entries.first)
    let second = try #require(entries.dropFirst().first)
    let startedAt = Date(timeIntervalSince1970: 40_000)

    store.startTaskTimer(goalID: first.goal.id, taskID: first.task.id, now: startedAt)
    store.startTaskTimer(
        goalID: second.goal.id,
        taskID: second.task.id,
        now: startedAt.addingTimeInterval(75)
    )

    #expect(!store.isTaskTimerRunning(goalID: first.goal.id, taskID: first.task.id))
    #expect(store.isTaskTimerRunning(goalID: second.goal.id, taskID: second.task.id))
    let updatedFirst = try #require(store.goals.first(where: { $0.id == first.goal.id })?.tasks.first(where: { $0.id == first.task.id }))
    #expect(updatedFirst.actualMinutes == first.task.actualMinutes + 2)
    #expect(updatedFirst.status == .planned)
}

@MainActor
@Test func stageThreeTimerInlinePanelRendersAsCompactSingleControlSurface() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageThreeRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let view = TaskTimerInlinePanel(
        store: store,
        goalID: entry.goal.id,
        taskID: entry.task.id,
        estimatedMinutes: entry.task.estimatedMinutes
    )
    .frame(width: 210)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 210, height: WeekflowLayout.taskTimerInlinePanelHeight))
    #expect(WeekflowLayout.taskTimerInlinePanelHeight == 44)
    #expect(WeekflowLayout.taskTimerControlSize == WeekflowLayout.taskCardIconHitTarget)
    #expect(WeekflowLayout.taskCardMinimumHeight == 84)
    try writeStageThreeSnapshotIfRequested(image, name: "任务卡内嵌计时-阶段3")
}

private func writeStageThreeSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageThreeSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageThreeSnapshotError: Error {
    case encodingFailed
}
