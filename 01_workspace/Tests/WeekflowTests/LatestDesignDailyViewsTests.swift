import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func latestDailyPlanningFirstStepRendersThreePartsWithTomorrowCalendar() throws {
    let folder = latestDailyTemporaryFolder("Planning")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = latestDailyCalendar()
    let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12)))
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    _ = store.setDailyPlanningCutoff(minutes: 17 * 60, on: tomorrow)
    let cutoffEventID = store.addDailyPlanningCutoffToCalendar(on: tomorrow)
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

    #expect(WeekflowLayout.workCutoffPopoverWidth == WeekflowLayout.taskStartTimeMenuWidth)
    #expect(WeekflowLayout.dailyWorkspaceColumnTopInset == 18)
    #expect(WeekflowLayout.dailyWorkspaceColumnHorizontalInset == 18)
    #expect(WeekflowLayout.dailyWorkspaceHeaderHeight == 66)
    #expect(store.events(on: tomorrow).contains { $0.id == cutoffEventID })
    #expect(Calendar.current.isDate(store.activeDay, inSameDayAs: sunday))
    try latestDailySnapshot(
        view,
        size: NSSize(width: 951, height: 676),
        name: "每日计划-三部分与明日日历-最新设计"
    )
}

@MainActor
@Test func latestDailyShutdownRendersThreeEqualColumns() throws {
    let folder = latestDailyTemporaryFolder("Shutdown")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder), referenceDate: .now)
    let entries = store.todayTasks
    for (index, entry) in entries.prefix(3).enumerated() {
        var task = entry.task
        task.actualMinutes = [20, 35, 15][index]
        if index == 2 { task.status = .completed }
        store.updateTask(task, goalID: entry.goal.id)
    }
    let view = DailyShutdownView(store: store, initialPhase: 0)
        .frame(width: 951, height: 676, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)

    let columnWidth = WeekflowLayout.threeColumnWidth(
        for: 951,
        columnSpacing: WeekflowLayout.dailyWorkspaceColumnSpacing
    )
    #expect(
        columnWidth * 3 + WeekflowLayout.dailyWorkspaceColumnSpacing * 2
            == 951
    )
    #expect(store.todayTasks.filter { $0.task.status == .completed }.count >= 2)
    #expect(Set(store.todayTasks.compactMap { $0.task.actualMinutes > 0 ? $0.task.channelID : nil }).count >= 2)
    try latestDailySnapshot(
        view,
        size: NSSize(width: 951, height: 676),
        name: "每日收尾-居中饼图与双列任务-最新设计"
    )
}

private func latestDailyTemporaryFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowLatestDaily\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func latestDailyCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

@MainActor
private func latestDailySnapshot<V: View>(_ view: V, size: NSSize, name: String) throws {
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
        throw LatestDailySnapshotError.encodingFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw LatestDailySnapshotError.encodingFailed
    }
    try png.write(to: outputFolder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum LatestDailySnapshotError: Error {
    case encodingFailed
}
