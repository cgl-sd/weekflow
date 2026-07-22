import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func stageSixWeeklyPoolAssignmentMovesBetweenTomorrowAndDayAfter() throws {
    let folder = stageSixTemporaryFolder("WeeklyMove")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageSixCalendar()
    let sunday = stageSixSunday(calendar: calendar)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let dayAfterTomorrow = try #require(calendar.date(byAdding: .day, value: 2, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    let source = try #require(store.taskPool.first)

    store.relocateTask(goalID: source.goal.id, taskID: source.task.id, from: nil, to: tomorrow)
    #expect(store.tasks(on: tomorrow).contains { $0.task.id == source.task.id })

    store.relocateTask(
        goalID: source.goal.id,
        taskID: source.task.id,
        from: tomorrow,
        to: dayAfterTomorrow
    )

    let updated = try #require(store.goals.first?.tasks.first { $0.id == source.task.id })
    #expect(updated.plannedDate == nil)
    #expect(updated.assignedDates.count == 1)
    #expect(!store.tasks(on: tomorrow).contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: dayAfterTomorrow).contains { $0.task.id == source.task.id })
    #expect(store.taskPool.contains { $0.task.id == source.task.id })
}

@MainActor
@Test func stageSixRegularTaskMovePreservesStartClockAndSynchronizesBothDates() throws {
    let folder = stageSixTemporaryFolder("RegularMove")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageSixCalendar()
    let sunday = stageSixSunday(calendar: calendar)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let dayAfterTomorrow = try #require(calendar.date(byAdding: .day, value: 2, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    let entry = try #require(store.tasks(on: tomorrow).first { $0.task.startTime != nil })
    let originalHour = try #require(entry.task.startTime.map { calendar.component(.hour, from: $0) })
    let originalMinute = try #require(entry.task.startTime.map { calendar.component(.minute, from: $0) })

    store.relocateTask(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        from: tomorrow,
        to: dayAfterTomorrow
    )

    let updated = try #require(store.goals.first?.tasks.first { $0.id == entry.task.id })
    let updatedStart = try #require(updated.startTime)
    #expect(!store.tasks(on: tomorrow).contains { $0.task.id == entry.task.id })
    #expect(store.tasks(on: dayAfterTomorrow).contains { $0.task.id == entry.task.id })
    #expect(calendar.isDate(updatedStart, inSameDayAs: dayAfterTomorrow))
    #expect(calendar.component(.hour, from: updatedStart) == originalHour)
    #expect(calendar.component(.minute, from: updatedStart) == originalMinute)
}

@MainActor
@Test func stageSixTomorrowAndDayAfterBothAcceptManualTasks() throws {
    let folder = stageSixTemporaryFolder("ManualAdd")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageSixCalendar()
    let sunday = stageSixSunday(calendar: calendar)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let dayAfterTomorrow = try #require(calendar.date(byAdding: .day, value: 2, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    let goal = try #require(store.activeGoals.first)
    let tomorrowTaskID = try #require(store.addTask(
        to: goal.id,
        title: "明天新增任务",
        plannedDate: tomorrow,
        dueDate: tomorrow,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))
    let dayAfterTaskID = try #require(store.addTask(
        to: goal.id,
        title: "后天新增任务",
        plannedDate: dayAfterTomorrow,
        dueDate: dayAfterTomorrow,
        minutes: 45,
        notes: "",
        milestoneID: nil
    ))

    #expect(store.tasks(on: tomorrow).contains { $0.task.id == tomorrowTaskID })
    #expect(store.tasks(on: dayAfterTomorrow).contains { $0.task.id == dayAfterTaskID })
}

@MainActor
@Test func stageSixDragTokenCarriesOptionalSourceDateAndReadsLegacyTokens() throws {
    let goalID = UUID()
    let taskID = UUID()
    let sourceDate = Date(timeIntervalSince1970: 1_783_872_000)
    let moved = try #require(TaskDragToken(token: TaskDragToken(
        goalID: goalID,
        taskID: taskID,
        sourceDate: sourceDate
    ).value))
    #expect(moved.goalID == goalID)
    #expect(moved.taskID == taskID)
    #expect(moved.sourceDate == sourceDate)

    let legacy = try #require(TaskDragToken(token: "weekflow-task|\(goalID.uuidString)|\(taskID.uuidString)"))
    #expect(legacy.sourceDate == nil)
}

@MainActor
@Test func stageSixDailyPlanningSecondStepRendersOnlyTomorrowAndDayAfter() throws {
    let folder = stageSixTemporaryFolder("Render")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageSixCalendar()
    let sunday = stageSixSunday(calendar: calendar)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    let view = DailyPlanningView(
        store: store,
        step: .constant(1),
        showingTaskForm: .constant(false),
        plannedDate: .constant(nil),
        finish: {},
        referenceDate: sunday
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)

    #expect(WeekflowLayout.primaryActionHeight == 44)
    #expect(WorkspaceToolbar.contextualDateTitle(for: .dailyPlanning, dailyPlanningStep: 0) == "今日")
    #expect(WorkspaceToolbar.contextualDateTitle(for: .dailyPlanning, dailyPlanningStep: 1) == "明天")
    #expect(WorkspaceToolbar.contextualDateTitle(for: .dailyPlanning, dailyPlanningStep: 2) == "明天")
    try stageSixSnapshot(view, size: NSSize(width: 951, height: 676), name: "每日计划第二步-阶段6")
}

private func stageSixTemporaryFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageSix\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func stageSixCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func stageSixSunday(calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
}

@MainActor
private func stageSixSnapshot<V: View>(_ view: V, size: NSSize, name: String) throws {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(origin: .zero, size: size)
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
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw StageSixSnapshotError.encodingFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageSixSnapshotError.encodingFailed
    }
    try png.write(to: outputFolder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageSixSnapshotError: Error {
    case encodingFailed
}
