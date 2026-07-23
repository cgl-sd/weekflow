import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func stageSevenExecutionClassificationIncludesCompletionTimingAndSubtaskProgress() {
    var completed = WeekTask(title: "已完成", estimatedMinutes: 30)
    completed.status = .completed
    var timed = WeekTask(title: "已计时", estimatedMinutes: 30)
    timed.actualMinutes = 5
    var subtaskProgress = WeekTask(title: "子任务推进", estimatedMinutes: 30)
    subtaskProgress.subtasks = [TaskSubtask(title: "步骤", completed: true)]
    let untouched = WeekTask(title: "尚未开始", estimatedMinutes: 30)

    #expect(completed.hasExecutionProgress)
    #expect(timed.hasExecutionProgress)
    #expect(subtaskProgress.hasExecutionProgress)
    #expect(!untouched.hasExecutionProgress)
}

@MainActor
@Test func dailyShutdownTimeDistributionUsesActualThenCompletedEstimate() {
    var completedWithoutTimer = WeekTask(title: "完成但未计时", estimatedMinutes: 45)
    completedWithoutTimer.status = .completed

    var completedWithTimer = WeekTask(title: "完成且已计时", estimatedMinutes: 60)
    completedWithTimer.status = .completed
    completedWithTimer.actualMinutes = 25

    let unfinishedWithoutTimer = WeekTask(title: "尚未完成", estimatedMinutes: 30)

    #expect(DailyShutdownTimeDistribution.reviewMinutes(for: completedWithoutTimer) == 45)
    #expect(DailyShutdownTimeDistribution.reviewMinutes(for: completedWithTimer) == 25)
    #expect(DailyShutdownTimeDistribution.reviewMinutes(for: unfinishedWithoutTimer) == 0)
}

@MainActor
@Test func dailyMaintenanceLeavesOverdueTasksInPlaceForManualReview() throws {
    let folder = stageSevenTemporaryFolder("ManualMaintenance")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder), referenceDate: today)
    let goalID = try #require(store.selectedGoalID)
    let taskID = try #require(store.addTask(
        to: goalID,
        title: "等待收尾决定",
        plannedDate: yesterday,
        dueDate: nil,
        minutes: 30,
        notes: "",
        milestoneID: nil
    ))

    store.performDailyMaintenance()

    let task = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID })
    )
    #expect(task.plannedDate.map { calendar.isDate($0, inSameDayAs: yesterday) } == true)
    #expect(task.rolloverCount == 0)
}

@MainActor
@Test func dailyShutdownCanManuallyMoveAnUnfinishedTaskAndKeepItsCredit() throws {
    let folder = stageSevenTemporaryFolder("ManualRollover")
    defer { try? FileManager.default.removeItem(at: folder) }
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder), referenceDate: today)
    let goalID = try #require(store.selectedGoalID)
    let taskID = try #require(store.addTask(
        to: goalID,
        title: "手动顺延",
        plannedDate: today,
        dueDate: nil,
        minutes: 45,
        notes: "",
        milestoneID: nil
    ))
    var task = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID })
    )
    task.actualMinutes = 20
    store.updateTask(task, goalID: goalID)

    store.rolloverTaskManually(
        goalID: goalID,
        taskID: taskID,
        from: today,
        to: tomorrow
    )

    task = try #require(
        store.goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID })
    )
    #expect(task.plannedDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } == true)
    #expect(task.rolloverCount == 1)
    #expect(task.status != TaskStatus.archived)
    let hasExpectedCredit = task.completionCredits.contains {
        calendar.isDate($0.date, inSameDayAs: today)
            && $0.reason == CompletionCreditReason.actualTimeLogged
            && $0.minutes == 20
    }
    #expect(hasExpectedCredit)
}

@MainActor
@Test func stageSevenFocusTimerWritesModeMinutesIntoSharedStore() throws {
    let folder = stageSevenTemporaryFolder("Focus")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let suiteName = "WeekflowStageSevenFocus-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: StageSevenNotificationScheduler()
    )
    timer.configureFocusWriter { mode, seconds, date in
        store.recordFocusSession(mode: mode, seconds: seconds, date: date)
    }
    timer.select(.study)
    timer.start(now: .now)
    timer.advance(by: 65)
    timer.pause()

    #expect(store.focusMinutes(on: .now)[.study] == 1)
    #expect(store.focusMinutes(on: .now)[.meditation] == nil)
}

@MainActor
@Test func stageSevenFocusRecordsAndDailySummaryPersistThroughSharedStore() throws {
    let folder = stageSevenTemporaryFolder("Persistence")
    let suiteName = "WeekflowStageSevenPersistence-\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suiteName))
    defer {
        try? FileManager.default.removeItem(at: folder)
        preferences.removePersistentDomain(forName: suiteName)
    }
    let storage = LocalStorage(baseDirectory: folder)
    var store: WeekflowStore? = WeekflowStore(
        storage: storage,
        legacyPreferences: preferences,
        synchronousPersistence: true
    )
    store?.recordFocusSession(mode: .meditation, minutes: 15, date: .now)
    store?.recordFocusSession(mode: .meditation, minutes: 10, date: .now)
    store?.recordFocusSession(mode: .leisure, minutes: 20, date: .now)
    store?.saveDailySummary("## 今日总结\n完成了验收。", on: .now)
    store = nil

    // Simulate an app restart: a fresh LocalStorage reading the same on-disk file
    // (reusing the previous store's live storage instance is not a realistic
    // restart and races the shared persistence actor's teardown).
    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder), legacyPreferences: preferences)
    #expect(reloaded.focusMinutes(on: .now)[.meditation] == 25)
    #expect(reloaded.focusMinutes(on: .now)[.leisure] == 20)
    #expect(reloaded.dailySummary(on: .now)?.content.contains("完成了验收") == true)
}

@MainActor
@Test func stageSevenSummaryTemplateContainsResultsActualTimeAndFocusTotals() {
    let goal = WeeklyGoal(title: "交付", outcome: "完成", startDate: .now, endDate: .now)
    let progressed = WeekTask(
        title: "推进方案",
        plannedDate: .now,
        estimatedMinutes: 60,
        actualMinutes: 25,
        status: .inProgress,
        channelID: "work"
    )
    let untouched = WeekTask(
        title: "检查附件",
        plannedDate: .now,
        estimatedMinutes: 30,
        channelID: "research"
    )
    let summary = DailyShutdownSummaryBuilder.build(
        entries: [(goal, progressed), (goal, untouched)],
        focusMinutes: [.meditation: 10, .study: 35, .leisure: 15],
        channelTitle: { $0 == "work" ? "工作推进" : "研究整理" }
    )

    #expect(summary.contains("推进方案｜实际时间 00:25｜结果：进行中"))
    #expect(summary.contains("## 今日尚未实施的事项\n- 检查附件"))
    #expect(summary.contains("禅定：00:10"))
    #expect(summary.contains("学习：00:35"))
    #expect(summary.contains("休闲：00:15"))
    #expect(summary.contains("总专注时长：01:00"))
    #expect(summary.contains("工作推进：00:25"))
    #expect(!summary.contains("延伸到明天"))
    #expect(!summary.contains("移动日期"))
}

@MainActor
@Test func stageSevenReviewAndSummaryRenderAtLockedCanvas() throws {
    let folder = stageSevenTemporaryFolder("Render")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder), referenceDate: .now)
    store.recordFocusSession(mode: .meditation, minutes: 10, date: .now)
    store.recordFocusSession(mode: .study, minutes: 35, date: .now)
    store.recordFocusSession(mode: .leisure, minutes: 15, date: .now)

    let review = DailyShutdownView(store: store, initialPhase: 0)
        .frame(width: 951, height: 676, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    try stageSevenSnapshot(review, size: NSSize(width: 951, height: 676), name: "每日收尾-执行分类-阶段7")

    let summary = DailyShutdownView(store: store, initialPhase: 1)
        .frame(width: 951, height: 676, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    try stageSevenSnapshot(summary, size: NSSize(width: 951, height: 676), name: "每日收尾-总结模板-阶段7")

    #expect(WeekflowLayout.primaryActionHeight == 44)
    #expect(store.dailySummary(on: .now)?.content.contains("总专注时长：01:00") == true)
}

private func stageSevenTemporaryFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageSeven\(name)-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
private func stageSevenSnapshot<V: View>(_ view: V, size: NSSize, name: String) throws {
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
        throw StageSevenSnapshotError.encodingFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageSevenSnapshotError.encodingFailed
    }
    try png.write(to: outputFolder.appendingPathComponent("\(name).png"), options: .atomic)
}

@MainActor
private final class StageSevenNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {}
    func sendCompletion(mode: FocusMode, minutes: Int) {}
}

private enum StageSevenSnapshotError: Error {
    case encodingFailed
}
