import Foundation
import Testing
@testable import Weekflow

private let currentPackageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

@MainActor
@Test func workspaceMenuUsesCustomPrimaryAndSystemSecondaryPresentation() throws {
    let sidebarSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/SidebarView.swift"
        ),
        encoding: .utf8
    )

    #expect(!sidebarSource.contains(".popover(isPresented: $isWorkspaceMenuPresented"))
    #expect(sidebarSource.contains(".sheet(item: $activeMenuPanel"))
    #expect(sidebarSource.contains(".presentationBackground(.regularMaterial)"))
    #expect(sidebarSource.contains("WorkspaceMenuPopover("))
    #expect(!sidebarSource.contains("WorkspacePanelPopover("))
    #expect(sidebarSource.contains("WorkspaceMenuSheet("))
    #expect(sidebarSource.contains("WindowOutsideClickMonitor("))
    #expect(sidebarSource.contains("dismissOnOtherWindows: true"))
    #expect(sidebarSource.contains("TaskDurationMenuPointer()"))
    #expect(sidebarSource.contains("ChannelSettingsView("))
    #expect(sidebarSource.contains("isWorkspaceHeaderHovering || isWorkspaceMenuPresented"))
    #expect(sidebarSource.contains("isWorkspaceMenuPresented.toggle()"))

    let settingsSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ChannelSettingsView.swift"
        ),
        encoding: .utf8
    )
    #expect(settingsSource.components(separatedBy: ".scrollIndicators(.automatic)").count - 1 == 2)
    #expect(settingsSource.components(separatedBy: ".background(SystemOverlayScroller())").count - 1 == 2)
    #expect(!settingsSource.contains(".scrollIndicators(.visible)"))
    #expect(settingsSource.contains("hoveredSection == section"))
    #expect(settingsSource.contains(".stablePointingHandHover"))
    #expect(settingsSource.components(separatedBy: ".pointingHandCursor()").count - 1 >= 8)
    #expect(settingsSource.contains(".pointingHandCursor(coversDescendants: true)"))

    let scrollerSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/SystemOverlayScroller.swift"
        ),
        encoding: .utf8
    )
    #expect(scrollerSource.contains("scrollView.scrollerStyle = .overlay"))
    #expect(scrollerSource.contains("scrollView.autohidesScrollers = true"))
    #expect(scrollerSource.contains("NSView.boundsDidChangeNotification"))
    #expect(scrollerSource.contains("showScrollerTemporarily"))
    #expect(scrollerSource.contains("scroller.isHidden = true"))
}

@MainActor
@Test func legacyFocusRecordsDecodeWithOneSession() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-000000000001",
      "date": 0,
      "mode": "meditation",
      "minutes": 25
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let record = try decoder.decode(FocusRecord.self, from: Data(json.utf8))
    #expect(record.sessionCount == 1)
    #expect(record.minutes == 25)
}

@MainActor
@Test func trashLivesInLeftNavigationInsteadOfAssistantRail() throws {
    #expect(AssistantPanel.railCases == [.calendar, .goals, .backlog, .shutdown, .search])
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/AssistantPanelViews.swift"
        ),
        encoding: .utf8
    )
    #expect(!source.contains("AssistantRailAddButton"))
}

@MainActor
@Test func assistantCalendarConsolidatesCutoffVisibilityIntoItsCustomMenu() throws {
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/AssistantPanelViews.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("AssistantCalendarOptionsMenu("))
    #expect(source.contains("showsCalendarOptions.toggle()"))
    #expect(source.contains("Text(\"显示任务截止时间\")"))
    #expect(source.contains("showsDailyCutoff.toggle()"))
    #expect(source.contains("assistantCalendarOptionsOverlay"))
    #expect(!source.contains(".help(showsDailyCutoff ? \"隐藏任务截止时间\""))
}

@MainActor
@Test func dailyPlanningCalendarButtonUsesTheSharedCutoffOptionsMenu() throws {
    let toolbarSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WorkspaceToolbar.swift"
        ),
        encoding: .utf8
    )
    let contentSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ContentView.swift"
        ),
        encoding: .utf8
    )

    #expect(toolbarSource.contains("toggleMenu(.calendarOptions)"))
    #expect(toolbarSource.contains("dailyPlanningStep == 0"))
    #expect(!toolbarSource.contains("dailyPlanningStep != 1"))
    #expect(toolbarSource.contains("AssistantCalendarOptionsMenu("))
    #expect(toolbarSource.contains("weekflow.calendar.showsDailyCutoff"))
    #expect(toolbarSource.contains("CGSize(width: 196, height: 44)"))
    #expect(!toolbarSource.contains("togglePlanningCalendar"))
    #expect(!contentSource.contains("toggleDailyPlanningCalendar"))
    #expect(!contentSource.contains("showsAssistantRail || destination == .dailyPlanning"))
}

@MainActor
@Test func dailyPlanningDateDrivesTheToolbarAndTheEntirePlanningPage() throws {
    let toolbarSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WorkspaceToolbar.swift"
        ),
        encoding: .utf8
    )
    let contentSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ContentView.swift"
        ),
        encoding: .utf8
    )
    let planningSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )

    #expect(contentSource.contains("@State private var dailyPlanningDate = SystemBusinessCalendar.current.calendar.date("))
    #expect(contentSource.contains("planningDate: dailyPlanningDate"))
    #expect(contentSource.contains("visibleDayCount: toolbarVisibleDayCount"))
    #expect(contentSource.contains("return Int(WeekflowLayout.boardVisibleDayCount)"))
    // navigateDailyPlanning now uses ContentCommandHandler.GlobalDateNavigation (P2-2)
    #expect(contentSource.contains("navigateDailyPlanning(_ navigation: ContentCommandHandler.GlobalDateNavigation)"))
    #expect(toolbarSource.contains("allowsReset: destination == .home"))
    #expect(toolbarSource.contains("|| destination == .dailyPlanning"))
    #expect(toolbarSource.contains("dailyPlanningDate = calendar.startOfDay(for: .now)"))
    #expect(toolbarSource.contains("PlanningDateJumpPopover("))
    #expect(planningSource.contains("planningDate.map { calendar.startOfDay(for: $0) }"))
    #expect(planningSource.contains(".onChange(of: tomorrow)"))
}

@MainActor
@Test func dailyPlanningTaskPoolReservesAnIndependentScrollbarLane() throws {
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("@State private var verticalScrollerTrackWidth = NSScroller.scrollerWidth("))
    #expect(source.contains("scrollerStyle: .legacy"))
    #expect(source.contains("private let cardWidthReduction: CGFloat = 10"))
    #expect(source.contains("proxy.size.width - verticalScrollerTrackWidth - cardWidthReduction"))
    #expect(source.contains(".frame(width: cardWidth, alignment: .topLeading)"))
    #expect(source.contains("ZeroInsetVerticalScroller("))
    #expect(source.contains("onTrackWidthChange: { measuredWidth in"))
    #expect(source.contains(".padding(.leading, contentInset)"))
    #expect(!source.contains(".padding(12)\n        .background(WeekflowPalette.surface"))
}

@MainActor
@Test func planningPoolAndDailyTasksUseTheSameSystemScrollerAlgorithm() throws {
    let planningSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )
    let scrollerSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/VerticalScrollerAlignment.swift"
        ),
        encoding: .utf8
    )

    #expect(planningSource.contains("isVisible: true,\n                                columnWidth: proxy.size.width"))
    #expect(!planningSource.contains("PlanningPoolScrollbar"))
    #expect(planningSource.contains("ScrollViewReader { scrollProxy in"))
    #expect(planningSource.contains("scrollProxy.scrollTo(taskID, anchor: .bottom)"))
    #expect(planningSource.contains("taskAssigned: { newlyAssignedTaskID = $0 }"))
    #expect(scrollerSource.contains("scrollView.scrollerStyle = .legacy"))
    #expect(scrollerSource.contains("scrollView.autohidesScrollers = !showsScroller"))
    #expect(scrollerSource.contains("scrollView.hasVerticalScroller = showsScroller"))
    #expect(scrollerSource.contains("width: targetWidth"))
    #expect(scrollerSource.contains("clipView.setBoundsOrigin"))
    #expect(!scrollerSource.contains("clipView.animator().setBoundsOrigin"))
    #expect(!scrollerSource.contains("scheduledScrollRequestID"))
    #expect(scrollerSource.contains("configureEnclosingScrollView(applyPendingScrollRequest: true)"))
    #expect(!scrollerSource.contains("PlanningPoolVerticalScroller"))
}

@MainActor
@Test func planningAndWeeklyBoardsShareTheHomepageMoveDropAlgorithm() throws {
    let planningSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )
    let weeklySource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )
    let dropSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/HomeTaskDropSupport.swift"
        ),
        encoding: .utf8
    )

    #expect(planningSource.components(separatedBy: "delegate: PlanningColumnTaskDropDelegate(").count - 1 == 1)
    #expect(planningSource.contains("private var homeDelegate: HomeColumnTaskDropDelegate"))
    #expect(planningSource.contains("guard draggedTaskToken?.sourceDate == nil else"))
    #expect(planningSource.contains("poolDropPreview = nil"))
    #expect(planningSource.contains(".onDrag {"))
    #expect(!planningSource.contains("TaskDropCoordinator.handle"))
    #expect(weeklySource.contains("delegate: HomeColumnTaskDropDelegate("))
    #expect(weeklySource.contains("selectedDates: entry.task.assignedDates"))
    #expect(weeklySource.contains("toggle: toggleAssignment"))
    #expect(!weeklySource.contains("WeeklyColumnTaskDropDelegate"))
    #expect(dropSource.contains("return DropProposal(operation: .move)"))
    #expect(dropSource.contains("isDropTarget?.wrappedValue = true"))
}

@MainActor
@Test func dailyPlanningPoolDragPreviewDoesNotAssignBeforeDrop() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPlanningPoolPreview-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = Calendar.current.startOfDay(for: .now)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    let entry = try #require(store.taskPool.first)
    let targetDate = try #require(
        Calendar.current.date(byAdding: .day, value: 20, to: referenceDate)
    )
    let token = TaskDragToken(goalID: entry.goal.id, taskID: entry.task.id)
    let preview = PlanningPoolDropPreview(token: token, before: nil)

    #expect(!store.tasks(on: targetDate).contains { $0.task.id == entry.task.id })
    #expect(
        planningDisplayedEntries(store: store, date: targetDate, preview: preview)
            .contains { $0.task.id == entry.task.id }
    )
    #expect(!store.tasks(on: targetDate).contains { $0.task.id == entry.task.id })
}

@MainActor
@Test func dailyPlanningPoolDoubleClickAppendsTaskToTheBottom() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPlanningPoolDoubleClick-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = Calendar.current.startOfDay(for: .now)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    let entry = try #require(store.taskPool.first)
    let targetDate = try #require(
        Calendar.current.date(byAdding: .day, value: 20, to: referenceDate)
    )
    let existingTaskID = try #require(
        store.addTask(
            to: entry.goal.id,
            title: "原有任务",
            plannedDate: targetDate,
            dueDate: nil,
            minutes: 30,
            notes: "",
            milestoneID: nil
        )
    )

    assignPlanningPoolTaskToBottom(
        store: store,
        goalID: entry.goal.id,
        taskID: entry.task.id,
        date: targetDate
    )

    let orderedTaskIDs = store.tasks(on: targetDate).map(\.task.id)
    #expect(orderedTaskIDs.contains(existingTaskID))
    #expect(orderedTaskIDs.last == entry.task.id)
}

@MainActor
@Test func dailyPlanningTaskListUsesHomepageWidthAndScrollerRules() throws {
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )

    #expect(source.contains("WeekflowLayout.homeTaskScrollViewportWidth("))
    #expect(source.contains("WeekflowLayout.homeShowsVerticalScroller("))
    #expect(source.contains("WeekflowLayout.homeTaskCardWidth("))
    #expect(source.contains("columnWidth: taskScrollViewportWidth"))
    #expect(source.contains("isVisible: showsVerticalScroller"))
    #expect(!source.contains("private let assignmentControlWidth"))
    #expect(!source.contains("private struct PlanningTaskCard"))
    #expect(source.contains("Button(action: removeFromTarget)"))
    #expect(source.contains("Label(\"已添加\", systemImage: \"checkmark\")"))
    #expect(source.contains("Text(entry.task.title)"))
    #expect(source.contains("Text(entry.goal.title)"))
    #expect(source.contains(".onTapGesture(count: 2, perform: assignToTarget)"))
    #expect(source.contains(".help(\"拖动或双击添加到当天任务\")"))
    #expect(source.contains("HomeAddTaskButton(action: addTask)\n                        .frame(width: cardContentWidth"))
}

@MainActor
@Test func removingFromDailyPlanningNeverMovesTheTaskToTrash() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPlanningRemoveFromDay-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = Calendar.current.startOfDay(for: .now)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    let poolEntry = try #require(store.taskPool.first)
    let targetDate = try #require(
        Calendar.current.date(byAdding: .day, value: 20, to: referenceDate)
    )
    store.assignTask(goalID: poolEntry.goal.id, taskID: poolEntry.task.id, to: targetDate)

    removePlanningTaskFromDay(
        store: store,
        goalID: poolEntry.goal.id,
        taskID: poolEntry.task.id,
        date: targetDate
    )

    let updatedPoolTask = try #require(
        store.goals.first(where: { $0.id == poolEntry.goal.id })?
            .tasks.first(where: { $0.id == poolEntry.task.id })
    )
    #expect(!updatedPoolTask.isAssigned(on: targetDate))
    #expect(updatedPoolTask.status != .deleted)
    #expect(store.taskPool.contains { $0.task.id == poolEntry.task.id })

    let nativeTaskID = try #require(
        store.addTask(
            to: poolEntry.goal.id,
            title: "普通当天任务",
            plannedDate: targetDate,
            dueDate: nil,
            minutes: 30,
            notes: "",
            milestoneID: nil
        )
    )
    removePlanningTaskFromDay(
        store: store,
        goalID: poolEntry.goal.id,
        taskID: nativeTaskID,
        date: targetDate
    )
    let updatedNativeTask = try #require(
        store.goals.first(where: { $0.id == poolEntry.goal.id })?
            .tasks.first(where: { $0.id == nativeTaskID })
    )
    #expect(updatedNativeTask.plannedDate == nil)
    #expect(updatedNativeTask.status != .deleted)
    #expect(store.taskPool.contains { $0.task.id == nativeTaskID })
}

@MainActor
@Test func dailyPlanningAssignmentsChainFromTheConfiguredWorkStart() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPlanningSchedule-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = Calendar.current.startOfDay(for: .now)
    let targetDate = try #require(
        Calendar.current.date(byAdding: .day, value: 25, to: referenceDate)
    )
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    _ = store.setDailyPlanningStart(minutes: 8 * 60 + 30, on: targetDate)
    let poolEntries = Array(store.taskPool.prefix(2))
    #expect(poolEntries.count == 2)

    assignPlanningPoolTaskToBottom(
        store: store,
        goalID: poolEntries[0].goal.id,
        taskID: poolEntries[0].task.id,
        date: targetDate
    )
    assignPlanningPoolTaskToBottom(
        store: store,
        goalID: poolEntries[1].goal.id,
        taskID: poolEntries[1].task.id,
        date: targetDate
    )

    let scheduled = store.tasks(on: targetDate)
    let first = try #require(scheduled.first { $0.task.id == poolEntries[0].task.id }?.task)
    let second = try #require(scheduled.first { $0.task.id == poolEntries[1].task.id }?.task)
    #expect(first.estimatedMinutes == 60)
    #expect(second.estimatedMinutes == 60)
    #expect(first.startTime.map { Calendar.current.component(.hour, from: $0) } == 8)
    #expect(first.startTime.map { Calendar.current.component(.minute, from: $0) } == 30)
    #expect(second.startTime.map { Calendar.current.component(.hour, from: $0) } == 9)
    #expect(second.startTime.map { Calendar.current.component(.minute, from: $0) } == 30)
}

@MainActor
@Test func dailyPlanningUsesIndependentStableThreeColumnSteps() throws {
    let planningSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )
    let contentSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ContentView.swift"
        ),
        encoding: .utf8
    )
    let cardSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/HomeBoardViews.swift"
        ),
        encoding: .utf8
    )

    #expect(planningSource.contains("title: \"每周任务池\""))
    #expect(planningSource.contains("workTimeCard(date: date)"))
    #expect(planningSource.contains("PlanningTaskList("))
    #expect(planningSource.contains("switch step"))
    #expect(planningSource.contains("waitingStep(date: tomorrow"))
    #expect(planningSource.contains("finalPlanningStep(date: tomorrow"))
    #expect(planningSource.components(separatedBy: "PlanningTaskList(").count - 1 == 4)
    #expect(!planningSource.contains("SunsamaAssistantPanel("))
    #expect(planningSource.contains("Color.clear"))
    #expect(contentSource.contains(".onChange(of: dailyPlanningStep)"))
    #expect(contentSource.contains("handleDailyPlanningStepChange(oldStep: oldStep, newStep: newStep)"))
    #expect(contentSource.contains("assistantCalendarPresentation = .timeline"))
    #expect(contentSource.contains("activeAssistantPanel = .calendar"))
    #expect(contentSource.contains("resolvedAssistantPanelWidth("))
    #expect(!planningSource.contains("AssistantCalendarView(store: store, activeDate: $store.activeDay)"))
    #expect(planningSource.contains("DailyWorkspaceColumnHeader("))
    #expect(planningSource.contains("WeekflowLayout.dailyWorkspaceHeaderHeight"))
    #expect(planningSource.contains("scrollRequest: timerScrollRequest"))
    #expect(planningSource.contains("timerExpansionRequested:"))
    #expect(!contentSource.contains("case .focus, .dailyPlanning, .dailyShutdown, .archive:"))
    #expect(cardSource.contains("return TaskTimeDisplay.unsetStart"))
    #expect(cardSource.contains("TaskTimeDisplay.estimated(minutes:"))
    #expect(planningSource.contains("WorkTimePickerMenuOverlay("))
    #expect(planningSource.contains("WindowOutsideClickMonitor("))
    #expect(planningSource.contains("title: \"接续未完成任务\""))
    #expect(!planningSource.contains("title: \"什么可以等？\""))
    #expect(planningSource.contains("title: \"确定计划\""))
    #expect(planningSource.contains("continuationSummary(currentDate: currentDate, targetDate: date)"))
    #expect(planningSource.contains("WeekflowDailyProgressTrack("))
    #expect(cardSource.contains("WeekflowDailyProgressTrack("))
    #expect(planningSource.contains("PlanningSortMenuOverlay("))
    #expect(planningSource.contains("store.sortTasksByStartTime(on: date)"))
    #expect(!planningSource.contains("Text(\"今日任务\")"))
    #expect(!planningSource.contains("ShutdownTaskCard"))
    #expect(planningSource.contains("compactHeight: WeekflowLayout.homeTaskCardHeight"))
    #expect(planningSource.contains("title: \"今日回顾\","))
    #expect(planningSource.contains("columnSpacing: WeekflowLayout.dailyWorkspaceColumnSpacing"))
    #expect(contentSource.contains("case .focus, .archive, .trash:"))
    #expect(!contentSource.contains("case .focus, .dailyShutdown, .archive:"))
    #expect(!planningSource.contains(".popover(isPresented: $showsStartPicker"))
    #expect(!planningSource.contains(".popover(isPresented: $showsShutdownPicker"))
}

@MainActor
@Test func unsetTaskTimesFollowTheSharedEstimatedAndActualRules() {
    #expect(TaskTimeDisplay.estimated(minutes: 0) == "--:--")
    #expect(TaskTimeDisplay.actual(minutes: 0, estimatedMinutes: 0) == "--:--")
    #expect(TaskTimeDisplay.actual(minutes: 0, estimatedMinutes: 60) == "00:00")
    #expect(TaskTimeDisplay.actual(minutes: 15, estimatedMinutes: 60) == "00:15")
}

@MainActor
@Test func searchDateFiltersUseStableCalendarIntervals() {
    let calendar = Calendar(identifier: .gregorian)
    let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 16))!
    let lastWeek = calendar.date(byAdding: .day, value: -7, to: now)!
    let oldTask = WeekTask(title: "上周", plannedDate: lastWeek, estimatedMinutes: 30)
    #expect(AssistantSearchDateFilter.lastWeek.matches(oldTask, now: now, calendar: calendar))
    #expect(!AssistantSearchDateFilter.lastMonth.matches(oldTask, now: now, calendar: calendar))
}

@MainActor
@Test func timeMenusUseOneLeftAlignedUnsetAction() throws {
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ScrollTimePickers.swift"
        ),
        encoding: .utf8
    )
    #expect(!source.contains("取消开始时间"))
    #expect(!source.contains("取消预计时间"))
    #expect(source.components(separatedBy: "title: \"不设置\"").count - 1 == 2)
    let scrollEnd = try #require(source.range(of: ".scrollIndicators(.visible)"))
    let startUnset = try #require(source.range(of: "selectionRow(title: \"不设置\""))
    #expect(scrollEnd.lowerBound < startUnset.lowerBound)
    let durationStart = try #require(source.range(of: "struct ScrollDurationPopover"))
    let durationSource = String(source[durationStart.lowerBound...])
    let durationScroll = try #require(durationSource.range(of: ".scrollIndicators(.visible)"))
    let durationUnset = try #require(durationSource.range(of: "title: \"不设置\""))
    #expect(durationScroll.lowerBound < durationUnset.lowerBound)
}

@MainActor
@Test func taskCardTimeMenusUseCustomStartPresentationAndMeasuredEstimatedAnchor() throws {
    let homeSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/HomeBoardViews.swift"
        ),
        encoding: .utf8
    )
    let sharedMenuSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/TaskCardPrimaryMenuOverlays.swift"
        ),
        encoding: .utf8
    )
    #expect(homeSource.contains("TaskCardStartTimeMenuOverlay("))
    #expect(homeSource.contains(".startTimeButton(entry.task.id)"))
    #expect(sharedMenuSource.contains("WindowOutsideClickMonitor("))
    #expect(sharedMenuSource.contains("x: estimatedDurationButtonFrame?.midX"))
    #expect(sharedMenuSource.contains("let menuTop = cardFrame.maxY"))
    #expect(!sharedMenuSource.contains("let expandedCardBottom = cardFrame.minY"))
}

@MainActor
@Test func dailyPlanningUsesCustomTaskCardMenusButOmitsDateAdjustment() throws {
    let homeSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/HomeBoardViews.swift"
        ),
        encoding: .utf8
    )
    let planningSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )

    for menuType in [
        "TaskCardDurationMenuOverlay(",
        "TaskCardStartTimeMenuOverlay(",
        "TaskCardChannelMenuOverlay(",
        "TaskCardPriorityMenuOverlay("
    ] {
        #expect(homeSource.contains(menuType))
        #expect(planningSource.contains(menuType))
    }

    // Every planning step reuses this one task-column implementation, so its
    // custom menus and drop behavior cannot drift between pages.
    #expect(planningSource.components(separatedBy: "showsEstimatedDurationMenu: Binding(").count - 1 == 1)
    #expect(planningSource.components(separatedBy: "showsStartTimeMenu: Binding(").count - 1 == 1)
    #expect(planningSource.components(separatedBy: "showsChannelMenu: Binding(").count - 1 == 1)
    #expect(planningSource.components(separatedBy: "showsPriorityMenu: Binding(").count - 1 == 1)
    // Daily planning and daily shutdown both reuse the shared task card while
    // intentionally omitting date adjustment on their workflow surfaces.
    #expect(planningSource.components(separatedBy: "showsDateControl: false").count - 1 == 2)
    #expect(!planningSource.contains("showsDateMenu: Binding("))
    #expect(!planningSource.contains("TaskCardDateMenuOverlay("))
    // Daily task cards rely on the shared overlay dismissal. The two local
    // monitors belong to the work-time picker and the column sort menu.
    #expect(planningSource.components(separatedBy: "WindowOutsideClickMonitor").count - 1 == 2)
}

@MainActor
@Test func taskCardMainAndSubtaskCompletionControlsCannotDriftInSize() throws {
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/HomeBoardViews.swift"
        ),
        encoding: .utf8
    )
    #expect(source.components(separatedBy: "TaskCardCompletionButton(").count - 1 == 2)
    #expect(source.contains("sizeAdjustment: TaskCardTypographyPreferences.completionIconSizeAdjustment"))
}

@MainActor
@Test func focusDurationUsesApplicationOwnedMenuInsteadOfSystemPopover() throws {
    let focusSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/FocusView.swift"
        ),
        encoding: .utf8
    )
    let menuBarSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/FocusMenuBarPanel.swift"
        ),
        encoding: .utf8
    )
    let durationMenuSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/FocusDurationMenu.swift"
        ),
        encoding: .utf8
    )
    let statusItemSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/FocusStatusItemController.swift"
        ),
        encoding: .utf8
    )
    #expect(focusSource.contains("FocusDurationMenu("))
    #expect(menuBarSource.contains("FocusDurationMenu("))
    #expect(focusSource.contains("onSelection:"))
    #expect(menuBarSource.contains("onSelection:"))
    #expect(durationMenuSource.contains("onSelection()"))
    #expect(statusItemSource.contains("button.title = \"\""))
    #expect(!statusItemSource.contains("statusBarTitle"))
    #expect(!focusSource.contains(".popover(isPresented: $isEditingDuration"))
    #expect(!menuBarSource.contains(".popover(isPresented: $isEditingDuration"))
}

@MainActor
@Test func focusStatusPanelUsesTheMutedFloatingPanelPalette() throws {
    let paletteSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/WeekflowPalette.swift"
        ),
        encoding: .utf8
    )
    let menuBarSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/FocusMenuBarPanel.swift"
        ),
        encoding: .utf8
    )
    let statusItemSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/FocusStatusItemController.swift"
        ),
        encoding: .utf8
    )
    let focusModeSource = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Models/FocusSession.swift"
        ),
        encoding: .utf8
    )

    #expect(paletteSource.contains("static let floatingPanelSurface"))
    #expect(paletteSource.contains("static let floatingPanelRaisedSurface"))
    #expect(menuBarSource.contains(".background(WeekflowPalette.floatingPanelSurface)"))
    #expect(menuBarSource.contains("WeekflowPalette.floatingPanelRaisedSurface"))
    #expect(statusItemSource.contains(".fill(WeekflowPalette.floatingPanelSurface)"))
    #expect(focusModeSource.contains("WeekflowPalette.focusMeditation"))
    #expect(focusModeSource.contains("WeekflowPalette.focusStudy"))
    #expect(focusModeSource.contains("WeekflowPalette.focusLeisure"))
}

@MainActor
@Test func assistantSearchKeepsThreeCustomFilterButtons() throws {
    let source = try String(
        contentsOf: currentPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/AssistantSearchView.swift"
        ),
        encoding: .utf8
    )
    #expect(source.contains("id: .filter"))
    #expect(source.contains("id: .date"))
    #expect(source.contains("id: .channel"))
    #expect(source.contains("case .date:"))
    #expect(source.contains("case .channel:"))
    #expect(source.contains("menuOverlay(for: activeMenu)"))
    #expect(source.contains("showsManageChannelAction: false"))
    #expect(source.contains("hoveredButton == id"))
    #expect(source.contains("WindowOutsideClickMonitor("))
    #expect(source.contains("menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1"))
    #expect(!source.contains("Picker("))
    #expect(!source.contains(".popover("))
}
