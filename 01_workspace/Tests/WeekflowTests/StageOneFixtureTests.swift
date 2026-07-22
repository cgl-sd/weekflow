import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func productionBootstrapDoesNotSeedDevelopmentTasks() throws {
    let folder = temporaryFolder(named: "ProductionBootstrap")
    defer { try? FileManager.default.removeItem(at: folder) }

    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)

    #expect(store.goals.isEmpty)
    #expect(store.calendarEvents.isEmpty)
    #expect(!store.isUsingDevelopmentFixture)
    #expect(!store.resetDevelopmentFixture())
    #expect(try storage.load() == nil)
}

@MainActor
@Test func stageOneFixtureHasRequiredSundayMondayTuesdayCountsAndCanReset() throws {
    let folder = temporaryFolder(named: "StageOneCounts")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = fixtureCalendar()
    let sunday = fixtureSunday(calendar: calendar)
    let monday = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let tuesday = try #require(calendar.date(byAdding: .day, value: 2, to: sunday))
    let storage = LocalStorage(baseDirectory: folder)
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: sunday, calendar: calendar)
    let store = WeekflowStore(storage: storage, developmentFixture: fixture)

    #expect(store.tasks(on: sunday).count == 4)
    #expect(store.tasks(on: monday).count == 10)
    #expect(store.tasks(on: tuesday).count == 12)
    #expect(store.isUsingDevelopmentFixture)

    let moved = try #require(store.tasks(on: tuesday).first)
    store.moveTask(goalID: moved.goal.id, taskID: moved.task.id, to: sunday)
    #expect(store.tasks(on: sunday).count == 5)
    #expect(store.tasks(on: tuesday).count == 11)
    #expect(store.resetDevelopmentFixture())
    #expect(store.tasks(on: sunday).count == 4)
    #expect(store.tasks(on: monday).count == 10)
    #expect(store.tasks(on: tuesday).count == 12)
    #expect(try storage.load() == nil)
}

@MainActor
@Test func stageOneFixtureKeepsTheCurrentTaskCardAcceptanceExamples() throws {
    let calendar = fixtureCalendar()
    let sunday = fixtureSunday(calendar: calendar)
    let monday = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let tuesday = try #require(calendar.date(byAdding: .day, value: 2, to: sunday))
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: sunday, calendar: calendar)
    let tasks = try #require(fixture.goals.first).tasks

    let plain = try #require(tasks.first { $0.title == "【本轮演示】普通任务 · 无开始时间" })
    #expect(plain.priority == .none)
    #expect(plain.startTime == nil)
    #expect(calendar.isDate(try #require(plain.plannedDate), inSameDayAs: monday))

    let urgent = try #require(tasks.first { $0.title == "【本轮演示】紧急任务 · 已设开始时间" })
    #expect(urgent.priority == .must)
    #expect(calendar.component(.hour, from: try #require(urgent.startTime)) == 10)
    #expect(calendar.component(.minute, from: try #require(urgent.startTime)) == 15)
    #expect(calendar.isDate(try #require(urgent.plannedDate), inSameDayAs: monday))

    let lowPriority = try #require(tasks.first { $0.title == "【本轮演示】低优先级任务" })
    #expect(lowPriority.priority == .later)
    #expect(calendar.isDate(try #require(lowPriority.plannedDate), inSameDayAs: tuesday))

    let timed = try #require(tasks.first { $0.title == "【本轮演示】实际与预计时间对照" })
    #expect(timed.actualMinutes == 28)
    #expect(timed.estimatedMinutes == 75)
    #expect(timed.status == .inProgress)
    #expect(calendar.isDate(try #require(timed.plannedDate), inSameDayAs: tuesday))
}

@MainActor
@Test func developmentFixtureIsIsolatedFromProductionStorage() throws {
    let root = temporaryFolder(named: "FixtureIsolation")
    defer { try? FileManager.default.removeItem(at: root) }

    let productionStorage = LocalStorage(baseDirectory: root)
    let productionStore = WeekflowStore(storage: productionStorage)
    productionStore.synchronousPersistence = true
    productionStore.addGoal(title: "用户正式目标", outcome: "不得被测试数据改写", endDate: .now)

    let calendar = fixtureCalendar()
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: fixtureSunday(calendar: calendar), calendar: calendar)
    let fixtureStorage = LocalStorage.developmentFixtures(rootDirectory: root)
    let fixtureStore = WeekflowStore(storage: fixtureStorage, developmentFixture: fixture)
    let fixtureTask = try #require(fixtureStore.goals.first?.tasks.first)
    fixtureStore.toggleTask(goalID: try #require(fixtureStore.goals.first?.id), taskID: fixtureTask.id)
    #expect(fixtureStore.resetDevelopmentFixture())

    let reloadedProduction = WeekflowStore(storage: productionStorage)
    #expect(productionStorage.directoryURL != fixtureStorage.directoryURL)
    #expect(reloadedProduction.goals.map(\.title) == ["用户正式目标"])
    #expect(!reloadedProduction.goals.contains { $0.title == "V4 交互联动验收" })
    #expect(try fixtureStorage.load() == nil)
}

@MainActor
@Test func stageOneBoardRendersLockedGeometryWithScrollableTuesdayData() throws {
    let folder = temporaryFolder(named: "StageOneBoard")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = fixtureCalendar()
    let sunday = fixtureSunday(calendar: calendar)
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: sunday, calendar: calendar)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: fixture
    )

    let view = HomeBoardView(
        store: store,
        visibleDayIndex: .constant(7),
        selectedChannelID: "all",
        addTaskOnDate: { _ in },
        openTask: { _ in },
        showCalendar: {},
        referenceDate: sunday
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 676))
    #expect(WeekflowLayout.dayColumnScrollbarGutter == 10)
    #expect(WeekflowLayout.taskTimerMinimumWidth >= 48)

    let timerTextWidth = ("99:59" as NSString).size(withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    ]).width + 12
    #expect(timerTextWidth <= WeekflowLayout.taskTimerMinimumWidth)
    try writeStageOneSnapshotIfRequested(image, name: "首页-阶段1测试数据")
}

@MainActor
@Test func stageOneTuesdayColumnActuallyScrollsWithoutChangingContentWidth() throws {
    let folder = temporaryFolder(named: "StageOneScrollInteraction")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = fixtureCalendar()
    let sunday = fixtureSunday(calendar: calendar)
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: sunday, calendar: calendar)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: fixture
    )
    let board = HomeBoardView(
        store: store,
        visibleDayIndex: .constant(7),
        selectedChannelID: "all",
        addTaskOnDate: { _ in },
        openTask: { _ in },
        showCalendar: {},
        referenceDate: sunday
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    let hostingView = NSHostingView(rootView: board)
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

    let scrollViews = descendantScrollViews(in: hostingView)
    let overflowing = scrollViews.filter { scrollView in
        guard let documentView = scrollView.documentView else { return false }
        return documentView.frame.height > scrollView.contentSize.height + 1
    }
    let tuesdayScrollView = try #require(overflowing.max { lhs, rhs in
        (lhs.documentView?.frame.height ?? 0) < (rhs.documentView?.frame.height ?? 0)
    })
    let documentView = try #require(tuesdayScrollView.documentView)
    let widthBefore = documentView.frame.width
    let maximumOffset = max(documentView.frame.height - tuesdayScrollView.contentSize.height, 0)

    tuesdayScrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumOffset))
    tuesdayScrollView.reflectScrolledClipView(tuesdayScrollView.contentView)
    hostingView.layoutSubtreeIfNeeded()

    #expect(maximumOffset > 0)
    #expect(tuesdayScrollView.contentView.bounds.origin.y > 0)
    #expect(documentView.frame.width == widthBefore)
    try writeStageOneViewSnapshotIfRequested(hostingView, name: "首页-周二滚动到底")
}

private func temporaryFolder(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Weekflow\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func fixtureCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func fixtureSunday(calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
}

private func writeStageOneSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageOneSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

@MainActor
private func writeStageOneViewSnapshotIfRequested(_ view: NSView, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw StageOneSnapshotError.encodingFailed
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageOneSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

@MainActor
private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView {
        result.append(scrollView)
    }
    for subview in view.subviews {
        result.append(contentsOf: descendantScrollViews(in: subview))
    }
    return result
}

private enum StageOneSnapshotError: Error {
    case encodingFailed
}
