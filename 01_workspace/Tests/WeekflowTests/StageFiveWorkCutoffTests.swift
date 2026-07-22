import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@Test func stageFiveCutoffRangeUsesHalfHourStepsAndFreshDefault() {
    #expect(DailyPlanningState.defaultStartMinutes == 9 * 60)
    #expect(DailyPlanningState.allowedStartMinutes.first == 0)
    #expect(DailyPlanningState.allowedStartMinutes.last == 23 * 60 + 30)
    #expect(DailyPlanningState.allowedStartMinutes.count == 48)
    #expect(zip(
        DailyPlanningState.allowedStartMinutes,
        DailyPlanningState.allowedStartMinutes.dropFirst()
    ).allSatisfy { $1 - $0 == 30 })
    #expect(DailyPlanningState.defaultCutoffMinutes == 17 * 60)
    #expect(DailyPlanningState.allowedCutoffMinutes.first == 30)
    #expect(DailyPlanningState.allowedCutoffMinutes.last == 24 * 60)
    #expect(DailyPlanningState.allowedCutoffMinutes.count == 48)
    #expect(zip(
        DailyPlanningState.allowedCutoffMinutes,
        DailyPlanningState.allowedCutoffMinutes.dropFirst()
    ).allSatisfy { $1 - $0 == 30 })
    #expect(DailyPlanningState.normalizedStartMinutes(0) == 0)
    #expect(DailyPlanningState.normalizedCutoffMinutes(0) == 30)
    #expect(DailyPlanningState.normalizedCutoffMinutes(5 * 60) == 5 * 60)
    #expect(DailyPlanningState.normalizedCutoffMinutes(18 * 60 + 22) == 18 * 60 + 30)
    #expect(DailyPlanningState.normalizedCutoffMinutes(24 * 60) == 24 * 60)
}

@Test func legacyDailyPlanningStateDecodesWithDefaultStartTime() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000111",
      "date": 0,
      "cutoffMinutes": 1020
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let state = try decoder.decode(DailyPlanningState.self, from: Data(json.utf8))
    #expect(state.startMinutes == DailyPlanningState.defaultStartMinutes)
    #expect(state.cutoffMinutes == 17 * 60)
}

@Test func workTimeBoundarySelectionsAdjustTheirCompanionWithoutRejectingTheChoice() throws {
    let folder = stageFiveTemporaryFolder("FullDayWorkRange")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageFiveCalendar()
    let date = stageFiveSunday(calendar: calendar)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: date, calendar: calendar)
    )

    #expect(store.setDailyPlanningStart(minutes: 23 * 60 + 30, on: date) == 23 * 60 + 30)
    #expect(store.dailyPlanningCutoffMinutes(on: date) == 24 * 60)
    #expect(store.setDailyPlanningCutoff(minutes: 30, on: date) == 30)
    #expect(store.dailyPlanningStartMinutes(on: date) == 0)
}

@Test func stageFiveCutoffEventIsCreatedOnceThenUpdatedInPlace() throws {
    let folder = stageFiveTemporaryFolder("Upsert")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageFiveCalendar()
    let sunday = stageFiveSunday(calendar: calendar)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )

    #expect(store.dailyPlanningCutoffMinutes(on: tomorrow) == 17 * 60)
    #expect(store.dailyPlanningCutoffEvent(on: tomorrow) == nil)

    let firstSelection = store.setDailyPlanningCutoff(minutes: 18 * 60 + 30, on: tomorrow)
    let firstID = store.addDailyPlanningCutoffToCalendar(on: tomorrow)
    let firstEvent = try #require(store.dailyPlanningCutoffEvent(on: tomorrow))
    #expect(firstSelection == 18 * 60 + 30)
    #expect(firstEvent.id == firstID)
    #expect(calendar.component(.hour, from: firstEvent.startDate) == 18)
    #expect(calendar.component(.minute, from: firstEvent.startDate) == 30)
    #expect(store.events(on: tomorrow).filter { $0.sourceKey != nil }.count == 1)

    _ = store.setDailyPlanningCutoff(minutes: 19 * 60 + 30, on: tomorrow)
    let secondID = store.addDailyPlanningCutoffToCalendar(on: tomorrow)
    let updatedEvent = try #require(store.dailyPlanningCutoffEvent(on: tomorrow))
    #expect(secondID == firstID)
    #expect(updatedEvent.id == firstID)
    #expect(calendar.component(.hour, from: updatedEvent.startDate) == 19)
    #expect(calendar.component(.minute, from: updatedEvent.startDate) == 30)
    #expect(store.calendarEvents.filter { $0.sourceKey == updatedEvent.sourceKey }.count == 1)
    #expect(store.dailyPlanningStates.count == 1)
}

@Test func stageFiveCutoffStateAndCalendarMarkerPersistTogether() throws {
    let folder = stageFiveTemporaryFolder("Persistence")
    let suiteName = "WeekflowStageFivePreferences-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    defer {
        try? FileManager.default.removeItem(at: folder)
        preferences.removePersistentDomain(forName: suiteName)
    }
    let calendar = stageFiveCalendar()
    let targetDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
    let storage = LocalStorage(baseDirectory: folder)
    var store: WeekflowStore? = WeekflowStore(storage: storage, legacyPreferences: preferences)

    _ = store?.setDailyPlanningCutoff(minutes: 20 * 60, on: targetDate)
    let eventID = try #require(store?.addDailyPlanningCutoffToCalendar(on: targetDate))
    store = nil

    let reloaded = WeekflowStore(storage: storage, legacyPreferences: preferences)
    #expect(reloaded.dailyPlanningCutoffMinutes(on: targetDate) == 20 * 60)
    #expect(reloaded.dailyPlanningCutoffEvent(on: targetDate)?.id == eventID)
    #expect(reloaded.events(on: targetDate).contains { $0.id == eventID })
}

@Test func stageFiveLegacyCalendarEventDecodesWithoutSourceKey() throws {
    let event = CalendarEvent(title: "旧日历事件", startDate: .now, durationMinutes: 45)
    let encoded = try JSONEncoder.weekflow.encode(event)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "sourceKey")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder.weekflow.decode(CalendarEvent.self, from: legacyData)
    #expect(decoded.title == event.title)
    #expect(decoded.sourceKey == nil)
}

@MainActor
@Test func stageFiveWorkCutoffControlsAndCalendarMarkerRenderAtAcceptedSizes() throws {
    let folder = stageFiveTemporaryFolder("Render")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = stageFiveCalendar()
    let sunday = stageFiveSunday(calendar: calendar)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: sunday))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: sunday, calendar: calendar)
    )
    _ = store.setDailyPlanningCutoff(minutes: 17 * 60, on: tomorrow)
    _ = store.addDailyPlanningCutoffToCalendar(on: tomorrow)

    #expect(WeekflowLayout.workCutoffControlHeight == 34)
    #expect(WeekflowLayout.workCutoffPopoverWidth == WeekflowLayout.taskStartTimeMenuWidth)
    #expect(WeekflowLayout.workCutoffPopoverHeight == WeekflowLayout.taskStartTimeMenuHeight)

    let planning = DailyPlanningView(
        store: store,
        step: .constant(0),
        showingTaskForm: .constant(false),
        plannedDate: .constant(nil),
        finish: {},
        referenceDate: sunday
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)
    try stageFiveSnapshot(planning, size: NSSize(width: 951, height: 676), name: "每日计划截止时间-阶段5")

    let picker = ScrollClockTimePopover(
        selection: calendar.date(byAdding: .hour, value: 20, to: tomorrow),
        anchorDate: tomorrow,
        minuteRange: DailyPlanningState.minimumCutoffMinutes...DailyPlanningState.maximumCutoffMinutes,
        minuteStep: DailyPlanningState.cutoffStepMinutes,
        allowsUnset: false,
        title: "选择工作截止时间",
        select: { _ in }
    )
    try stageFiveSnapshot(
        picker,
        size: NSSize(
            width: WeekflowLayout.workCutoffPopoverWidth,
            height: WeekflowLayout.workCutoffPopoverHeight
        ),
        name: "工作截止时间选择器-阶段5"
    )

    let assistant = AssistantCalendarView(store: store, activeDate: .constant(tomorrow))
        .padding(14)
        .frame(width: 300, height: 620, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    try stageFiveSnapshot(
        assistant,
        size: NSSize(width: 300, height: 620),
        name: "右侧日历截止标记-阶段5",
        scrollToBottom: true
    )
}

private func stageFiveTemporaryFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageFive\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func stageFiveCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
}

private func stageFiveSunday(calendar: Calendar) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!
}

@MainActor
private func stageFiveSnapshot<V: View>(
    _ view: V,
    size: NSSize,
    name: String,
    scrollToBottom: Bool = false
) throws {
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

    if scrollToBottom,
       let scrollView = stageFiveDescendantScrollViews(in: hostingView).max(by: {
           ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
       }),
       let documentView = scrollView.documentView {
        let maximumOffset = max(documentView.frame.height - scrollView.contentSize.height, 0)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: maximumOffset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        hostingView.layoutSubtreeIfNeeded()
    }

    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let outputFolder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw StageFiveSnapshotError.encodingFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageFiveSnapshotError.encodingFailed
    }
    try png.write(to: outputFolder.appendingPathComponent("\(name).png"), options: .atomic)
}

@MainActor
private func stageFiveDescendantScrollViews(in view: NSView) -> [NSScrollView] {
    var result = view is NSScrollView ? [view as! NSScrollView] : []
    for subview in view.subviews {
        result.append(contentsOf: stageFiveDescendantScrollViews(in: subview))
    }
    return result
}

private enum StageFiveSnapshotError: Error {
    case encodingFailed
}
