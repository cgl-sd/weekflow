import Testing
import AppKit
import SwiftUI
@testable import Weekflow

@MainActor
@Test func goalProgressTracksCompletedSubgoalsInsteadOfUnrelatedTasks() {
    var goal = WeeklyGoal(title: "测试", outcome: "完成", startDate: .now, endDate: .now)
    goal.tasks = [
        WeekTask(title: "完成", plannedDate: .now, dueDate: nil, estimatedMinutes: 60, status: .completed),
        WeekTask(title: "未完成", plannedDate: .now, dueDate: nil, estimatedMinutes: 60)
    ]
    #expect(goal.progress == 0)
    #expect(goal.completedTaskCount == 1)
    goal.subgoals = [
        GoalSubgoal(title: "已完成目标", isCompleted: true),
        GoalSubgoal(title: "未完成目标")
    ]
    #expect(goal.progress == 0.5)
}

@MainActor
@Test func totalPlannedMinutesAreSummed() {
    var goal = WeeklyGoal(title: "测试", outcome: "完成", startDate: .now, endDate: .now)
    goal.tasks = [WeekTask(title: "A", plannedDate: .now, dueDate: nil, estimatedMinutes: 45), WeekTask(title: "B", plannedDate: .now, dueDate: nil, estimatedMinutes: 75)]
    #expect(goal.plannedMinutes == 120)
}

@MainActor
@Test func demoScheduleIsReadyForBoardAndCalendar() {
    let fixtures = WeekflowDevelopmentFixture.regressionTodaySchedule(referenceDate: .now)
    #expect(fixtures.count == 5)
    #expect(fixtures.allSatisfy { $0.plannedDate != nil && $0.startTime != nil })
    #expect(Set(fixtures.compactMap(\.channelID)).count >= 4)
}

@MainActor
@Test func acceptedVisualGeometryRemainsLocked() {
    #expect(WeekflowLayout.windowWidth == 1_080)
    #expect(WeekflowLayout.windowHeight == 700)
    #expect(WeekflowLayout.sidebarWidth == 210)
    #expect(WeekflowLayout.assistantRailWidth == 48)
    #expect(WeekflowLayout.assistantPanelWidth == 260)
    #expect(WeekflowLayout.boardVisibleDayCount == 3)

    let dailyColumnWidth = WeekflowLayout.threeColumnWidth(
        for: 951,
        columnSpacing: WeekflowLayout.dailyWorkspaceColumnSpacing
    )
    #expect(dailyColumnWidth * 3 == 951)

    let workspaceWidth = WeekflowLayout.windowWidth
        - WeekflowLayout.sidebarWidth
        - WeekflowLayout.assistantRailWidth
    #expect(workspaceWidth == 822)
    let viewportWidth = workspaceWidth
        - WeekflowLayout.homeBoardLeadingPadding
        - WeekflowLayout.homeBoardTrailingPadding
    let spacing = WeekflowLayout.homeDayColumnSpacing
    let columnWidth = WeekflowLayout.homeDayColumnWidth(
        for: viewportWidth,
        columnSpacing: spacing
    )
    let firstDayLeadingEdge = WeekflowLayout.sidebarWidth
        + WeekflowLayout.homeBoardLeadingPadding
    let secondDayTrailingEdge = firstDayLeadingEdge + columnWidth * 2 + spacing
    let thirdDayLeadingEdge = firstDayLeadingEdge + (columnWidth + spacing) * 2
    let assistantPanelLeadingEdge = WeekflowLayout.windowWidth
        - WeekflowLayout.assistantRailWidth
        - WeekflowLayout.assistantPanelWidth

    #expect(assistantPanelLeadingEdge >= secondDayTrailingEdge)
    #expect(assistantPanelLeadingEdge <= thirdDayLeadingEdge)
}

@MainActor
@Test func framedSurfacesUseTheReducedGlobalCornerScale() {
    #expect(WeekflowCornerRadius.resolved(14) == 8)
    #expect(WeekflowCornerRadius.resolved(10) == 6)
    #expect(WeekflowCornerRadius.resolved(5) == 3)
    #expect(WeekflowCornerRadius.resolved(1) == 1)
    #expect(WeekflowCornerRadius.resolved(0) == 0)
}

@MainActor
@Test func focusPresetsUseTheRequiredSixtyMinuteDuration() throws {
    #expect(FocusMode.allCases.map(\.title) == ["禅定", "学习", "休闲"])
    #expect(FocusMode.allCases.allSatisfy { $0.defaultMinutes == 60 })
    let suiteName = "WeekflowFocusDefaults-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(defaults: defaults, notificationScheduler: RecordingFocusNotificationScheduler())
    timer.select(.study)
    #expect(timer.formattedRemaining == "60:00")
}

@MainActor
@Test func focusDurationsPersistAndTimerStatesNotify() throws {
    let suiteName = "WeekflowFocusPersistence-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let notifications = RecordingFocusNotificationScheduler()
    let timer = FocusTimerService(defaults: defaults, notificationScheduler: notifications)

    timer.updateMinutes(45, for: .meditation)
    timer.updateMinutes(90, for: .study)
    timer.updateMinutes(120, for: .leisure)
    let restored = FocusTimerService(defaults: defaults, notificationScheduler: notifications)
    #expect(restored.minutes(for: .meditation) == 45)
    #expect(restored.minutes(for: .study) == 90)
    #expect(restored.minutes(for: .leisure) == 120)

    restored.select(.leisure)
    #expect(restored.formattedRemaining == "02:00:00")
    restored.start()
    #expect(restored.isRunning)
    #expect(restored.hasStarted)
    restored.select(.study)
    #expect(restored.selectedMode == .leisure)
    restored.advance(by: 60)
    restored.pause()
    #expect(!restored.isRunning)
    #expect(restored.hasStarted)
    restored.start()
    restored.advance(by: restored.remainingSeconds)
    #expect(!restored.isRunning)
    #expect(!restored.hasStarted)
    #expect(notifications.permissionRequests == 2)
    #expect(notifications.completions.last?.mode == .leisure)
    #expect(notifications.completions.last?.minutes == 120)
}

@MainActor
@Test func focusTaskLinkWritesElapsedMinutesBackToTask() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowFocusTaskLink-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let initialActualMinutes = entry.task.actualMinutes
    let defaults = try #require(UserDefaults(suiteName: "WeekflowFocusTaskLink-\(UUID().uuidString)"))
    let timer = FocusTimerService(defaults: defaults, notificationScheduler: RecordingFocusNotificationScheduler())
    timer.configureTaskWriter { reference, seconds in
        store.recordFocusSeconds(for: reference, seconds: seconds)
    }
    timer.linkTask(
        TaskReference(goalID: entry.goal.id, taskID: entry.task.id),
        title: entry.task.title,
        estimatedMinutes: 2
    )
    #expect(timer.remainingSeconds == 120)
    timer.start()
    timer.advance(by: 65)
    timer.pause()

    let updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(updated.actualMinutes == initialActualMinutes + 1)
    #expect(updated.changeRecords.last?.source == .timer)
}

@MainActor
@Test func focusViewRendersLargeCountdownWithoutWorkspaceToolbar() throws {
    let suiteName = "WeekflowFocusRender-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(defaults: defaults, notificationScheduler: RecordingFocusNotificationScheduler())
    let view = FocusView(timer: timer)
        .frame(width: 951, height: 676, alignment: .top)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 676))
    try writeSnapshotIfRequested(image, name: "专注模式")
}

@MainActor
@Test func focusWakeReconciliationUsesWallClockTime() throws {
    let defaults = try #require(UserDefaults(suiteName: "WeekflowFocusWake-\(UUID().uuidString)"))
    let timer = FocusTimerService(defaults: defaults, notificationScheduler: RecordingFocusNotificationScheduler())
    timer.updateMinutes(5, for: .meditation)
    let startedAt = Date(timeIntervalSince1970: 50_000)
    timer.start(now: startedAt)
    timer.reconcileAfterInactivity(now: startedAt.addingTimeInterval(90))
    #expect(timer.remainingSeconds == 210)
    #expect(timer.isRunning)
    timer.advance(by: timer.remainingSeconds)
    #expect(!timer.isRunning)
}

@MainActor
@Test func modifiedWorkflowScreensRenderAtReferenceCanvas() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWorkflowTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))

    let visibleDestinations: [AppDestination] = [
        .focus,
        .dailyPlanning,
        .dailyShutdown,
        .weeklyPlanning,
        .weeklyReview,
        .archive
    ]
    for destination in visibleDestinations {
        let image = try renderShell(store: store, destination: destination)
        #expect(image.width == Int(WeekflowLayout.windowWidth * 2))
        #expect(image.height == Int(WeekflowLayout.windowHeight * 2))
    }

    for step in 0...2 {
        let view = DailyPlanningView(
            store: store,
            step: .constant(step),
            showingTaskForm: .constant(false),
            plannedDate: .constant(nil),
            finish: {}
        )
        .frame(width: 951, height: 676, alignment: .topLeading)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size == NSSize(width: 951, height: 676))
        try writeSnapshotIfRequested(image, name: "每日计划-步骤\(step + 1)")
    }
}

@MainActor
@Test func movingTaskToAnotherDayPreservesItsClockTime() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowMoveTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first(where: { $0.task.startTime != nil }))
    let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: .now))
    let originalTime = Calendar.current.dateComponents([.hour, .minute], from: try #require(entry.task.startTime))

    store.moveTask(goalID: entry.goal.id, taskID: entry.task.id, to: tomorrow)

    let moved = try #require(store.tasks(on: tomorrow).first(where: { $0.task.id == entry.task.id })?.task)
    #expect(Calendar.current.dateComponents([.hour, .minute], from: try #require(moved.startTime)) == originalTime)
}

@MainActor
@Test func quickCaptureUsesCurrentGoalWhenComposerGoalIsUnselected() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowQuickCaptureGoal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let currentGoal = try #require(store.selectedGoalID)

    #expect(store.quickCaptureGoalID(preferred: nil) == currentGoal)

    let explicitGoal = UUID()
    store.goals.append(WeeklyGoal(
        id: explicitGoal,
        title: "手动选择的目标",
        outcome: "验证目标优先级",
        startDate: .now,
        endDate: .now
    ))
    #expect(store.quickCaptureGoalID(preferred: explicitGoal) == explicitGoal)
}

@MainActor
@Test func dailyPlanningFutureMoveUsesTheSharedTaskRecord() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDailyPlanningSharedStore-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let goal = try #require(store.activeGoals.first)
    let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)))
    let dayAfterTomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: tomorrow))
    let taskID = try #require(store.addTask(
        to: goal.id,
        title: "每日计划同步测试",
        plannedDate: tomorrow,
        dueDate: nil,
        minutes: 45,
        notes: "",
        milestoneID: nil,
        priority: .must
    ))

    #expect(store.tasks(on: tomorrow).contains { $0.task.id == taskID })
    store.moveTask(goalID: goal.id, taskID: taskID, to: dayAfterTomorrow)
    #expect(!store.tasks(on: tomorrow).contains { $0.task.id == taskID })
    #expect(store.tasks(on: dayAfterTomorrow).contains { $0.task.id == taskID })
    store.toggleTask(goalID: goal.id, taskID: taskID)
    #expect(!store.tasks(on: dayAfterTomorrow).contains { $0.task.id == taskID })
    #expect(store.archivedTasks.first(where: { $0.task.id == taskID })?.task.status == .completed)
}

@MainActor
@Test func dailyShutdownSummaryUsesProgressActualFocusAndChannelTime() {
    let goal = WeeklyGoal(title: "本周交付", outcome: "完成", startDate: .now, endDate: .now)
    let completed = WeekTask(
        title: "完成界面核对",
        plannedDate: .now,
        estimatedMinutes: 45,
        actualMinutes: 30,
        status: .completed,
        channelID: "work"
    )
    let unfinished = WeekTask(
        title: "补充验收说明",
        plannedDate: .now,
        estimatedMinutes: 60,
        channelID: "research"
    )
    let summary = DailyShutdownSummaryBuilder.build(
        entries: [(goal, completed), (goal, unfinished)],
        focusMinutes: [.meditation: 12, .study: 30, .leisure: 5],
        channelTitle: { $0 == "work" ? "工作推进" : "研究整理" }
    )

    #expect(summary.contains("## 今日已经进行的事项"))
    #expect(summary.contains("完成界面核对｜实际时间 00:30｜结果：已完成"))
    #expect(summary.contains("## 今日尚未实施的事项"))
    #expect(summary.contains("- 补充验收说明"))
    #expect(summary.contains("禅定：00:12"))
    #expect(summary.contains("学习：00:30"))
    #expect(summary.contains("休闲：00:05"))
    #expect(summary.contains("总专注时长：00:47"))
    #expect(summary.contains("工作推进：00:30"))
    #expect(!summary.contains("研究整理：00:00"))
}

@MainActor
@Test func dailyShutdownReviewAndSummaryPagesRender() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDailyShutdownRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))

    for phase in 0...1 {
        let view = DailyShutdownView(store: store, initialPhase: phase)
            .frame(width: 951, height: 676, alignment: .topLeading)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size == NSSize(width: 951, height: 676))
        try writeSnapshotIfRequested(image, name: phase == 0 ? "每日收尾-今日回顾" : "每日收尾-总结模板")
    }
}

@MainActor
@Test func sidebarHeaderRemainsPixelStableAcrossReviewScreens() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowSidebarTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))

    let homeImage = try renderSidebar(store: store, selection: .home)
    let comparisonImages = [
        try renderSidebar(store: store, selection: .dailyShutdown),
        try renderSidebar(store: store, selection: .weeklyReview)
    ]
    let crop = CGRect(x: 0, y: 0, width: homeImage.width, height: 90)
    let homeHeader = try #require(homeImage.cropping(to: crop)?.dataProvider?.data)
    for image in comparisonImages {
        let comparisonHeader = try #require(image.cropping(to: crop)?.dataProvider?.data)
        let maximumChannelDelta = zip(homeHeader as Data, comparisonHeader as Data)
            .map { abs(Int($0) - Int($1)) }
            .max() ?? 0
        #expect(maximumChannelDelta <= 1)
    }
}

@MainActor
@Test func sidebarSelectionDoesNotUseCompletionGreen() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowSidebarColorTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))

    for destination in [AppDestination.home, .focus, .dailyPlanning, .weeklyPlanning, .archive] {
        let image = try renderSidebar(store: store, selection: destination)
        #expect(!containsCompletionGreen(image))
    }
}

@MainActor
@Test func completeWindowKeepsSidebarHeaderStableAcrossPlanningAndReview() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowShellTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let home = try renderShell(store: store, destination: .home)
    let dailyPlanning = try renderShell(store: store, destination: .dailyPlanning)
    let weeklyReview = try renderShell(store: store, destination: .weeklyReview)
    let crop = CGRect(x: 0, y: 0, width: 420, height: 110)
    let baseline = try #require(home.cropping(to: crop)?.dataProvider?.data) as Data

    for image in [dailyPlanning, weeklyReview] {
        let comparison = try #require(image.cropping(to: crop)?.dataProvider?.data) as Data
        let maximumChannelDelta = zip(baseline, comparison)
            .map { abs(Int($0) - Int($1)) }
            .max() ?? 0
        #expect(maximumChannelDelta <= 1)
    }
}

@MainActor
@Test func taskCardsRenderWithAndWithoutStartTimes() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskCardTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))

    var goal = WeeklyGoal(
        title: "完成产品原型",
        outcome: "交付可演示版本",
        startDate: .now,
        endDate: .now
    )
    let nineAM = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)
    goal.tasks = [
        WeekTask(
            title: "整理交互说明",
            plannedDate: .now,
            startTime: nineAM,
            estimatedMinutes: 60,
            channelID: "work",
            subtasks: [
                TaskSubtask(title: "核对按钮", completed: true),
                TaskSubtask(title: "补齐状态")
            ]
        ),
        WeekTask(
            title: "检查视觉间距",
            plannedDate: .now,
            estimatedMinutes: 45,
            channelID: "research",
            priority: .should
        )
    ]

    let view = VStack(spacing: 12) {
        SunsamaTaskCard(entry: (goal, goal.tasks[0]), store: store)
        SunsamaTaskCard(entry: (goal, goal.tasks[1]), store: store)
    }
    .padding(12)
    .frame(width: 280, height: 280, alignment: .top)
    .background(WeekflowPalette.appBackground)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 280, height: 280))
    try writeSnapshotIfRequested(image, name: "任务卡-有无开始时间")
}

@MainActor
@Test func taskCardPopoverActionsPersistImmediately() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskPopoverActions-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let originalDate = try #require(entry.task.plannedDate)
    let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: originalDate))

    store.moveTask(goalID: entry.goal.id, taskID: entry.task.id, to: tomorrow)
    var updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(Calendar.current.isDate(try #require(updated.plannedDate), inSameDayAs: tomorrow))

    updated.channelID = "research"
    updated.priority = .should
    updated.startTime = Calendar.current.date(bySettingHour: 10, minute: 15, second: 0, of: tomorrow)
    store.updateTask(updated, goalID: entry.goal.id)
    updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(updated.channelID == "research")
    #expect(updated.priority == .should)
    #expect(Calendar.current.component(.hour, from: try #require(updated.startTime)) == 10)
    #expect(Calendar.current.component(.minute, from: try #require(updated.startTime)) == 15)

    let timerStart = Date(timeIntervalSince1970: 10_000)
    store.startTaskTimer(goalID: entry.goal.id, taskID: entry.task.id, now: timerStart)
    updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(updated.status == .inProgress)
    let elapsedMinutes = store.pauseTaskTimer(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        now: timerStart.addingTimeInterval(125)
    )
    updated = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(elapsedMinutes == 2)
    #expect(updated.actualMinutes == entry.task.actualMinutes + 2)
    #expect(updated.actualSeconds == entry.task.actualSeconds + 125)
    #expect(updated.status == .planned)
    #expect(updated.changeRecords.last?.source == .timer)
    #expect(Set(TaskChannel.defaults.prefix(4).map(\.colorName)).count >= 3)
    #expect(TaskPriority.none.flagSymbol == "flag")
}

@MainActor
@Test func taskCardPopoversRenderAtCompactSizes() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPopoverRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let view = HStack(alignment: .top, spacing: 12) {
        TaskChannelPopover(
            channels: TaskChannel.defaults,
            selectedChannelID: "research",
            select: { _ in },
            manage: {}
        )
        VStack(spacing: 12) {
            TaskDatePopover(selectedDate: .now, moveByDays: { _ in }, moveToDate: { _ in })
            TaskPriorityPopover(selectedPriority: .none, select: { _ in })
            TaskTimerInlinePanel(
                store: store,
                goalID: entry.goal.id,
                taskID: entry.task.id,
                estimatedMinutes: 60
            )
            .frame(width: 210)
        }
    }
    .padding(12)
    .frame(width: 650, height: 680, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 650, height: 680))
    try writeSnapshotIfRequested(image, name: "任务卡弹层组合")
}

@MainActor
@Test func taskDetailSavesOnlyRealFieldChanges() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskDetailChanges-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let original = entry.task

    let noChanges = store.saveEditedTask(original, original: original, goalID: entry.goal.id)
    var stored = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(noChanges.isEmpty)
    #expect(stored.changeRecords.isEmpty)
    #expect(stored.updatedAt == original.updatedAt)

    var renamed = original
    renamed.title = "\(original.title)（已核对）"
    let titleChanges = store.saveEditedTask(renamed, original: original, goalID: entry.goal.id)
    stored = try #require(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.first(where: { $0.id == entry.task.id }))
    #expect(titleChanges.count == 1)
    #expect(titleChanges.first?.field == "标题")
    #expect(stored.changeRecords.count == 1)
    #expect(stored.changeRecords.first?.source == .manual)
}

@MainActor
@Test func taskDetailAggregatesOneEditingSessionIntoOneRecord() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskDetailSession-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let original = entry.task
    let originalRecordCount = original.changeRecords.count

    var renamed = original
    renamed.title = "\(original.title)（本次会话）"
    _ = store.saveEditedTask(
        renamed,
        original: original,
        goalID: entry.goal.id,
        recordChanges: false
    )
    var withNotes = renamed
    withNotes.notes = "一次会话内补充的笔记"
    _ = store.saveEditedTask(
        withNotes,
        original: renamed,
        goalID: entry.goal.id,
        recordChanges: false
    )
    store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "新增子任务")

    var stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(stored.changeRecords.count == originalRecordCount)

    let sessionRecord = store.recordTaskEditingSession(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        original: original
    )
    stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(stored.changeRecords.count == originalRecordCount + 1)
    #expect(sessionRecord?.field == "任务详情")
    #expect(sessionRecord?.newValue.contains("标题") == true)
    #expect(sessionRecord?.newValue.contains("备注") == true)
    #expect(sessionRecord?.newValue.contains("子任务") == true)
}

@MainActor
@Test func taskDetailDefersDiskWritesUntilTheSessionCommit() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDeferredDetailPersistence-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)
    store.synchronousPersistence = true
    store.addGoal(title: "响应测试", outcome: "关闭时统一保存", endDate: .now)
    let goalID = try #require(store.selectedGoalID)
    let taskID = try #require(store.addTask(
        to: goalID,
        title: "原任务",
        plannedDate: .now,
        dueDate: nil,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))
    let original = try #require(store.goals
        .first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }))

    _ = store.addSubtask(
        goalID: goalID,
        taskID: taskID,
        title: "内存中的修改",
        persistImmediately: false
    )
    var reloaded = WeekflowStore(storage: storage)
    var reloadedTask = try #require(reloaded.goals
        .first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }))
    #expect(reloadedTask.subtasks.isEmpty)

    _ = store.recordTaskEditingSession(goalID: goalID, taskID: taskID, original: original)
    reloaded = WeekflowStore(storage: storage)
    reloadedTask = try #require(reloaded.goals
        .first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }))
    #expect(reloadedTask.subtasks.map(\.title) == ["内存中的修改"])
    #expect(reloadedTask.changeRecords.last?.field == "任务详情")
}

@MainActor
@Test func taskDetailCanRenameAndDeleteSubtasksInline() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowInlineSubtask-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "原子任务")
    var stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    let subtaskID = try #require(stored.subtasks.last?.id)

    store.updateSubtaskTitle(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        subtaskID: subtaskID,
        title: "修改后的子任务"
    )
    stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(stored.subtasks.first(where: { $0.id == subtaskID })?.title == "修改后的子任务")

    store.updateSubtaskActualMinutes(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        subtaskID: subtaskID,
        minutes: 45
    )
    store.updateSubtaskPlannedMinutes(
        goalID: entry.goal.id,
        taskID: entry.task.id,
        subtaskID: subtaskID,
        minutes: 75
    )
    stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(stored.subtasks.first(where: { $0.id == subtaskID })?.actualMinutes == 45)
    #expect(stored.subtasks.first(where: { $0.id == subtaskID })?.plannedMinutes == 75)

    store.deleteSubtask(goalID: entry.goal.id, taskID: entry.task.id, subtaskID: subtaskID)
    stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(!stored.subtasks.contains(where: { $0.id == subtaskID }))
}

@MainActor
@Test func taskDetailCanAppendConsecutiveBlankSubtasks() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBlankSubtasks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)

    let firstID = store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "")
    let secondID = store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "")
    let stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))

    #expect(firstID != secondID)
    #expect(stored.subtasks.suffix(2).allSatisfy { $0.title.isEmpty })
}

@MainActor
@Test func taskDetailSubtasksCanBeReorderedAndMovedToTheEnd() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowSubtaskReorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let firstID = store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "第一项")
    let secondID = store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "第二项")
    let thirdID = store.addSubtask(goalID: entry.goal.id, taskID: entry.task.id, title: "第三项")

    store.moveSubtask(goalID: entry.goal.id, taskID: entry.task.id, subtaskID: firstID, to: thirdID)
    var stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(Array(stored.subtasks.suffix(3).map(\.id)) == [secondID, thirdID, firstID])

    store.moveSubtask(goalID: entry.goal.id, taskID: entry.task.id, subtaskID: secondID, to: nil)
    stored = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == entry.task.id }))
    #expect(Array(stored.subtasks.suffix(3).map(\.id)) == [thirdID, firstID, secondID])
}

@MainActor
@Test func deletingASubtaskRestoresFocusToItsPreviousRow() {
    let first = TaskSubtask(title: "第一项")
    let second = TaskSubtask(title: "第二项")
    let third = TaskSubtask(title: "第三项")
    let subtasks = [first, second, third]

    #expect(TaskDetailSubtaskFocusPolicy.targetAfterDeleting(
        subtaskID: third.id,
        from: subtasks
    ) == second.id)
    #expect(TaskDetailSubtaskFocusPolicy.targetAfterDeleting(
        subtaskID: second.id,
        from: subtasks
    ) == first.id)
    #expect(TaskDetailSubtaskFocusPolicy.targetAfterDeleting(
        subtaskID: first.id,
        from: subtasks
    ) == second.id)
    #expect(TaskDetailSubtaskFocusPolicy.targetAfterDeleting(
        subtaskID: first.id,
        from: [first]
    ) == nil)
}

@MainActor
@Test func taskCardsReorderImmediatelyAroundTheHoveredTarget() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskReorder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let original = Array(store.todayTasks.prefix(3))
    let first = try #require(original.first)
    let second = original[1]
    let third = original[2]
    let date = try #require(first.task.plannedDate)

    store.reorderTask(
        goalID: first.goal.id,
        taskID: first.task.id,
        before: third.goal.id,
        targetTaskID: third.task.id,
        on: date,
        persistImmediately: false
    )
    #expect(Array(store.tasks(on: date).prefix(3).map(\.task.id)) == [
        second.task.id, first.task.id, third.task.id
    ])

    store.reorderTask(
        goalID: third.goal.id,
        taskID: third.task.id,
        before: second.goal.id,
        targetTaskID: second.task.id,
        on: date,
        persistImmediately: false
    )
    #expect(Array(store.tasks(on: date).prefix(3).map(\.task.id)) == [
        third.task.id, second.task.id, first.task.id
    ])
}

@MainActor
@Test func taskDetailRendersFlatResponsiveEditorWithoutVisibleScrollerTrack() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskDetailRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)
    let view = TaskDetailView(
        store: store,
        target: TaskDetailTarget(goalID: entry.goal.id, taskID: entry.task.id)
    )
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: WeekflowLayout.taskDetailSheetWidth,
        height: WeekflowLayout.taskDetailSheetHeight
    )
    hostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    hostingView.layoutSubtreeIfNeeded()
    let scrollViews = taskDetailScrollViews(in: hostingView)
    #expect(!scrollViews.isEmpty)
    let editorScrollViews = scrollViews.filter {
        $0.frame.width > 300 && $0.frame.height > 100
    }
    #expect(!editorScrollViews.isEmpty)
    #expect(!editorScrollViews.contains {
        $0.hasVerticalScroller && $0.verticalScroller?.isHidden == false
    })

    let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    let image = NSImage(size: hostingView.bounds.size)
    image.addRepresentation(bitmap)
    #expect(image.size == NSSize(
        width: WeekflowLayout.taskDetailSheetWidth,
        height: WeekflowLayout.taskDetailSheetHeight
    ))
    #expect(WeekflowLayout.taskDetailMinimumWidth < WeekflowLayout.taskDetailSheetWidth)
    #expect(WeekflowLayout.taskDetailMinimumHeight < WeekflowLayout.taskDetailSheetHeight)
    try writeSnapshotIfRequested(image, name: "任务详情")
}

@MainActor
@Test func taskDetailUsesSharedDownwardAnchoredMenus() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let _detail_main = try String(contentsOf: packageRoot
        .appendingPathComponent("Sources/Weekflow/Views/TaskDetailView.swift"), encoding: .utf8)
    let _detail_menus = try String(contentsOf: packageRoot
        .appendingPathComponent("Sources/Weekflow/Views/TaskDetailMenus.swift"), encoding: .utf8)
    let _detail_actions = try String(contentsOf: packageRoot
        .appendingPathComponent("Sources/Weekflow/Views/TaskDetailActions.swift"), encoding: .utf8)
    let _detail_support = try String(contentsOf: packageRoot
        .appendingPathComponent("Sources/Weekflow/Views/TaskDetailSupport.swift"), encoding: .utf8)
    let source = _detail_main + _detail_menus + _detail_actions + _detail_support

    #expect(source.contains("TaskChannelPopover("))
    #expect(source.contains("TaskPriorityPopover("))
    #expect(source.contains("TaskDatePopover("))
    #expect(source.contains("ScrollDurationPopover("))
    #expect(source.contains("ScrollClockTimePopover("))
    #expect(source.contains("title: \"真实时间\""))
    #expect(source.contains("categoryPopoverButton"))
    #expect(source.contains("priority == .none ? \"优先级\""))
    #expect(source.contains("detailMenuAction(\"重复功能\""))
    #expect(source.contains("detailMenuAction(\"建立目标联系\""))
    #expect(source.contains("detailMenuAction(\"复制\""))
    #expect(source.contains("detailMenuAction(\"删除\""))
    #expect(source.contains("Text(\"其他操作\")"))
    #expect(!source.contains("shortcut: \"⌘ D\""))
    #expect(!source.contains("shortcut: \"⌘ ⌫\""))
    #expect(!source.contains("shortcut: \"R\""))
    #expect(source.contains("isAddSubtaskHovered ? \"plus.circle.fill\" : \"plus.circle\""))
    #expect(source.contains("case subtaskActualTime(UUID)"))
    #expect(source.contains("case subtaskEstimatedTime(UUID)"))
    #expect(source.contains("updateSubtaskActualMinutes"))
    #expect(source.contains("updateSubtaskPlannedMinutes"))
    #expect(source.contains("width: WeekflowLayout.taskDetailSheetWidth"))
    #expect(source.contains("height: WeekflowLayout.taskDetailSheetHeight"))
    #expect(source.contains("subtaskTimeValues(subtask)"))
    #expect(source.contains("TaskDetailSubtaskTextField"))
    #expect(source.contains("onDeleteAtStart"))
    #expect(source.contains("store.deleteSubtask"))
    #expect(source.contains("ScrollViewReader"))
    #expect(source.contains("subtaskRevealToken"))
    #expect(source.contains("appendEmptySubtask(entry)"))
    #expect(source.contains("onSubmit: { appendEmptySubtask(entry) }"))
    #expect(source.contains("title: \"\""))
    #expect(source.contains("finishEditingSession"))
    #expect(source.contains("closeResponsively(entry)"))
    #expect(source.contains("isClosing = true"))
    #expect(source.contains("DispatchQueue.main.async"))
    #expect(source.contains("recordChanges: false"))
    #expect(source.contains("persistImmediately: false"))
    #expect(source.contains(".onTapGesture { activeMenu = nil }"))
    #expect(source.contains(".onChange(of: menuDismissToken)"))
    #expect(source.contains("TaskPopoverInteractiveHighlight"))
    #expect(source.contains("TaskDetailMenuAnchorPreferenceKey"))
    #expect(source.contains("TaskDurationMenuPointer"))
    #expect(source.contains("anchorFrame.maxY"))
    #expect(source.contains(".font(.system(size: 22, weight: .regular))"))
    #expect(source.contains(".fixedSize(horizontal: true, vertical: false)"))
    #expect(source.contains("focusRequest: focusedSubtaskID == subtask.id ? subtaskRevealToken : nil"))
    #expect(source.contains("deleteSubtaskAndRestoreFocus"))
    #expect(source.contains("WeekflowLayout.taskDetailChannelMenuWidth"))
    #expect(source.contains("WeekflowLayout.taskDetailPriorityMenuWidth"))
    #expect(source.contains("WeekflowLayout.taskDetailDateMenuWidth"))
    #expect(!source.contains("ViewThatFits(in: .horizontal)"))
    #expect(!source.contains("detailsExpanded"))
    #expect(!source.contains("Button(\"添加\")"))
    #expect(!source.contains(".popover("))
    #expect(!source.contains("private func propertyMenu"))
    #expect(!source.contains("toggleDetailTimer"))
    #expect(!source.contains("\"展开\""))
    #expect(!source.contains("completionTree"))
    #expect(!source.contains("Text(\"完成情况\")"))
    #expect(!source.contains("notesEditor"))
    #expect(!source.contains("TextField(\"任务笔记...\""))
    #expect(!source.contains("isExpandedPresentation"))
    #expect(!source.contains("guard !trimmedTitle.isEmpty"))
    #expect(!source.contains("task.completionCredits.filter"))
    #expect(WeekflowLayout.taskDetailChannelMenuWidth < WeekflowLayout.taskDetailAttributeMenuWidth)
    #expect(WeekflowLayout.taskDetailPriorityMenuWidth < WeekflowLayout.taskDetailAttributeMenuWidth)
    #expect(WeekflowLayout.taskDetailDateMenuWidth < WeekflowLayout.taskDetailAttributeMenuWidth)
}

@MainActor
@Test func buttonsActivateAcrossTheirCompleteHighlightedBounds() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let cursorSource = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Support/PointingHandCursor.swift"),
        encoding: .utf8
    )
    let detailSource = try ["TaskDetailSupport.swift", "TaskDetailView.swift", "TaskDetailMenus.swift", "TaskDetailActions.swift", "ShortcutHelpView.swift"]
            .map { try String(contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/\($0)"), encoding: .utf8) }
            .joined(separator: "\n")

    #expect(cursorSource.contains("label\n                .contentShape(Rectangle())"))
    #expect(detailSource.contains(".frame(width: 30, height: 42)\n                    .contentShape(Rectangle())"))
    #expect(detailSource.contains(".frame(width: WeekflowLayout.taskDetailTimeColumnWidth)\n            .frame(minHeight: 38)\n            .contentShape(Rectangle())"))
}

@MainActor
@Test func taskDetailUsesAControlledBackdropAndSizedModalInsteadOfSystemSheet() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/ContentView.swift"),
        encoding: .utf8
    )

    #expect(source.contains("WeekflowPalette.taskDetailBackdrop"))
    #expect(source.contains("taskDetailMenuDismissToken += 1"))
    #expect(source.contains("menuDismissToken: taskDetailMenuDismissToken"))
    #expect(source.contains("TaskDetailView("))
    #expect(source.contains("onClose: closeTaskDetail"))
    #expect(source.contains("WeekflowLayout.taskDetailCornerRadius"))
    #expect(!source.contains(".sheet(item: $presentedTask)"))
    #expect(WeekflowLayout.taskDetailSheetWidth == 700)
    #expect(WeekflowLayout.taskDetailSheetHeight == 650)
    #expect(!source.contains("taskDetailExpandedWidth"))
}

@MainActor
@Test func taskDetailMoreActionsDuplicateRepeatAndMoveWithoutLosingSourceData() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTaskDetailActions-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.activeTasks.first)
    var original = entry.task
    original.actualMinutes = 45
    original.status = .completed
    original.subtasks = [
        TaskSubtask(title: "已核对", completed: true, plannedMinutes: 30, actualMinutes: 20)
    ]
    store.updateTask(original, goalID: entry.goal.id)

    let copyID = try #require(store.duplicateTask(goalID: entry.goal.id, taskID: entry.task.id))
    var copy = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == copyID }))
    #expect(copy.title.hasSuffix("副本"))
    #expect(copy.actualMinutes == 0)
    #expect(copy.status == .planned)
    #expect(copy.subtasks.first?.title == "已核对")
    #expect(copy.subtasks.first?.completed == false)
    #expect(copy.subtasks.first?.plannedMinutes == 30)

    store.setTaskRecurrence(
        goalID: entry.goal.id,
        taskID: copyID,
        rule: RecurringRule(frequency: .weekly)
    )
    copy = try #require(store.goals
        .first(where: { $0.id == entry.goal.id })?
        .tasks.first(where: { $0.id == copyID }))
    #expect(copy.recurringRule?.frequency == .weekly)
    #expect(copy.changeRecords.last?.field == "重复")

    store.addGoal(title: "关联目标", outcome: "验证目标联系", endDate: .now)
    let destinationGoalID = try #require(store.selectedGoalID)
    #expect(store.moveTask(goalID: entry.goal.id, taskID: copyID, toGoalID: destinationGoalID))
    #expect(store.goals.first(where: { $0.id == entry.goal.id })?.tasks.contains(where: { $0.id == copyID }) == false)
    #expect(store.goals.first(where: { $0.id == destinationGoalID })?.tasks.contains(where: { $0.id == copyID }) == true)
}

@MainActor
private func taskDetailScrollViews(in view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView {
        result.append(scrollView)
    }
    for child in view.subviews {
        result.append(contentsOf: taskDetailScrollViews(in: child))
    }
    return result
}

@MainActor
@Test func weekTaskDecodesLegacyDataWithoutChangeRecords() throws {
    let task = WeekTask(title: "兼容旧数据", plannedDate: .now, estimatedMinutes: 30)
    let encoded = try JSONEncoder().encode(task)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "changeRecords")
    object.removeValue(forKey: "executionWeekStart")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(WeekTask.self, from: legacyData)
    #expect(decoded.changeRecords.isEmpty)
    #expect(decoded.executionWeekStart == nil)
    #expect(decoded.title == task.title)
}

@MainActor
@Test func weeklyGoalDecodesLegacyDataWithoutSubgoals() throws {
    let goal = WeeklyGoal(title: "旧周目标", outcome: "保持兼容", startDate: .now, endDate: .now)
    let encoded = try JSONEncoder().encode(goal)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "subgoals")
    object.removeValue(forKey: "channelID")
    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(WeeklyGoal.self, from: legacyData)
    #expect(decoded.subgoals.isEmpty)
    #expect(decoded.channelID == nil)
    #expect(decoded.title == goal.title)
}

@MainActor
@Test func weeklySubgoalCreatesAPathLinkedTaskAndSharesDailyAssignment() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWeeklySubgoal-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let goal = try #require(store.activeGoals.first)
    let subgoalID = try #require(store.addSubgoal(
        to: goal.id,
        title: "完成任务卡片",
        detail: "补齐交互状态",
        createTask: true
    ))
    let updatedGoal = try #require(store.goals.first(where: { $0.id == goal.id }))
    #expect(updatedGoal.subgoals.contains { $0.id == subgoalID })
    let linkedTask = try #require(updatedGoal.tasks.first(where: { $0.subgoalID == subgoalID }))
    #expect(linkedTask.isUnassigned)
    #expect(updatedGoal.subgoals.first(where: { $0.id == subgoalID })?.channelID == nil)
    #expect(linkedTask.channelID == updatedGoal.channelID)

    let targetDate = Calendar.current.startOfDay(for: .now)
    store.assignTask(goalID: goal.id, taskID: linkedTask.id, to: targetDate)
    #expect(store.tasks(on: targetDate).contains { $0.task.id == linkedTask.id })
    store.toggleSubgoal(goalID: goal.id, subgoalID: subgoalID)
    #expect(store.goals.first(where: { $0.id == goal.id })?.subgoals.first(where: { $0.id == subgoalID })?.isCompleted == true)
}

@MainActor
@Test func weeklyPlanningRendersGoalTreeTaskPoolAndDailyAssignment() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWeeklyPlanningRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let goal = try #require(store.activeGoals.first)
    _ = store.addSubgoal(to: goal.id, title: "视觉验收子目标", createTask: true)
    let view = WeeklyBoardView(store: store, presentedTask: .constant(nil), usesScrollContainer: false)
        .frame(width: 951, height: 900, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 900))
    try writeSnapshotIfRequested(image, name: "每周计划")
}

@MainActor
@Test func weeklyPlanningRelationshipMapRendersTheSameGoalTaskAndDayData() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWeeklyRelationshipMap-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let referenceDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 22, hour: 12))
    )
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: referenceDate
    )
    let goal = try #require(store.activeGoals.first)
    let subgoalID = try #require(store.addSubgoal(
        to: goal.id,
        title: "完成关系图交互",
        detail: "连接周目标、任务池与每日分配",
        createTask: true
    ))
    let secondSubgoalID = try #require(store.addSubgoal(
        to: goal.id,
        title: "校验共享日期节点",
        detail: "允许多条分配关系交叉",
        createTask: true
    ))
    let updatedGoal = try #require(store.goals.first { $0.id == goal.id })
    let task = try #require(updatedGoal.tasks.first { $0.subgoalID == subgoalID })
    let secondTask = try #require(updatedGoal.tasks.first { $0.subgoalID == secondSubgoalID })
    let monday = WeeklyDateNavigation.weekStart(for: referenceDate)
    let friday = try #require(Calendar.current.date(byAdding: .day, value: 4, to: monday))
    store.assignTask(goalID: goal.id, taskID: task.id, to: referenceDate)
    store.assignTask(goalID: goal.id, taskID: task.id, to: friday)
    store.assignTask(goalID: goal.id, taskID: secondTask.id, to: monday)
    store.assignTask(goalID: goal.id, taskID: secondTask.id, to: referenceDate)
    #expect(store.weeklyPlanningPoolEntries.count == 2)
    #expect(store.weeklyPlanningTasks(on: referenceDate).count == 2)

    let view = WeeklyBoardView(
        store: store,
        presentedTask: .constant(nil),
        usesScrollContainer: false,
        referenceDate: referenceDate,
        presentation: .constant(.relationships)
    )
    .frame(width: 951, height: 900, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 900))
    try writeSnapshotIfRequested(image, name: "每周计划-关系图")
}

@MainActor
@Test func weeklyGoalSubgoalsStaySynchronizedWithTaskPoolEntries() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowSubgoalPoolSync-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let first = GoalSubgoal(title: "整理研究材料", detail: "完成资料归档")
    let second = GoalSubgoal(title: "准备周会", detail: "输出汇报提纲")
    store.addGoal(
        title: "完成本周研究推进",
        outcome: "形成可汇报成果",
        endDate: .now,
        subgoals: [first, second]
    )

    var goal = try #require(store.selectedGoal)
    let linkedTasks = goal.tasks.filter { $0.subgoalID != nil && $0.status != .deleted }
    #expect(linkedTasks.count == 2)
    #expect(store.taskPool.filter { $0.goal.id == goal.id }.count == 2)
    #expect(linkedTasks.allSatisfy { $0.isUnassigned })

    goal.subgoals[0].title = "整理并标注研究材料"
    goal.subgoals.removeAll { $0.id == second.id }
    store.updateGoal(goal)

    let updated = try #require(store.goals.first { $0.id == goal.id })
    #expect(updated.tasks.first { $0.subgoalID == first.id }?.title == "整理并标注研究材料")
    #expect(updated.tasks.first { $0.subgoalID == second.id }?.status == .deleted)
    #expect(store.taskPool.filter { $0.goal.id == goal.id }.count == 1)
}

@MainActor
@Test func weeklyPlanningPoolKeepsScheduledSubgoalsAndFallsBackToTheGoal() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWeeklyPlanningPoolFallback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))

    let standaloneGoalID = store.addGoal(
        title: "完成独立周目标",
        outcome: "",
        endDate: .now
    )
    let standaloneEntries = store.weeklyPlanningPoolEntries.filter { $0.goal.id == standaloneGoalID }
    #expect(standaloneEntries.count == 1)
    #expect(standaloneEntries.first?.task.subgoalID == nil)
    #expect(standaloneEntries.first?.task.title == "完成独立周目标")

    let first = GoalSubgoal(title: "整理材料")
    let second = GoalSubgoal(title: "完成演示")
    let subgoalGoalID = store.addGoal(
        title: "推进发布",
        outcome: "",
        endDate: .now,
        subgoals: [first, second]
    )
    var scheduledTask = try #require(
        store.goals.first(where: { $0.id == subgoalGoalID })?.tasks.first(where: {
            $0.subgoalID == first.id
        })
    )
    scheduledTask.plannedDate = Calendar.current.startOfDay(for: .now)
    store.updateTask(scheduledTask, goalID: subgoalGoalID)

    let subgoalEntries = store.weeklyPlanningPoolEntries.filter { $0.goal.id == subgoalGoalID }
    #expect(subgoalEntries.count == 2)
    #expect(Set(subgoalEntries.compactMap(\.task.subgoalID)) == Set([first.id, second.id]))

    let targetDate = Calendar.current.startOfDay(for: .now)
    let firstLinkedTaskID = try #require(
        subgoalEntries.first(where: { $0.task.subgoalID == first.id })?.task.id
    )
    store.assignTask(goalID: subgoalGoalID, taskID: firstLinkedTaskID, to: targetDate)
    let unrelatedTaskID = try #require(
        store.addTask(
            to: subgoalGoalID,
            title: "不属于周目标结构的普通任务",
            plannedDate: targetDate,
            dueDate: nil,
            minutes: 30,
            notes: "",
            milestoneID: nil
        )
    )

    let dailyEntries = store.weeklyPlanningTasks(on: targetDate)
    #expect(dailyEntries.contains { $0.task.id == firstLinkedTaskID })
    #expect(!dailyEntries.contains { $0.task.id == unrelatedTaskID })
}

@MainActor
@Test func weeklyReviewMigratesIncompleteTasksIntoARealNextWeekGoal() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWeeklyReviewMigration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    var goal = try #require(store.activeGoals.first)
    let today = Calendar.current.startOfDay(for: .now)
    let completed = WeekTask(title: "已完成任务", plannedDate: today, estimatedMinutes: 30, status: .completed)
    let unfinished = WeekTask(title: "继续任务", plannedDate: today, estimatedMinutes: 60)
    goal.tasks = [completed, unfinished]
    store.updateGoal(goal)

    let nextGoalID = try #require(store.continueGoalToNextWeek(id: goal.id, now: today))
    let archivedGoal = try #require(store.goals.first(where: { $0.id == goal.id }))
    let nextGoal = try #require(store.goals.first(where: { $0.id == nextGoalID }))
    #expect(archivedGoal.isArchived)
    #expect(archivedGoal.tasks.map(\.id) == [completed.id])
    #expect(nextGoal.carriedFromGoalID == goal.id)
    #expect(nextGoal.tasks.map(\.id) == [unfinished.id])
    #expect(nextGoal.tasks.first?.rolloverCount == unfinished.rolloverCount + 1)
    let expectedDate = try #require(Calendar.current.date(byAdding: .day, value: 7, to: today))
    #expect(Calendar.current.isDate(try #require(nextGoal.tasks.first?.plannedDate), inSameDayAs: expectedDate))

    store.moveIncompleteTasksToPool(goalID: nextGoalID)
    #expect(store.taskPool.contains { $0.task.id == unfinished.id })
}

@MainActor
@Test func weeklyReviewRendersGoalProgressSubgoalsAndActions() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowWeeklyReviewRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    var goal = try #require(store.activeGoals.first)
    goal.subgoals = [GoalSubgoal(title: "回顾子目标")]
    store.updateGoal(goal)
    let view = WeeklyReviewView(store: store, usesScrollContainer: false)
        .frame(width: 951, height: 900, alignment: .topLeading)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 900))
    try writeSnapshotIfRequested(image, name: "每周回顾")
}

@MainActor
@Test func archiveChannelFilterUsesConfiguredChannelsOnly() {
    #expect(ArchiveChannelFilter.matches(channelID: "work", selectedChannelID: "all"))
    #expect(ArchiveChannelFilter.matches(channelID: "work", selectedChannelID: "work"))
    #expect(!ArchiveChannelFilter.matches(channelID: "research", selectedChannelID: "work"))
}

@MainActor
@Test func archivedAndDeletedGoalsRemainSeparateAndRecoverable() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowGoalLifecycle-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let archivedID = try #require(store.activeGoals.first?.id)
    let deletedID = store.addGoal(title: "待删除目标", outcome: "", endDate: .now)

    store.archiveGoal(id: archivedID)
    store.deleteGoal(id: deletedID)

    #expect(store.archivedGoals.map(\.id).contains(archivedID))
    #expect(!store.archivedGoals.map(\.id).contains(deletedID))
    #expect(store.deletedGoals.map(\.id).contains(deletedID))
    #expect(!store.deletedGoals.map(\.id).contains(archivedID))

    store.restoreDeletedGoal(id: deletedID)
    #expect(store.activeGoals.map(\.id).contains(deletedID))
    #expect(!store.deletedGoals.map(\.id).contains(deletedID))
}

@MainActor
@Test func archiveRendersFilteredCardsAndFullScreenWithoutAssistantRail() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowArchiveRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    var goal = try #require(store.activeGoals.first)
    var task = try #require(goal.tasks.first)
    task.channelID = "work"
    store.updateTask(task, goalID: goal.id)
    store.archiveTask(goalID: goal.id, taskID: task.id)
    goal = try #require(store.goals.first(where: { $0.id == goal.id }))
    goal.channelID = "work"
    store.updateGoal(goal)
    store.archiveGoal(id: goal.id)

    let archiveView = ArchiveSummaryView(
        store: store,
        selectedChannelID: "work",
        usesScrollContainer: false
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    let renderer = ImageRenderer(content: archiveView)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 676))
    try writeSnapshotIfRequested(image, name: "归档内容")

    let shell = try renderShell(store: store, destination: .archive)
    #expect(shell.width == Int(WeekflowLayout.windowWidth * 2))
    #expect(shell.height == Int(WeekflowLayout.windowHeight * 2))

    store.restoreTask(goalID: goal.id, taskID: task.id)
    #expect(store.activeGoals.contains { $0.id == goal.id })
    #expect(store.todayTasks.contains { $0.task.id == task.id })
}

@MainActor
@Test func assistantOverlayMovesToolbarActionsInsteadOfResizingBoard() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowOverlayTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let closed = try renderShell(store: store, destination: .home, assistantPanelPresented: false)
    let expanded = try renderShell(store: store, destination: .home, assistantPanelPresented: true)
    let leftToolbarCrop = CGRect(x: 420, y: 0, width: 600, height: 90)
    let closedLeft = try #require(closed.cropping(to: leftToolbarCrop)?.dataProvider?.data) as Data
    let expandedLeft = try #require(expanded.cropping(to: leftToolbarCrop)?.dataProvider?.data) as Data
    let leftMaximumDelta = zip(closedLeft, expandedLeft)
        .map { abs(Int($0) - Int($1)) }
        .max() ?? 0
    #expect(leftMaximumDelta <= 1)

    let rightToolbarCrop = CGRect(x: 1_500, y: 0, width: 700, height: 90)
    let closedRight = try #require(closed.cropping(to: rightToolbarCrop)?.dataProvider?.data) as Data
    let expandedRight = try #require(expanded.cropping(to: rightToolbarCrop)?.dataProvider?.data) as Data
    #expect(closedRight != expandedRight)
}

@MainActor
@Test func calendarAssistantPanelReservesSpaceAndShrinksTheCalendarGrid() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCalendarInsetTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let closed = try renderShell(
        store: store,
        destination: .home,
        workspaceView: .monthCalendar,
        assistantPanelPresented: false
    )
    let expanded = try renderShell(
        store: store,
        destination: .home,
        workspaceView: .monthCalendar,
        assistantPanelPresented: true
    )
    let calendarCrop = CGRect(x: 420, y: 120, width: 900, height: 900)
    let closedCalendar = try #require(closed.cropping(to: calendarCrop)?.dataProvider?.data) as Data
    let expandedCalendar = try #require(expanded.cropping(to: calendarCrop)?.dataProvider?.data) as Data
    #expect(closedCalendar != expandedCalendar)
}

@MainActor
@Test func assistantRailTogglesAndRendersEveryPanel() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowAssistantRailTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))

    for panel in AssistantPanel.allCases {
        #expect(AssistantPanel.toggled(panel, current: nil) == panel)
        #expect(AssistantPanel.toggled(panel, current: panel) == nil)
        let other = AssistantPanel.allCases.first { $0 != panel }
        #expect(AssistantPanel.toggled(panel, current: other) == panel)

        let rail = SunsamaAssistantRail(
            store: store,
            activePanel: .constant(panel),
            showingTaskForm: .constant(false)
        )
        .frame(width: WeekflowLayout.assistantRailWidth, height: 676)
        let railRenderer = ImageRenderer(content: rail)
        railRenderer.scale = 2
        let railImage = try #require(railRenderer.nsImage)
        var railRect = CGRect(origin: .zero, size: railImage.size)
        let railCGImage = try #require(railImage.cgImage(forProposedRect: &railRect, context: nil, hints: nil))
        #expect(!containsCompletionGreen(railCGImage))

        let panelPreview = HStack(spacing: 0) {
            SunsamaAssistantPanel(store: store, panel: panel, activeDate: .constant(.now))
                .frame(width: WeekflowLayout.assistantPanelWidth, height: 676)
            Divider()
            rail
        }
        .frame(width: 349, height: 676)
        let previewRenderer = ImageRenderer(content: panelPreview)
        previewRenderer.scale = 2
        let image = try #require(previewRenderer.nsImage)
        #expect(image.size == NSSize(width: 349, height: 676))
        try writeSnapshotIfRequested(image, name: "右栏-\(panel.title)")
    }
}

@MainActor
@Test func referenceCalendarSurfacesRenderAtTargetSizes() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    #expect(store.tasks(on: .now).filter { $0.task.startTime != nil }.count >= 5)

    let calendarModes: [WorkspaceView] = [.dayCalendar, .threeDayCalendar, .weekdaysCalendar, .monthCalendar]
    for mode in calendarModes {
        let view = WorkspaceCalendarView(
            store: store,
            mode: mode,
            selectedDate: .now,
            selectedChannelID: "all"
        )
        .frame(width: 894, height: 676)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 894)
        #expect(image.size.height == 676)
        try writeSnapshotIfRequested(image, name: mode.id.replacingOccurrences(of: " · ", with: "-"))
    }

    let assistant = SunsamaAssistantPanel(
        store: store,
        panel: .calendar,
        activeDate: .constant(.now)
    )
    .frame(width: WeekflowLayout.assistantPanelWidth, height: 676)
    let assistantRenderer = ImageRenderer(content: assistant)
    assistantRenderer.scale = 2
    let assistantImage = try #require(assistantRenderer.nsImage)
    #expect(assistantImage.size.width == WeekflowLayout.assistantPanelWidth)
    #expect(assistantImage.size.height == 676)
    try writeSnapshotIfRequested(assistantImage, name: "右侧日历")

    let dayTasks = SunsamaAssistantPanel(
        store: store,
        panel: .calendar,
        activeDate: .constant(.now),
        calendarPresentation: .constant(.dayTasks)
    )
    .frame(width: WeekflowLayout.assistantPanelWidth, height: 676)
    let dayTasksRenderer = ImageRenderer(content: dayTasks)
    dayTasksRenderer.scale = 2
    let dayTasksImage = try #require(dayTasksRenderer.nsImage)
    #expect(dayTasksImage.size.width == WeekflowLayout.assistantPanelWidth)
    #expect(dayTasksImage.size.height == 676)
    try writeSnapshotIfRequested(dayTasksImage, name: "右侧当天任务")
}

private func writeSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw SnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

@MainActor
private func renderSidebar(store: WeekflowStore, selection: AppDestination) throws -> CGImage {
    let view = AppSidebarView(store: store, destination: .constant(selection))
        .frame(width: 250, height: 676, alignment: .topLeading)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    var rect = CGRect(origin: .zero, size: image.size)
    return try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
}

@MainActor
private func renderShell(
    store: WeekflowStore,
    destination: AppDestination,
    workspaceView: WorkspaceView = .board,
    assistantPanelPresented: Bool = false
) throws -> CGImage {
    let view = ContentView(
        store: store,
        initialDestination: destination,
        initialWorkspaceView: workspaceView,
        initialAssistantPanelPresented: assistantPanelPresented
    )
        .frame(
            width: WeekflowLayout.windowWidth,
            height: WeekflowLayout.windowHeight,
            alignment: .topLeading
        )
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    try writeSnapshotIfRequested(image, name: "完整窗口-\(destination.rawValue)")
    var rect = CGRect(origin: .zero, size: image.size)
    return try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
}

private enum SnapshotError: Error {
    case encodingFailed
}

@MainActor
private final class RecordingFocusNotificationScheduler: FocusNotificationScheduling {
    struct Completion {
        let mode: FocusMode
        let minutes: Int
    }

    private(set) var permissionRequests = 0
    private(set) var completions: [Completion] = []

    func requestPermission() {
        permissionRequests += 1
    }

    func sendCompletion(mode: FocusMode, minutes: Int) {
        completions.append(Completion(mode: mode, minutes: minutes))
    }
}

private func containsCompletionGreen(_ image: CGImage) -> Bool {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let target = (red: 85.0, green: 201.0, blue: 135.0)
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            let red = color.redComponent * 255
            let green = color.greenComponent * 255
            let blue = color.blueComponent * 255
            if abs(red - target.red) < 10,
               abs(green - target.green) < 10,
               abs(blue - target.blue) < 10 {
                return true
            }
        }
    }
    return false
}
