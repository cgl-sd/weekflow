import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func assistantCalendarDateOpensMonthViewAndDayTaskCards() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let contentSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/ContentView.swift"),
        encoding: .utf8
    )
    let assistantSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/AssistantPanelViews.swift"),
        encoding: .utf8
    )
    let homeSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/HomeBoardViews.swift"),
        encoding: .utf8
    )

    #expect(contentSource.contains("openCalendarDate: openCalendarDate"))
    #expect(contentSource.contains("assistantCalendarPresentation = .dayTasks"))
    #expect(contentSource.contains("workspaceView = .monthCalendar"))
    #expect(contentSource.contains("calendarAssistantReservesSpace"))
    #expect(contentSource.contains("returnToDashboard: returnToDashboard"))
    #expect(contentSource.contains("workspaceView = .board"))
    #expect(assistantSource.contains("openDayTasks(activeDate)"))
    #expect(assistantSource.contains("AssistantDayTaskListView"))
    #expect(assistantSource.contains("HomeDayColumn("))
    #expect(assistantSource.contains("AssistantTaskFilterButton"))
    #expect(assistantSource.contains("isDateHovering ? WeekflowPalette.surfaceSelected"))
    #expect(assistantSource.contains("dateSelectionHelp: \"返回首页仪表盘\""))
    #expect(!assistantSource.contains("calendar.day.timeline.left"))
    #expect(homeSource.contains("highlightsDateHeader && isDateHovering"))
}

@MainActor
@Test func workspaceViewSwitcherUsesTheSharedCustomToolbarMenuLayer() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = packageRoot
        .appendingPathComponent("Sources/Weekflow/Views/WorkspaceToolbar.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("case view"))
    #expect(source.contains("toggleMenu(.view)"))
    #expect(source.contains("[.view: $0]"))
    #expect(source.contains("WorkspaceViewMenu(selection: $workspaceView)"))
    #expect(!source.contains("showingViewMenu"))
    #expect(!source.contains(".popover(isPresented: $showingViewMenu"))
}

@MainActor
@Test func latestCalendarTimelineUsesSixToMidnightWithoutWrappingTheRange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let six = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 6)))
    let cutoff = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 17, minute: 30)))
    let beforeSix = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 5, minute: 59)))
    let beforeMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 23, minute: 59)))

    #expect(CalendarTimelineLayout.firstHour == 6)
    #expect(CalendarTimelineLayout.endHour == 24)
    #expect(Array(CalendarTimelineLayout.hourRange).first == 6)
    #expect(Array(CalendarTimelineLayout.hourRange).last == 24)
    #expect(CalendarTimelineLayout.contains(six, calendar: calendar))
    #expect(!CalendarTimelineLayout.contains(beforeSix, calendar: calendar))
    #expect(CalendarTimelineLayout.contains(beforeMidnight, calendar: calendar))
    #expect(CalendarTimelineLayout.offset(for: cutoff, hourHeight: 44, calendar: calendar) == 506)
}

@MainActor
@Test func latestCalendarCutoffRendersAsAFullWidthFence() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowLatestCalendar-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .stageOne(referenceDate: date, calendar: calendar)
    )
    _ = store.setDailyPlanningCutoff(minutes: 17 * 60 + 30, on: date)
    _ = store.addDailyPlanningCutoffToCalendar(on: date)

    let event = try #require(store.dailyPlanningCutoffEvent(on: date))
    #expect(calendar.component(.hour, from: event.startDate) == 17)
    #expect(calendar.component(.minute, from: event.startDate) == 30)

    let view = AssistantCalendarView(store: store, activeDate: .constant(date))
        .padding(14)
        .frame(width: 300, height: 620, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 300, height: 620)
    hostingView.layoutSubtreeIfNeeded()
    #expect(hostingView.fittingSize.width <= 300)
    #expect(hostingView.fittingSize.height <= 620)
}

@MainActor
@Test func taskCalendarPlacementDefaultsToPreviewAndPersistsCommitment() throws {
    let task = WeekTask(
        title: "日历交互任务",
        plannedDate: .now,
        startTime: .now,
        calendarPlacement: .committed,
        estimatedMinutes: 45
    )
    let data = try JSONEncoder().encode(task)
    let decoded = try JSONDecoder().decode(WeekTask.self, from: data)
    #expect(decoded.calendarPlacement == .committed)

    let legacyObject = try #require(
        JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var legacy = legacyObject
    legacy.removeValue(forKey: "calendarPlacement")
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    let legacyTask = try JSONDecoder().decode(WeekTask.self, from: legacyData)
    #expect(legacyTask.calendarPlacement == .suggested)
}

@MainActor
@Test func calendarHoverPinTogglesCommittedAndSuggestedStates() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCalendarPin-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.activeTasks.first)
    var task = entry.task
    task.startTime = .now
    task.calendarPlacement = .suggested
    store.updateTask(task, goalID: entry.goal.id)

    store.toggleTaskCalendarCommitment(goalID: entry.goal.id, taskID: task.id)
    #expect(store.activeTasks.first(where: { $0.task.id == task.id })?.task.calendarPlacement == .committed)

    store.toggleTaskCalendarCommitment(goalID: entry.goal.id, taskID: task.id)
    #expect(store.activeTasks.first(where: { $0.task.id == task.id })?.task.calendarPlacement == .suggested)
}
