import Foundation
import Testing
@testable import Weekflow

private let weeklyRefinementPackageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

@MainActor
@Test func weeklyPlanningRangeOnlyDismissesOutsideItsEditor() {
    #expect(!WeeklyPlanningRangeDismissalPolicy.shouldDismiss(isInteractingInsidePanel: true))
    #expect(WeeklyPlanningRangeDismissalPolicy.shouldDismiss(isInteractingInsidePanel: false))
    #expect(
        CompactCalendarHighlightMetrics.singleDayDiameter
            < CompactCalendarHighlightMetrics.rangeHeight
    )
    #expect(
        CompactCalendarHighlightMetrics.hoverOpacity
            <= CompactCalendarHighlightMetrics.rangeStartOpacity
    )
    #expect(
        CompactCalendarHighlightMetrics.todayOpacity
            > CompactCalendarHighlightMetrics.selectedDayOpacity
    )
    #expect(
        CompactCalendarHighlightMetrics.selectedDayOpacity
            > CompactCalendarHighlightMetrics.rangeStartOpacity
    )
    #expect(
        CompactCalendarHighlightMetrics.singleDayOpacity(
            isToday: true,
            isSelected: false,
            isRangeStart: true
        ) == CompactCalendarHighlightMetrics.todayOpacity
    )
    #expect(
        CompactCalendarHighlightMetrics.singleDayOpacity(
            isToday: true,
            isSelected: true,
            isRangeStart: true
        ) == CompactCalendarHighlightMetrics.todayOpacity
    )
}

@MainActor
@Test func weeklyRelationshipGoalCentersNeverOverlap() {
    let centers = WeeklyRelationshipLayout.nonOverlappingCenters(
        desiredCenters: [45, 117, 189],
        nodeHeight: 82,
        spacing: 12
    )

    #expect(centers.count == 3)
    #expect(centers[1] - centers[0] >= 94)
    #expect(centers[2] - centers[1] >= 94)

    let offset = WeeklyRelationshipLayout.centeredOffset(
        centers: centers,
        nodeHeight: 82,
        canvasHeight: 420
    )
    let firstTop = centers[0] + offset - 41
    let lastBottom = centers[2] + offset + 41
    #expect(abs(firstTop - (420 - lastBottom)) < 0.001)
}

@MainActor
@Test func weeklyRelationshipDropUpdatesTheSharedSectionData() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowRelationshipDrop-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let targetDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 23, hour: 12))
    )
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let goalID = store.addGoal(title: "拖动关系任务", outcome: "", endDate: targetDate)
    let entry = try #require(store.weeklyPlanningPoolEntries.first { $0.goal.id == goalID })
    let token = TaskDragToken(goalID: goalID, taskID: entry.task.id)

    WeeklyRelationshipDropCoordinator.assign(token, to: targetDate, in: store)

    #expect(store.weeklyPlanningTasks(on: targetDate).contains { $0.task.id == entry.task.id })
    #expect(store.weeklyPlanningPoolEntries.contains { $0.task.id == entry.task.id })
    #expect(Calendar.current.isDate(store.activeDay, inSameDayAs: targetDate))
}

@MainActor
@Test func dailyManualTaskDoesNotPolluteWeeklyAssignments() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDailyWeeklyIsolation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let targetDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 24, hour: 12))
    )
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let goalID = store.addGoal(title: "周计划来源", outcome: "", endDate: targetDate)
    let weeklyEntry = try #require(store.weeklyPlanningPoolEntries.first { $0.goal.id == goalID })
    store.assignTask(goalID: goalID, taskID: weeklyEntry.task.id, to: targetDate)
    let manualTaskID = try #require(store.addTask(
        to: goalID,
        title: "每日计划临时任务",
        plannedDate: targetDate,
        dueDate: nil,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))

    let dailyEntries = store.tasks(on: targetDate)
    let weeklyEntries = store.weeklyPlanningTasks(on: targetDate)
    #expect(dailyEntries.contains { $0.task.id == weeklyEntry.task.id })
    #expect(dailyEntries.contains { $0.task.id == manualTaskID })
    #expect(weeklyEntries.contains { $0.task.id == weeklyEntry.task.id })
    #expect(!weeklyEntries.contains { $0.task.id == manualTaskID })
}

@MainActor
@Test func weeklyPlanningRangePersistsIndependentlyForEachWeek() throws {
    let suiteName = "WeekflowWeeklyPlanningRange-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let calendar = Calendar.current
    let firstReference = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 12))
    )
    let firstStart = try #require(calendar.date(byAdding: .day, value: -1, to: firstReference))
    let firstEnd = try #require(calendar.date(byAdding: .day, value: 4, to: firstStart))

    WeeklyPlanningRangePreferences.save(
        start: firstStart,
        end: firstEnd,
        for: firstReference,
        calendar: calendar,
        defaults: defaults
    )
    let restored = WeeklyPlanningRangePreferences.range(
        for: firstReference,
        calendar: calendar,
        defaults: defaults
    )
    #expect(calendar.isDate(restored.start, inSameDayAs: firstStart))
    #expect(calendar.isDate(restored.end, inSameDayAs: firstEnd))

    let nextWeek = try #require(calendar.date(byAdding: .day, value: 7, to: firstReference))
    let nextRange = WeeklyPlanningRangePreferences.range(
        for: nextWeek,
        calendar: calendar,
        defaults: defaults
    )
    #expect(nextRange == WeeklyPlanningRangePreferences.defaultRange(for: nextWeek, calendar: calendar))
}

@MainActor
@Test func compactCalendarOnlyUsesCapsulesForMultiDayRanges() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let today = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21))
    )
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))

    #expect(!CompactCalendarHighlightPolicy.isMultiDayRange(
        start: today,
        end: today,
        calendar: calendar
    ))
    #expect(CompactCalendarHighlightPolicy.isMultiDayRange(
        start: today,
        end: tomorrow,
        calendar: calendar
    ))
}

@MainActor
@Test func weeklyToolbarNavigationUsesMondayWeekAndKeepsSelectedDay() throws {
    #expect(AppDestination.dailyShutdown.rawValue == "每日回顾")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let selectedWednesday = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 22))
    )
    let currentTuesday = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21))
    )
    let nextMonday = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))
    )

    let start = WeeklyDateNavigation.weekStart(for: selectedWednesday, calendar: calendar)
    let end = WeeklyDateNavigation.weekEnd(for: selectedWednesday, calendar: calendar)

    #expect(calendar.component(.day, from: start) == 20)
    #expect(calendar.component(.day, from: end) == 26)
    #expect(WeeklyDateNavigation.isCurrentWeek(
        selectedWednesday,
        now: currentTuesday,
        calendar: calendar
    ))
    #expect(!WeeklyDateNavigation.isCurrentWeek(
        nextMonday,
        now: currentTuesday,
        calendar: calendar
    ))
}

@MainActor
@Test func weeklyGoalCompletionCanBeMarkedAndReopened() {
    let referenceDate = Date(timeIntervalSince1970: 1_750_000_000)
    let store = WeekflowStore(
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    let goal = store.goals[0]

    store.setGoalCompleted(id: goal.id, completed: true)
    #expect(store.goals[0].progress == 1)
    #expect(store.goals[0].completedAt != nil)

    store.setGoalCompleted(id: goal.id, completed: false)
    #expect(store.goals[0].completedAt == nil)
    #expect(store.goals[0].tasks.allSatisfy { $0.status != .completed })
}

@MainActor
@Test func flatWeeklyGoalCreatesAndKeepsOneMatchingPoolTask() throws {
    let referenceDate = Date(timeIntervalSince1970: 1_750_000_000)
    let store = WeekflowStore(
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    store.addGoal(
        title: "准备周汇报",
        outcome: "形成可提交版本",
        startDate: referenceDate,
        endDate: referenceDate,
        channelID: "work"
    )

    var goal = try #require(store.goals.first { $0.title == "准备周汇报" })
    let primaryTaskID = try #require(goal.primaryTaskID)
    #expect(store.taskPool.contains { $0.goal.id == goal.id && $0.task.id == primaryTaskID })

    goal.title = "完成周汇报"
    store.updateGoal(goal)
    let updatedGoal = try #require(store.goals.first { $0.id == goal.id })
    let updatedTask = try #require(updatedGoal.tasks.first { $0.id == primaryTaskID })
    #expect(updatedTask.title == "完成周汇报")
}

@MainActor
@Test func weeklyPlanningUsesTaskStyleDateMenusAndQuickAssignment() throws {
    let boardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )
    let toolbarSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WorkspaceToolbar.swift"
        ),
        encoding: .utf8
    )
    let calendarSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/TaskCardPopovers.swift"
        ),
        encoding: .utf8
    )
    #expect(boardSource.contains("showsPlanningRange.toggle()"))
    #expect(boardSource.components(separatedBy: "CompactTaskMonthCalendar(").count - 1 == 1)
    #expect(boardSource.contains("planningBoundaryButton(.start"))
    #expect(boardSource.contains("planningBoundaryButton(.end"))
    #expect(boardSource.contains("planningRangeBoundary = .end"))
    #expect(boardSource.contains("highlightsToday: true"))
    #expect(boardSource.contains("isPlanningRangeInteractionActive = true"))
    #expect(boardSource.contains("WeeklyPlanningRangeDismissalPolicy.shouldDismiss("))
    #expect(!boardSource.contains(".onTapGesture(count: 2, perform: quickAssign)"))
    #expect(boardSource.contains("Image(systemName: \"calendar.badge.plus\")"))
    #expect(boardSource.contains("WeeklyTaskPoolDayPicker("))
    #expect(!boardSource.contains("Text(\"添加到某一天\")"))
    #expect(boardSource.contains("selectedDates: entry.task.assignedDates"))
    #expect(!boardSource.contains("Label(\"添加子目标\""))
    #expect(toolbarSource.contains("WeeklyDateJumpPopover("))
    #expect(toolbarSource.contains("title: \"跳转到本周\""))
    #expect(toolbarSource.contains("highlightedRangeStart: weekStart"))
    #expect(toolbarSource.contains("highlightedRangeEnd: weekEnd"))
    #expect(toolbarSource.contains("selectedDate: selectedDate"))
    #expect(toolbarSource.contains("highlightsToday: true"))
    #expect(toolbarSource.contains("highlightsSelectedDate: false"))
    #expect(calendarSource.contains("singleDayHighlight(opacity:"))
    #expect(!calendarSource.contains("todayDiameter"))
    #expect(!calendarSource.contains("selectedDiameter"))
    #expect(!calendarSource.contains(".stroke(WeekflowPalette.objective.opacity(0.82)"))
}

@MainActor
@Test func weeklyRelationshipSwitchLivesInTheTopToolbarInsteadOfTheBoardHeader() throws {
    let boardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )
    let toolbarSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WorkspaceToolbar.swift"
        ),
        encoding: .utf8
    )
    let contentSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ContentView.swift"
        ),
        encoding: .utf8
    )

    #expect(!boardSource.contains("WeeklyPlanningViewSwitchButton"))
    #expect(boardSource.contains("private enum RelationshipHoverNode: Equatable"))
    #expect(!boardSource.contains("relationshipResultCard("))
    #expect(boardSource.contains("WeeklyRelationshipDateDropDelegate"))
    #expect(boardSource.contains("WeeklyRelationshipDropCoordinator.assign(token, to: date, in: store)"))
    #expect(boardSource.contains("accessibilityHint(\"点击编辑；拖动到右侧日期进行安排\")"))
    #expect(boardSource.contains("style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])"))
    #expect(boardSource.contains("if dropTargetDate == nil,"))
    #expect(boardSource.contains("relationshipDateAssignmentPreview("))
    #expect(boardSource.contains("goalGroupHeight + 24"))
    #expect(boardSource.contains("WeeklyRelationshipLayout.centeredOffset("))
    #expect(boardSource.contains("store.relocateTask("))
    #expect(boardSource.contains("case goal(WeeklyGoal.ID)"))
    #expect(boardSource.contains("ForEach(relationshipDates.indices"))
    #expect(boardSource.contains("store.weeklyPlanningTasks(on: date)"))
    #expect(boardSource.contains("Canvas { context, _ in"))
    #expect(toolbarSource.contains("if destination == .weeklyPlanning"))
    #expect(toolbarSource.contains("title: weeklyPlanningPresentation == .sections ? \"关系图\" : \"分区图\""))
    #expect(toolbarSource.contains("fixedWidth: 96"))
    #expect(boardSource.contains("private var canvasWidth: CGFloat { max(489, availableWidth - 52) }"))
    #expect(boardSource.contains("private var columnSpacing: CGFloat"))
    #expect(boardSource.contains("WeeklyRelationshipAvailableWidthPreferenceKey"))
    #expect(boardSource.contains("if presentation == .sections {\n                header"))
    #expect(boardSource.contains("private let goalNodeSpacing: CGFloat = 12"))
    #expect(boardSource.contains(".frame(width: canvasWidth + 20, alignment: .leading)"))
    #expect(boardSource.contains(".fixedSize(horizontal: true, vertical: false)"))
    #expect(boardSource.contains(".frame(width: goalNodeWidth, alignment: .leading)"))
    #expect(boardSource.contains("Text(\"周目标\")"))
    #expect(boardSource.contains("private var relationshipHeader: some View"))
    #expect(boardSource.contains("private var relationshipSurface: some View"))
    #expect(boardSource.contains("private var taskNodeWidth: CGFloat { min(max(canvasWidth * 0.24, 155), 190) }"))
    #expect(boardSource.contains("return (taskCenterY(at: first) + taskCenterY(at: last)) / 2"))
    #expect(contentSource.contains("weeklyPlanningPresentation: $weeklyPlanningPresentation"))
    #expect(contentSource.contains(".frame(width: WeekflowLayout.assistantRailWidth)\n                .layoutPriority(1)"))
    #expect(contentSource.contains(".frame(maxWidth: .infinity, maxHeight: .infinity)\n            .layoutPriority(-1)"))
    let switchLocation = try #require(toolbarSource.range(of: "if destination == .weeklyPlanning"))
    let planningCalendarLocation = try #require(toolbarSource.range(of: "if showsPlanningCalendar"))
    #expect(switchLocation.lowerBound < planningCalendarLocation.lowerBound)
}

@MainActor
@Test func weeklyGoalCreateAndEditEntriesOpenTheExactTaskDetailPage() throws {
    let boardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )
    let contentSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/ContentView.swift"
        ),
        encoding: .utf8
    )
    let detailSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/TaskDetailView.swift"
        ),
        encoding: .utf8
    )
    let homeCardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/HomeBoardViews.swift"
        ),
        encoding: .utf8
    )
    let appSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/App/WeekflowApp.swift"
        ),
        encoding: .utf8
    )
    let shortcutSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/TaskCardKeyboardShortcutAnchor.swift"
        ),
        encoding: .utf8
    )
    let contextMenuSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/TaskCardContextPopover.swift"
        ),
        encoding: .utf8
    )

    #expect(boardSource.contains("@Binding var presentedTask: TaskDetailTarget?"))
    #expect(boardSource.contains("action: createGoal"))
    #expect(boardSource.contains("title: \"\""))
    #expect(boardSource.contains("edit: { openGoal(goal.id) }"))
    #expect(boardSource.contains("presentedTask = TaskDetailTarget("))
    #expect(boardSource.contains("isWeeklyGoalDetail: true"))
    #expect(boardSource.contains("isNewWeeklyGoal: isNew"))
    #expect(boardSource.contains("Button(action: edit)"))
    #expect(boardSource.contains(".pointingHandCursor(coversDescendants: true)"))
    #expect(boardSource.contains("TaskCardContextMenuAnchor("))
    #expect(boardSource.contains("WeeklyGoalContextPopover("))
    #expect(boardSource.contains("store.copyGoalToClipboard(id: goal.id)"))
    #expect(boardSource.contains("store.copyGoalToClipboard(id: goal.id, cutsSource: true)"))
    #expect(boardSource.contains("store.pasteGoalClipboard("))
    #expect(boardSource.contains("afterGoalID: goal.id"))
    #expect(boardSource.contains("store.deleteGoal(id: goal.id)"))
    #expect(boardSource.contains("store.moveGoalToNextWeek(id: goal.id)"))
    #expect(boardSource.contains("if store.canUndoAutomaticDistribution"))
    #expect(boardSource.contains("WeeklyHeaderUndoButton(action: store.undoAutomaticDistribution)"))
    #expect(boardSource.contains("Label(\"撤销分配\", systemImage: \"arrow.uturn.backward\")"))
    #expect(!boardSource.contains("isExpanded"))
    #expect(!boardSource.contains("Text(goal.outcome)"))
    #expect(boardSource.contains("ForEach(goal.subgoals)"))
    #expect(!boardSource.contains("GoalEditFormView("))
    #expect(detailSource.components(separatedBy: "if !target.isWeeklyGoalDetail").count - 1 == 3)
    #expect(detailSource.contains("archivePropertyButton(entry)"))
    #expect(detailSource.contains("store.archiveGoal(id: entry.goal.id)"))
    #expect(detailSource.contains("store.archiveTask(goalID: entry.goal.id, taskID: entry.task.id)"))
    #expect(detailSource.contains("Text(\"未归档\")"))
    #expect(detailSource.contains("Text(\"未归档\")\n                        .foregroundStyle(WeekflowPalette.textMuted)"))
    #expect(detailSource.contains("store.deleteGoal(id: entry.goal.id)"))
    #expect(detailSource.contains("WeekflowPalette.textMuted.opacity(0.68)"))
    #expect(detailSource.contains("target.isWeeklyGoalDetail ? \"添加子目标\" : \"添加子任务\""))
    #expect(detailSource.contains("target.isWeeklyGoalDetail ? \"目标描述...\" : \"任务描述...\""))
    #expect(detailSource.contains("discardEmptyWeeklyGoalDraftIfNeeded"))
    #expect(homeCardSource.contains("if hovering {\n                selectForCommand()"))
    #expect(homeCardSource.contains("TaskCardKeyboardShortcutAnchor("))
    #expect(homeCardSource.contains("isActive: isHovering || showsContextPopover"))
    #expect(!homeCardSource.contains("help: \"归档任务\""))
    #expect(shortcutSource.contains("if modifiers == [.command]"))
    #expect(shortcutSource.contains("if modifiers == [.command, .shift], event.keyCode == 124"))
    #expect(shortcutSource.contains("!self.isEditingText(in: event.window)"))
    #expect(shortcutSource.contains("case (\"c\", _): copyAction()"))
    #expect(shortcutSource.contains("case (\"v\", _): pasteAction()"))
    #expect(shortcutSource.contains("case (_, 51), (_, 117): deleteAction()"))
    #expect(contextMenuSource.contains("title: \"剪切\""))
    #expect(contextMenuSource.contains("title: \"粘贴\""))
    #expect(contextMenuSource.contains("trailing: \"⌘  C\""))
    #expect(!contextMenuSource.contains("复制任务"))
    #expect(!contextMenuSource.contains("剪切任务"))
    #expect(!contextMenuSource.contains("粘贴任务"))
    #expect(!contextMenuSource.contains("删除任务"))
    #expect(!contextMenuSource.contains("复制目标"))
    #expect(!contextMenuSource.contains("剪切目标"))
    #expect(!contextMenuSource.contains("粘贴目标"))
    #expect(!contextMenuSource.contains("删除目标"))
    #expect(contextMenuSource.contains("title: \"移动到下一周\""))
    #expect(contextMenuSource.contains("symbol: \"arrow.right.circle\""))
    #expect(!contextMenuSource.contains("calendar.badge.arrow.forward"))
    #expect(contextMenuSource.contains("trailing: \"⇧⌘  →\""))
    #expect(boardSource.contains("WeekflowDailyProgressTrack("))
    #expect(boardSource.contains("TaskTimeDisplay.estimated(minutes: totalEstimatedMinutes)"))
    #expect(boardSource.contains("TaskTimeDisplay.estimated(minutes: estimatedMinutes(for: subgoal))"))
    #expect(boardSource.contains("Label(\"完成 \\(completionCountText)\", systemImage: \"checkmark.circle\")"))
    #expect(!boardSource.contains("store.channel(for: subgoal.channelID ?? goal.channelID)"))
    #expect(boardSource.contains("systemImage: \"clock\""))
    #expect(boardSource.contains("primaryTask?.estimatedMinutes"))
    #expect(boardSource.contains("store.channel(for: goal.channelID)?.color"))
    #expect(boardSource.contains("let goalChannel = store.channel(for: goal.channelID)"))
    #expect(boardSource.contains("tint: goalTint"))
    #expect(boardSource.contains("if let goalChannelColor"))
    #expect(boardSource.contains(".fill(goalChannelColor)"))
    #expect(!boardSource.contains("store.channel(for: goal.channelID)?.color ?? WeekflowPalette.objective"))
    #expect(!boardSource.contains("ProgressView(value: goal.progress)"))
    #expect(!boardSource.contains(".padding(.leading, 34)"))
    #expect(homeCardSource.contains("showsContextPopover = false"))
    #expect(!appSource.contains(".keyboardShortcut(\"c\", modifiers: [.command])"))
    #expect(!appSource.contains(".keyboardShortcut(\"v\", modifiers: [.command])"))
    // Command handling moved to ContentCommandHandler (P2-2 ContentView split)
    let commandHandlerSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/ContentCommandHandler.swift"
        ),
        encoding: .utf8
    )
    #expect(commandHandlerSource.contains("case .copyHighlightedTask:"))
    #expect(commandHandlerSource.contains("store.copyHighlightedTask()"))
    #expect(commandHandlerSource.contains("case .pasteTask:"))
    #expect(commandHandlerSource.contains("store.pasteTaskClipboard(on: store.activeDay)"))
    #expect(commandHandlerSource.contains("store.deleteTask(goalID: reference.goalID, taskID: reference.taskID)"))
    #expect(contentSource.components(separatedBy: "TaskDetailView(").count - 1 == 1)
    #expect(!contentSource.contains("GoalFormView("))
}

@MainActor
@Test func weeklyGoalClipboardSeparatesCopyCutPasteAndMoveToNextWeek() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowGoalClipboard-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let start = Calendar.current.startOfDay(for: .now)
    let end = try #require(Calendar.current.date(byAdding: .day, value: 6, to: start))
    let goalID = store.addGoal(title: "本周发布", outcome: "", startDate: start, endDate: end)

    store.copyGoalToClipboard(id: goalID)
    #expect(store.hasGoalClipboard)
    #expect(store.goals.count == 1)
    let copiedID = try #require(
        store.pasteGoalClipboard(toWeekContaining: start, afterGoalID: goalID)
    )
    let copied = try #require(store.goals.first(where: { $0.id == copiedID }))
    #expect(copied.title == "本周发布 副本")
    #expect(copiedID != goalID)
    let orderedGoalIDs = store.activeGoals.map(\.id)
    #expect(orderedGoalIDs.firstIndex(of: copiedID) == orderedGoalIDs.firstIndex(of: goalID).map { $0 + 1 })

    let nextWeek = try #require(Calendar.current.date(byAdding: .day, value: 7, to: start))
    store.copyGoalToClipboard(id: goalID, cutsSource: true)
    let movedID = try #require(store.pasteGoalClipboard(toWeekContaining: nextWeek))
    #expect(movedID == goalID)
    #expect(!store.hasGoalClipboard)
    var moved = try #require(store.goals.first(where: { $0.id == goalID }))
    #expect(Calendar.current.isDate(moved.startDate, inSameDayAs: nextWeek))

    store.moveGoalToNextWeek(id: goalID)
    moved = try #require(store.goals.first(where: { $0.id == goalID }))
    let followingWeek = try #require(Calendar.current.date(byAdding: .day, value: 14, to: start))
    #expect(Calendar.current.isDate(moved.startDate, inSameDayAs: followingWeek))
}

@MainActor
@Test func copiedTaskIsANamedSingleDayCardWhilePoolAssignmentsStayShared() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskClipboard-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let firstDay = Calendar.current.startOfDay(for: .now)
    let secondDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: firstDay))
    let goalID = store.addGoal(title: "共享任务来源", outcome: "", endDate: secondDay)
    let taskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    store.assignTask(goalID: goalID, taskID: taskID, to: firstDay)
    store.assignTask(goalID: goalID, taskID: taskID, to: secondDay)

    var source = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID })
    )
    source.title = "更新后的共享任务"
    store.updateTask(source, goalID: goalID)
    #expect(store.tasks(on: firstDay).contains { $0.task.id == taskID && $0.task.title == source.title })
    #expect(store.tasks(on: secondDay).contains { $0.task.id == taskID && $0.task.title == source.title })

    store.toggleTask(goalID: goalID, taskID: taskID)
    #expect(!store.tasks(on: firstDay).contains { $0.task.id == taskID })
    #expect(!store.tasks(on: secondDay).contains { $0.task.id == taskID })
    #expect(store.archivedTasks.first(where: { $0.task.id == taskID })?.task.status == .completed)
    store.toggleTask(goalID: goalID, taskID: taskID)

    store.highlightedTask = TaskReference(goalID: goalID, taskID: taskID)
    store.copyHighlightedTask()
    let copiedID = try #require(
        store.pasteTaskClipboard(
            on: firstDay,
            after: TaskReference(goalID: goalID, taskID: taskID)
        )
    )
    let copied = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == copiedID })
    )
    #expect(copied.title == "更新后的共享任务 副本")
    #expect(copied.assignedDates.isEmpty)
    #expect(Calendar.current.isDate(try #require(copied.plannedDate), inSameDayAs: firstDay))
    let orderedTaskIDs = store.tasks(on: firstDay).map(\.task.id)
    #expect(orderedTaskIDs.firstIndex(of: copiedID) == orderedTaskIDs.firstIndex(of: taskID).map { $0 + 1 })

    store.toggleTask(goalID: goalID, taskID: copiedID)
    #expect(store.archivedTasks.first(where: { $0.task.id == copiedID })?.task.status == .completed)
    #expect(!store.tasks(on: secondDay).contains { $0.task.id == copiedID })
    #expect(store.tasks(on: secondDay).first(where: { $0.task.id == taskID })?.task.status == .planned)
}

@MainActor
@Test func weeklyGoalSubtargetsDriveTaskBasedProgressAndCanBeCopiedForward() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowGoalCopy-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let start = Calendar.current.startOfDay(for: .now)
    let end = try #require(Calendar.current.date(byAdding: .day, value: 6, to: start))
    let goalID = store.addGoal(title: "发布版本", outcome: "完成交付", startDate: start, endDate: end)
    let primaryTaskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    let first = store.addSubtask(goalID: goalID, taskID: primaryTaskID, title: "完成开发")
    _ = store.addSubtask(goalID: goalID, taskID: primaryTaskID, title: "完成测试")
    #expect(store.goals.first(where: { $0.id == goalID })?.progress == 0)
    store.toggleSubtask(goalID: goalID, taskID: primaryTaskID, subtaskID: first)

    let updated = try #require(store.goals.first(where: { $0.id == goalID }))
    #expect(updated.subgoals.map(\.title) == ["完成开发", "完成测试"])
    #expect(updated.progress == 0.5)

    let duplicateID = try #require(store.duplicateGoal(id: goalID))
    let duplicate = try #require(store.goals.first(where: { $0.id == duplicateID }))
    #expect(duplicate.title == "发布版本 副本")
    #expect(duplicate.subgoals.count == 2)

    let nextWeekID = try #require(store.addGoalToNextWeek(id: goalID))
    let nextWeek = try #require(store.goals.first(where: { $0.id == nextWeekID }))
    let expectedStart = try #require(Calendar.current.date(byAdding: .day, value: 7, to: start))
    #expect(Calendar.current.isDate(nextWeek.startDate, inSameDayAs: expectedStart))
    #expect(nextWeek.title == "发布版本")
}

@MainActor
@Test func blankNewWeeklyGoalDraftIsNotKept() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBlankGoalDraft-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)
    let goalID = store.addGoal(
        title: "",
        outcome: "",
        endDate: .now,
        persistImmediately: false
    )

    #expect(store.goals.contains(where: { $0.id == goalID }))
    #expect(!WeekflowStore(storage: storage).goals.contains(where: { $0.id == goalID }))
    store.discardGoalDraft(id: goalID)
    #expect(!store.goals.contains(where: { $0.id == goalID }))
    #expect(!WeekflowStore(storage: storage).goals.contains(where: { $0.id == goalID }))
}

@MainActor
@Test func weeklyGoalPrimaryDetailRecordSynchronizesEditableGoalFields() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowGoalDetail-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let startDate = Calendar.current.startOfDay(for: Date.now)
    let endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
    let goalID = store.addGoal(
        title: "完成周目标",
        outcome: "原始说明",
        startDate: startDate,
        endDate: endDate,
        channelID: "work"
    )
    let taskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    var task = try #require(store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID }))
    task.title = "更新后的周目标"
    task.description = "更新后的说明"
    task.channelID = "research"
    task.dueDate = Calendar.current.date(byAdding: .day, value: 10, to: startDate)
    store.updateTask(task, goalID: goalID)

    let updated = try #require(store.goals.first(where: { $0.id == goalID }))
    #expect(updated.title == task.title)
    #expect(updated.outcome == task.description)
    #expect(updated.channelID == task.channelID)
    #expect(updated.endDate == task.dueDate)

    store.toggleTask(goalID: goalID, taskID: taskID)
    #expect(store.goals.first(where: { $0.id == goalID })?.completedAt != nil)
}

@MainActor
@Test func emptyWeeklyReviewDoesNotReserveAPlaceholderRegion() throws {
    let source = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyReviewView.swift"
        ),
        encoding: .utf8
    )
    #expect(!source.contains("没有可回顾的周目标"))
    #expect(!source.contains("ContentUnavailableView"))
}

@MainActor
@Test func weeklyReviewUsesTheExactWeeklyPlanningGoalCollection() throws {
    let reviewSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyReviewView.swift"
        ),
        encoding: .utf8
    )
    let snapshotSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/WeeklyReviewSnapshot.swift"
        ),
        encoding: .utf8
    )

    #expect(reviewSource.contains("goals: store.activeGoals"))
    #expect(snapshotSource.contains("let weeklyGoals = allGoals"))
    #expect(!snapshotSource.contains("goal.startDate < end && goal.endDate >= start"))
}

@MainActor
@Test func weeklyPlanningPoolUsesOneDraggableCardPerWeeklySubgoal() throws {
    let weeklySource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )
    let storeSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Stores/WeekflowStore.swift"
        ),
        encoding: .utf8
    )
    let calendarSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/TaskCardPopovers.swift"
        ),
        encoding: .utf8
    )
    let controlMenuSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Support/TaskControlMenuPresenter.swift"
        ),
        encoding: .utf8
    )

    #expect(weeklySource.contains("store.weeklyPlanningPoolEntries"))
    #expect(weeklySource.contains("entries: store.weeklyPlanningTasks(on: date)"))
    #expect(storeSource.contains("if goal.subgoals.isEmpty"))
    #expect(storeSource.contains("return primaryTask.map { [(goal, $0)] } ?? []"))
    #expect(storeSource.contains("return goal.subgoals.compactMap { subgoal in"))
    #expect(weeklySource.contains("Text(subgoalTitle)"))
    #expect(weeklySource.contains("Text(relationshipTitle)"))
    #expect(weeklySource.contains("entry.task.subgoalID == nil ? \" \" : entry.goal.title"))
    #expect(weeklySource.contains("Text(assignmentActionLabel)"))
    #expect(!weeklySource.contains("已选 \\(selected.count) 天"))
    #expect(weeklySource.contains(".joined(separator: \"、\")"))
    #expect(weeklySource.contains(".truncationMode(.tail)"))
    #expect(weeklySource.contains("WeeklyTaskPoolDayPicker("))
    #expect(weeklySource.contains("selectedDates: entry.task.assignedDates"))
    #expect(weeklySource.contains("toggle: toggleAssignment"))
    #expect(weeklySource.contains("TaskControlMenuAnchor("))
    #expect(weeklySource.contains("horizontalOffset: -WeekflowLayout.taskDurationMenuPointerWidth"))
    #expect(weeklySource.contains("pointerCenterX: WeekflowLayout.taskDurationMenuPointerWidth * 1.5"))
    #expect(weeklySource.contains("ForEach(dates, id: \\.self) { date in"))
    #expect(weeklySource.contains("WeeklyTaskPoolDayRow("))
    #expect(weeklySource.contains("leadingText: \"不设置\""))
    #expect(weeklySource.contains(".frame(width: 38, alignment: .leading)"))
    #expect(weeklySource.contains(".frame(width: 58, alignment: .leading)"))
    #expect(weeklySource.contains("Image(systemName: \"checkmark\")"))
    #expect(weeklySource.contains("clear: clearAssignments"))
    #expect(weeklySource.contains(".foregroundStyle(WeekflowPalette.objective)"))
    #expect(weeklySource.contains("isHovering || selected ? WeekflowPalette.surfaceHover : .clear"))
    #expect(!weeklySource.contains("selected ? WeekflowPalette.objective.opacity(0.10) : .clear"))
    #expect(weeklySource.contains("showsAssignmentPicker || isAssignmentButtonHovering"))
    #expect(!weeklySource.contains("tint.opacity(showsAssignmentPicker"))
    #expect(weeklySource.contains(".padding(.trailing, 6)"))
    #expect(weeklySource.contains(".frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)"))
    #expect(!weeklySource.contains(".popover(isPresented: $showsAssignmentPicker"))
    #expect(controlMenuSource.contains("TaskDurationMenuPointer()"))
    #expect(controlMenuSource.contains("requestedPointerCenterX ?? anchorOnScreen.midX - originX"))
    #expect(controlMenuSource.contains("styleMask: [.borderless, .nonactivatingPanel]"))
    #expect(controlMenuSource.contains("installOutsideClickMonitor"))
    #expect(controlMenuSource.contains("installScrollTracking"))
    #expect(controlMenuSource.contains("repositionPanel()"))
    #expect(controlMenuSource.contains("NSView.boundsDidChangeNotification"))
    #expect(controlMenuSource.contains("clipView.postsBoundsChangedNotifications = true"))
    #expect(controlMenuSource.contains("ancestorClipViews(of: anchor)"))
    #expect(controlMenuSource.contains("matching: .scrollWheel"))
    #expect(controlMenuSource.contains("isFullyVisible("))
    #expect(controlMenuSource.contains("panelFrame.minY >= clipOnScreen.minY"))
    #expect(controlMenuSource.contains("panelFrame.maxY <= clipOnScreen.maxY"))
    #expect(controlMenuSource.contains("scrollToMakeRoomBelow"))
    #expect(controlMenuSource.contains("private var hasAdjustedScrollForPresentation = false"))
    #expect(controlMenuSource.contains("if !hasAdjustedScrollForPresentation"))
    #expect(controlMenuSource.contains("hasAdjustedScrollForPresentation = true"))
    #expect(controlMenuSource.contains("hasAdjustedScrollForPresentation = false"))
    #expect(
        controlMenuSource.components(
            separatedBy: "if scrollToMakeRoomBelow(anchor:"
        ).count - 1 == 1
    )
    #expect(controlMenuSource.contains("let originX = anchorOnScreen.minX + horizontalOffset"))
    #expect(controlMenuSource.contains("let originY = anchorOnScreen.minY - panelSize.height - 3"))
    #expect(controlMenuSource.contains("clipView.scroll(to:"))
    #expect(controlMenuSource.contains("event.window !== panel"))
    #expect(weeklySource.contains(".onDrag {"))
    #expect(!weeklySource.contains(".onTapGesture(count: 2, perform: quickAssign)"))
    #expect(!weeklySource.contains("Image(systemName: \"hand.draw\")"))
    #expect(!weeklySource.contains(".help(\"拖到下方某一天，或双击自动安排；源任务会继续保留在任务池\")"))
    #expect(calendarSource.contains("let selectedDates: [Date]"))
}

@MainActor
@Test func dailyPlanningPoolAndWeeklyAssignmentsUseOnlyWeeklyGoalWork() throws {
    let dailySource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/DailyPlanningViews.swift"
        ),
        encoding: .utf8
    )
    let boardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )

    #expect(dailySource.contains("store.weeklyPlanningPoolEntries"))
    #expect(boardSource.contains("entries: store.weeklyPlanningTasks(on: date)"))
    #expect(!boardSource.contains("entries: store.tasks(on: date)"))
}

@MainActor
@Test func weeklyGoalEstimatedTotalSumsItsSubgoalEstimates() throws {
    let boardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )

    #expect(boardSource.contains("goal.subgoals.reduce(0) { total, subgoal in"))
    #expect(boardSource.contains("total + estimatedMinutes(for: subgoal)"))
    #expect(boardSource.contains("\"预计 \\(TaskTimeDisplay.estimated(minutes: totalEstimatedMinutes))\""))
    #expect(!boardSource.contains("预计合计"))
}

@MainActor
@Test func weeklyDailyAssignmentCardShowsOnlyItsWeeklyGoalOnTheSecondLine() throws {
    let boardSource = try String(
        contentsOf: weeklyRefinementPackageRoot.appendingPathComponent(
            "Sources/Weekflow/Views/WeeklyBoardView.swift"
        ),
        encoding: .utf8
    )

    #expect(boardSource.components(separatedBy: "Text(entry.goal.title)").count - 1 >= 2)
    #expect(!boardSource.contains("return \"\\(entry.goal.title) / \\(subgoal.title)\""))
}

@MainActor
@Test func deletingAPlanningPoolCardDeletesAndRestoresItsSubgoalWithTheGoal() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPlanningPoolLifecycle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let goalID = store.addGoal(title: "完成发布", outcome: "", endDate: .now, channelID: "work")
    let primaryTaskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    let subgoalID = store.addSubtask(goalID: goalID, taskID: primaryTaskID, title: "完成验收")
    let linkedTaskID = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.subgoalID == subgoalID })?.id
    )
    var goalWithDuplicate = try #require(store.goals.first(where: { $0.id == goalID }))
    goalWithDuplicate.tasks.append(
        WeekTask(
            title: "重复验收任务",
            estimatedMinutes: 30,
            subgoalID: subgoalID,
            channelID: goalWithDuplicate.channelID,
            sourceType: .weeklyObjective
        )
    )
    store.updateGoal(goalWithDuplicate)
    let activeLinkedTasks = try #require(store.goals.first(where: { $0.id == goalID }))
        .tasks.filter { $0.subgoalID == subgoalID && $0.status != .deleted && $0.status != .archived }
    #expect(activeLinkedTasks.count == 1)

    let firstDay = Calendar.current.startOfDay(for: .now)
    let secondDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: firstDay))
    store.assignTask(goalID: goalID, taskID: linkedTaskID, to: firstDay)
    store.assignTask(goalID: goalID, taskID: linkedTaskID, to: secondDay)
    #expect(
        store.goals.first(where: { $0.id == goalID })?
            .tasks.first(where: { $0.id == linkedTaskID })?
            .assignedDates.count == 2
    )

    store.deleteTask(goalID: goalID, taskID: linkedTaskID)
    #expect(store.goals.first(where: { $0.id == goalID })?.subgoals.contains(where: { $0.id == subgoalID }) == false)
    #expect(!store.taskPool.contains { $0.task.id == linkedTaskID })

    store.restoreDeletedTask(goalID: goalID, taskID: linkedTaskID)
    #expect(store.goals.first(where: { $0.id == goalID })?.subgoals.contains(where: { $0.id == subgoalID }) == true)
    #expect(store.tasks(on: .now).contains { $0.task.id == linkedTaskID })
    #expect(!store.taskPool.contains { $0.task.id == linkedTaskID })

    store.archiveGoal(id: goalID)
    #expect(!store.taskPool.contains { $0.task.id == linkedTaskID })
}
