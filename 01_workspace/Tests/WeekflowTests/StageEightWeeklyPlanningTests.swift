import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@Test func stageEightWeeklyTaskCardsUseCompactVerticalMetrics() {
    #expect(WeekflowLayout.weeklyTaskPoolCardHeight == 74)
    #expect(WeekflowLayout.weeklyAssignedTaskCardMinimumHeight == 70)
}

@MainActor
@Test func automaticWeeklyDistributionPreservesHistoryAndSkipsCurrentOrFutureAssignments() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowSafeAutoDistribution-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = Calendar.current
    let today = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 12))
    )
    let startOfToday = calendar.startOfDay(for: today)
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: startOfToday))
    let nextWeek = try #require(calendar.date(byAdding: .day, value: 7, to: startOfToday))
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: today
    )
    let goalID = store.addGoal(
        title: "自动分配边界",
        outcome: "保留历史与已有安排",
        startDate: startOfToday,
        endDate: nextWeek,
        persistImmediately: false
    )
    let primaryTaskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    for index in 1...6 {
        _ = store.addSubtask(
            goalID: goalID,
            taskID: primaryTaskID,
            title: "子目标 \(index)"
        )
    }
    let goalEntries = store.weeklyPlanningPoolEntries
        .filter { $0.goal.id == goalID }
    let taskIDs = goalEntries
        .map(\.task.id)
    #expect(taskIDs.count == 6)
    #expect(!taskIDs.contains(primaryTaskID))

    store.assignTask(goalID: goalID, taskID: taskIDs[0], to: yesterday)
    store.assignTask(goalID: goalID, taskID: taskIDs[1], to: tomorrow)
    var markedForNextWeek = try #require(
        store.weeklyPlanningPoolEntries.first { $0.task.id == taskIDs[2] }?.task
    )
    markedForNextWeek.executionWeekStart = nextWeek
    store.updateTask(markedForNextWeek, goalID: goalID)
    let completedSubgoalID = try #require(
        goalEntries.first(where: { $0.task.id == taskIDs[3] })?.task.subgoalID
    )
    store.toggleSubgoal(goalID: goalID, subgoalID: completedSubgoalID)

    store.autoDistributeTaskPool(now: today)

    let distributedTasks = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks
    )
    let historicalTask = try #require(distributedTasks.first(where: { $0.id == taskIDs[0] }))
    let futureTask = try #require(distributedTasks.first(where: { $0.id == taskIDs[1] }))
    let nextWeekTask = try #require(distributedTasks.first(where: { $0.id == taskIDs[2] }))
    let completedTask = try #require(distributedTasks.first(where: { $0.id == taskIDs[3] }))
    let firstNewlyAssignedTask = try #require(distributedTasks.first(where: { $0.id == taskIDs[4] }))
    let secondNewlyAssignedTask = try #require(distributedTasks.first(where: { $0.id == taskIDs[5] }))

    #expect(historicalTask.assignedDates.count == 1)
    #expect(historicalTask.isAssigned(on: yesterday))
    #expect(futureTask.assignedDates.count == 1)
    #expect(futureTask.isAssigned(on: tomorrow))
    #expect(nextWeekTask.assignedDates.isEmpty)
    #expect(calendar.isDate(try #require(nextWeekTask.executionWeekStart), inSameDayAs: nextWeek))
    #expect(completedTask.assignedDates.isEmpty)
    #expect(firstNewlyAssignedTask.isAssigned(on: startOfToday))
    #expect(secondNewlyAssignedTask.isAssigned(on: tomorrow))
    #expect(store.canUndoAutomaticDistribution)

    store.undoAutomaticDistribution()
    let undoneTasks = try #require(store.goals.first(where: { $0.id == goalID })?.tasks)
    #expect(undoneTasks.first(where: { $0.id == taskIDs[0] })?.isAssigned(on: yesterday) == true)
    #expect(undoneTasks.first(where: { $0.id == taskIDs[1] })?.isAssigned(on: tomorrow) == true)
    #expect(undoneTasks.first(where: { $0.id == taskIDs[4] })?.assignedDates.isEmpty == true)
    #expect(undoneTasks.first(where: { $0.id == taskIDs[5] })?.assignedDates.isEmpty == true)
    #expect(!store.canUndoAutomaticDistribution)

    store.autoDistributeTaskPool(now: today)
    let manuallyMovedDay = try #require(calendar.date(byAdding: .day, value: 2, to: startOfToday))
    store.relocateTask(
        goalID: goalID,
        taskID: taskIDs[4],
        from: startOfToday,
        to: manuallyMovedDay
    )
    store.undoAutomaticDistribution()
    let selectivelyUndoneTasks = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks
    )
    #expect(selectivelyUndoneTasks.first(where: { $0.id == taskIDs[4] })?.isAssigned(on: manuallyMovedDay) == true)
    #expect(selectivelyUndoneTasks.first(where: { $0.id == taskIDs[5] })?.assignedDates.isEmpty == true)
    #expect(selectivelyUndoneTasks.first(where: { $0.id == primaryTaskID })?.assignedDates.isEmpty == true)
}

@MainActor
@Test func automaticDistributionUsesOnlyUnassignedTaskPoolCardsInTheirExistingOrder() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowOrderedAutoDistribution-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = Calendar.current
    let today = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 12))
    )
    let startOfToday = calendar.startOfDay(for: today)
    let monday = try #require(calendar.date(byAdding: .day, value: -1, to: startOfToday))
    let previousWednesday = try #require(calendar.date(byAdding: .day, value: -6, to: startOfToday))
    let previousSunday = try #require(calendar.date(byAdding: .day, value: -2, to: startOfToday))
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: startOfToday))
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: today
    )
    let goalID = store.addGoal(
        title: "按任务池顺序分配",
        outcome: "",
        startDate: monday,
        endDate: try #require(calendar.date(byAdding: .day, value: 6, to: monday)),
        persistImmediately: false
    )
    let primaryTaskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    for index in 1...4 {
        _ = store.addSubtask(
            goalID: goalID,
            taskID: primaryTaskID,
            title: "任务池卡片 \(index)"
        )
    }
    let taskIDs = store.weeklyPlanningPoolEntries
        .filter { $0.goal.id == goalID }
        .map(\.task.id)
    #expect(taskIDs.count == 4)

    store.assignTask(goalID: goalID, taskID: taskIDs[0], to: monday)
    store.assignTask(goalID: goalID, taskID: taskIDs[1], to: monday)
    store.assignTask(goalID: goalID, taskID: taskIDs[2], to: previousWednesday)
    var priorWeekTask = try #require(
        store.goals.first(where: { $0.id == goalID })?
            .tasks.first(where: { $0.id == taskIDs[2] })
    )
    priorWeekTask.plannedDate = previousSunday
    store.updateTask(priorWeekTask, goalID: goalID)
    store.autoDistributeTaskPool(now: today)

    let tasks = try #require(store.goals.first(where: { $0.id == goalID })?.tasks)
    #expect(tasks.first(where: { $0.id == taskIDs[0] })?.assignedDates.count == 1)
    #expect(tasks.first(where: { $0.id == taskIDs[1] })?.assignedDates.count == 1)
    #expect(tasks.first(where: { $0.id == taskIDs[2] })?.isAssigned(on: previousWednesday) == true)
    #expect(tasks.first(where: { $0.id == taskIDs[2] })?.isAssigned(on: startOfToday) == true)
    #expect(tasks.first(where: { $0.id == taskIDs[3] })?.isAssigned(on: tomorrow) == true)
}

@MainActor
@Test func startingAnotherAutomaticDistributionCommitsThePreviousResult() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCommittedAutoDistribution-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = Calendar.current
    let today = try #require(
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 12))
    )
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: today
    )
    let goalID = store.addGoal(title: "锁定自动分配", outcome: "", endDate: today)
    let primaryTaskID = try #require(store.ensurePrimaryTask(forGoalID: goalID))
    _ = store.addSubtask(goalID: goalID, taskID: primaryTaskID, title: "第一轮")
    let firstTaskID = try #require(
        store.weeklyPlanningPoolEntries.first(where: { $0.goal.id == goalID })?.task.id
    )
    func assignedDates(for taskID: UUID) -> [Date]? {
        store.goals.first(where: { $0.id == goalID })?
            .tasks.first(where: { $0.id == taskID })?.assignedDates
    }

    store.autoDistributeTaskPool(now: today)
    #expect(store.canUndoAutomaticDistribution)
    #expect(assignedDates(for: firstTaskID)?.count == 1)

    // A second run with no new unit commits the first assignment and leaves
    // no current transaction for the undo control.
    store.autoDistributeTaskPool(now: today)
    #expect(!store.canUndoAutomaticDistribution)
    store.undoAutomaticDistribution()
    #expect(assignedDates(for: firstTaskID)?.count == 1)

    _ = store.addSubtask(goalID: goalID, taskID: primaryTaskID, title: "第二轮")
    let secondTaskID = try #require(
        store.weeklyPlanningPoolEntries.first(where: {
            $0.goal.id == goalID && $0.task.id != firstTaskID
        })?.task.id
    )
    store.autoDistributeTaskPool(now: today)
    #expect(store.canUndoAutomaticDistribution)
    #expect(assignedDates(for: secondTaskID)?.count == 1)

    store.undoAutomaticDistribution()
    #expect(assignedDates(for: firstTaskID)?.count == 1)
    #expect(assignedDates(for: secondTaskID)?.isEmpty == true)
    #expect(!store.canUndoAutomaticDistribution)
}

@MainActor
@Test func nextWeekWithoutExactDayStaysInTheMarkedWeeklyPool() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowNextWeekPool-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let referenceDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))
    )
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: referenceDate
    )
    let goal = try #require(store.activeGoals.first)
    let thisMonday = mondayOfWeek(containing: referenceDate)
    let nextMonday = try #require(Calendar.current.date(byAdding: .day, value: 7, to: thisMonday))

    let taskID = try #require(store.addTask(
        to: goal.id,
        title: "下周内执行但日期待定",
        plannedDate: nil,
        dueDate: nil,
        minutes: 45,
        notes: "",
        milestoneID: nil,
        executionWeekStart: nextMonday
    ))
    let task = try #require(
        store.goals.first(where: { $0.id == goal.id })?.tasks.first(where: { $0.id == taskID })
    )

    #expect(task.plannedDate == nil)
    #expect(Calendar.current.isDate(try #require(task.executionWeekStart), inSameDayAs: nextMonday))
    #expect(store.taskPool.contains { $0.task.id == taskID })

    let tuesday = try #require(Calendar.current.date(byAdding: .day, value: 1, to: nextMonday))
    store.assignTask(goalID: goal.id, taskID: taskID, to: tuesday)
    let assigned = try #require(
        store.goals.first(where: { $0.id == goal.id })?.tasks.first(where: { $0.id == taskID })
    )
    #expect(assigned.executionWeekStart == nil)
    #expect(assigned.isAssigned(on: tuesday))
}

@MainActor
@Test func weeklyPoolSourceCanAppearOnMultipleDaysAndStaySynchronized() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageEightPool-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))
    )
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: referenceDate
    )
    let source = try #require(store.taskPool.first { $0.task.executionWeekStart == nil })
    let monday = mondayOfWeek(containing: referenceDate)
    let thursday = try #require(Calendar.current.date(byAdding: .day, value: 3, to: monday))

    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: monday)
    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: thursday)

    let updated = try #require(
        store.goals
            .first(where: { $0.id == source.goal.id })?
            .tasks.first(where: { $0.id == source.task.id })
    )
    #expect(updated.plannedDate == nil)
    #expect(updated.assignedDates.count == 2)
    #expect(store.taskPool.contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: monday).contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: thursday).contains { $0.task.id == source.task.id })

    store.removeTaskAssignment(goalID: source.goal.id, taskID: source.task.id, from: monday)
    #expect(!store.tasks(on: monday).contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: thursday).contains { $0.task.id == source.task.id })
    #expect(store.taskPool.contains { $0.task.id == source.task.id })
}

@MainActor
@Test func weeklyDailyDragMovesOnlyTheOriginatingAssignment() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageEightMove-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))
    )
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: referenceDate
    )
    let source = try #require(store.taskPool.first)
    let monday = mondayOfWeek(containing: referenceDate)
    let tuesday = try #require(Calendar.current.date(byAdding: .day, value: 1, to: monday))
    let friday = try #require(Calendar.current.date(byAdding: .day, value: 4, to: monday))
    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: monday)
    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: tuesday)

    let token = TaskDragToken(goalID: source.goal.id, taskID: source.task.id, sourceDate: monday)
    let decoded = try #require(TaskDragToken(token: token.value))
    store.relocateTask(
        goalID: decoded.goalID,
        taskID: decoded.taskID,
        from: decoded.sourceDate,
        to: friday
    )

    #expect(!store.tasks(on: monday).contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: tuesday).contains { $0.task.id == source.task.id })
    #expect(store.tasks(on: friday).contains { $0.task.id == source.task.id })
    #expect(store.taskPool.contains { $0.task.id == source.task.id })
}

@MainActor
@Test func weeklyPlanningRendersTaskPoolAndSevenDayHorizontalBoard() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageEightRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = try #require(
        Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))
    )
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: referenceDate)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: fixture
    )
    let source = try #require(store.taskPool.first { $0.task.executionWeekStart == nil })
    let monday = mondayOfWeek(containing: referenceDate)
    let wednesday = try #require(Calendar.current.date(byAdding: .day, value: 2, to: monday))
    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: monday)
    store.assignTask(goalID: source.goal.id, taskID: source.task.id, to: wednesday)

    let view = WeeklyBoardView(
        store: store,
        presentedTask: .constant(nil),
        usesScrollContainer: false,
        referenceDate: referenceDate
    )
    .frame(width: 951, height: 900, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)

    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 951, height: 900)
    host.layoutSubtreeIfNeeded()
    let horizontalScrollers = descendantScrollViews(of: host).filter { $0.hasHorizontalScroller }
    #expect(!horizontalScrollers.isEmpty)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size == NSSize(width: 951, height: 900))
    try writeStageEightSnapshotIfRequested(image, name: "本周规划-下周待定任务池分区")

    let weekDays = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: monday) }
    let focusedFixture = VStack(alignment: .leading, spacing: 18) {
        Text("任务池")
            .font(.title2.weight(.semibold))
        HStack(spacing: 10) {
            ForEach(store.taskPool.prefix(3), id: \.task.id) { entry in
                WeeklyTaskPoolCard(
                    entry: entry,
                    tint: store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault,
                    store: store,
                    calendarAnchorDate: referenceDate
                )
            }
        }
        Text("每日分配 · 周一至周日")
            .font(.title2.weight(.semibold))
        HStack(alignment: .top, spacing: 10) {
            ForEach(weekDays, id: \.self) { date in
                WeekDayColumn(date: date, entries: store.tasks(on: date), store: store)
            }
        }
    }
    .padding(24)
    .frame(width: 1_450, height: 620, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)
    let focusedRenderer = ImageRenderer(content: focusedFixture)
    focusedRenderer.scale = 2
    let focusedImage = try #require(focusedRenderer.nsImage)
    #expect(focusedImage.size == NSSize(width: 1_450, height: 620))
    try writeStageEightSnapshotIfRequested(focusedImage, name: "本周规划-卡片与七天完整展开")
}

private func mondayOfWeek(containing date: Date) -> Date {
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: date)
    let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
    return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
}

@MainActor
private func descendantScrollViews(of view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView { result.append(scrollView) }
    for subview in view.subviews {
        result.append(contentsOf: descendantScrollViews(of: subview))
    }
    return result
}

private func writeStageEightSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageEightSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageEightSnapshotError: Error {
    case encodingFailed
}
