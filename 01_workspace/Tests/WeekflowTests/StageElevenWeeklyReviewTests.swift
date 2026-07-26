import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func stageElevenWeeklySnapshotUsesUnifiedGoalTaskFocusAndSummaryData() throws {
    let referenceDate = try stageElevenDate(year: 2026, month: 7, day: 15, hour: 12)
    let data = try stageElevenData(referenceDate: referenceDate)
    let snapshot = WeeklyReviewSnapshot(
        goals: Array(data.goals.prefix(2)),
        channels: TaskChannel.defaults,
        focusRecords: data.focusRecords,
        dailySummaries: data.dailySummaries,
        referenceDate: referenceDate
    )

    #expect(snapshot.goals.count == 2)
    #expect(snapshot.completedGoalCount == 1)
    #expect(snapshot.goalCompletionRate == 0.5)
    #expect(snapshot.taskEntries.count == 4)
    #expect(snapshot.performedTaskCount == 3)
    #expect(snapshot.taskExecutionRate == 0.75)
    #expect(snapshot.plannedMinutes == 270)
    #expect(snapshot.actualMinutes == 125)
    #expect(snapshot.varianceMinutes == -145)
    #expect(snapshot.incompleteEntries.map(\.task.title) == ["编写周报", "整理附件"])
    #expect(snapshot.focusMinutes["study"] == 30)
    #expect(snapshot.focusMinutes["meditation"] == 10)
    #expect(snapshot.focusMetrics.first { $0.modeID == "study" }?.sessionCount == 1)
    #expect(snapshot.totalFocusMinutes == 40)
    #expect(snapshot.dailySummaries.count == 2)
    #expect(snapshot.dayMetrics.reduce(0) { $0 + $1.taskMinutes } == 125)
    #expect(snapshot.dayMetrics.reduce(0) { $0 + $1.focusMinutes } == 40)
    #expect(snapshot.dayMetrics.reduce(0) { $0 + ($1.taskChannelMinutes["work"] ?? 0) } == 95)
    #expect(snapshot.dayMetrics.reduce(0) { $0 + ($1.taskChannelMinutes["research"] ?? 0) } == 30)
    #expect(snapshot.dayMetrics.reduce(0) { $0 + ($1.focusModeMinutes["study"] ?? 0) } == 30)
    #expect(snapshot.dayMetrics.reduce(0) { $0 + ($1.focusModeMinutes["meditation"] ?? 0) } == 10)
    #expect(snapshot.summaryText.contains("完成 1 / 2 个目标"))
    #expect(snapshot.summaryText.contains("推进 3 / 4 项任务"))
}

@MainActor
@Test func weeklyReviewAndDailyReviewShareTheChartPaletteSource() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Weekflow")
    let weeklySource = try String(
        contentsOf: root.appendingPathComponent("Views/WeeklyReviewView.swift"),
        encoding: .utf8
    )
    let dailySource = try String(
        contentsOf: root.appendingPathComponent("Views/PlanningTaskPool.swift"),
        encoding: .utf8
    )
    let settingsColorPickers = try String(
        contentsOf: root.appendingPathComponent("Views/SettingsColorPickers.swift"),
        encoding: .utf8
    )
    let settingsMain = try String(
        contentsOf: root.appendingPathComponent("Views/ChannelSettingsView.swift"),
        encoding: .utf8
    )
    let settingsSource = settingsColorPickers + settingsMain

    #expect(weeklySource.contains("ChartPalettePreferences.storageKey"))
    #expect(dailySource.contains("ChartPalettePreferences.storageKey"))
    #expect(settingsSource.contains("ChartPalettePicker"))
    #expect(settingsSource.contains("ChartPaletteMenu"))
    #expect(settingsSource.contains("ChartPaletteAnchorPreferenceKey"))
    #expect(settingsSource.contains("TaskControlMenuSurface("))
    #expect(settingsSource.contains("struct ChartPaletteMenuRow: View"))
    #expect(settingsSource.contains("isHovering ? WeekflowPalette.surfaceHover : .clear"))
    #expect(settingsSource.contains("Text(\"用于每日回顾和周回顾。\")"))
    #expect(!settingsSource.contains("专注模式保留自身颜色"))
    #expect(weeklySource.contains("本周任务目标完成情况"))
    #expect(!weeklySource.contains("metrics.filter { $0.totalMinutes > 0 }"))
    #expect(weeklySource.contains("ForEach(metrics)"))
    #expect(weeklySource.contains("title: \"专注模式 \\(shareText(focusMinutes))\""))
    #expect(weeklySource.contains("WeeklyReviewBreakdown(snapshot: snapshot)"))
    #expect(weeklySource.contains("WeekflowPalette.focusRing"))
    #expect(weeklySource.contains("snapshot.channelMetrics"))
    #expect(!weeklySource.contains("项完成"))
    #expect(!weeklySource.contains("completedTasks.map"))
    #expect(!weeklySource.contains("任务时间占比"))
    #expect(!weeklySource.contains("专注时间占比"))
    #expect(!weeklySource.contains("保留到任务池"))
}

@MainActor
@Test func chartPaletteOffersCommonWarmAndDarkModeOptionsWithLegacyFallbacks() {
    #expect(ChartPalettePreset.allCases.count == 8)
    #expect(ChartPalettePreset.allCases.contains(.rainbow))
    #expect(ChartPalettePreset.allCases.contains(.warm))
    #expect(ChartPalettePreset.allCases.filter(\.isOptimizedForDarkMode).count == 2)
    #expect(ChartPalettePreferences.preset(for: "sage") == .colorBrewer)
    #expect(ChartPalettePreferences.preset(for: "dusk") == .brightDark)
    #expect(ChartPalettePreset.classic.taskColors(for: .light).count == 8)
    #expect(ChartPalettePreset.classic.taskColors(for: .dark).count == 8)
    for mode in FocusMode.allCases {
        #expect(ChartPalettePreset.rainbow.focusColor(mode.rawValue) == mode.accentColor)
    }
}

@MainActor
@Test func stageElevenChannelDistributionUsesActualTaskMinutesAndConfiguredChannels() throws {
    let referenceDate = try stageElevenDate(year: 2026, month: 7, day: 15, hour: 12)
    let data = try stageElevenData(referenceDate: referenceDate)
    let snapshot = WeeklyReviewSnapshot(
        goals: Array(data.goals.prefix(2)),
        channels: TaskChannel.defaults,
        focusRecords: data.focusRecords,
        dailySummaries: data.dailySummaries,
        referenceDate: referenceDate
    )

    let work = try #require(snapshot.channelMetrics.first { $0.channelID == "work" })
    let research = try #require(snapshot.channelMetrics.first { $0.channelID == "research" })
    #expect(work.title == "工作推进")
    #expect(work.colorName == "orange")
    #expect(work.minutes == 95)
    #expect(abs(work.share - 0.76) < 0.001)
    #expect(research.title == "研究整理")
    #expect(research.minutes == 30)
    #expect(abs(research.share - 0.24) < 0.001)
}

@MainActor
@Test func stageElevenWeeklyReviewRendersRealCalculatedSections() throws {
    let referenceDate = try stageElevenDate(year: 2026, month: 7, day: 15, hour: 12)
    let data = try stageElevenData(referenceDate: referenceDate)
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageElevenRender-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(
        storage: LocalStorage(baseDirectory: folder),
        referenceDate: referenceDate
    )
    store.goals = data.goals
    store.focusRecords = data.focusRecords
    store.dailySummaries = data.dailySummaries

    let view = WeeklyReviewView(
        store: store,
        usesScrollContainer: true,
        referenceDate: referenceDate
    )
    .frame(width: 951, height: 676, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)

    let image = try stageElevenRender(view, size: NSSize(width: 951, height: 676))
    #expect(image.size == NSSize(width: 951, height: 676))
    try stageElevenWriteSnapshotIfRequested(image, name: "每周回顾-真实数据计算-阶段11")
}

private struct StageElevenData {
    let goals: [WeeklyGoal]
    let focusRecords: [FocusRecord]
    let dailySummaries: [DailySummary]
}

private func stageElevenData(referenceDate: Date) throws -> StageElevenData {
    let calendar = Calendar.current
    let firstDay = calendar.date(byAdding: .day, value: -3, to: referenceDate) ?? referenceDate
    let secondDay = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
    let weekEnd = calendar.date(byAdding: .day, value: 3, to: referenceDate) ?? referenceDate
    let outsideWeek = calendar.date(byAdding: .day, value: -14, to: referenceDate) ?? referenceDate

    var completedResearch = WeekTask(
        title: "完成资料整理",
        plannedDate: referenceDate,
        estimatedMinutes: 60,
        actualMinutes: 50,
        status: .completed,
        channelID: "work"
    )
    completedResearch.changeRecords = [stageElevenTimerChange(on: referenceDate, from: 0, to: 50)]

    var completedOutline = WeekTask(
        title: "确认报告结构",
        plannedDate: secondDay,
        estimatedMinutes: 30,
        actualMinutes: 30,
        status: .completed,
        channelID: "research"
    )
    completedOutline.changeRecords = [stageElevenTimerChange(on: secondDay, from: 0, to: 30)]

    var report = WeekTask(
        title: "编写周报",
        plannedDate: secondDay,
        estimatedMinutes: 120,
        actualMinutes: 45,
        status: .inProgress,
        channelID: "work"
    )
    report.changeRecords = [stageElevenTimerChange(on: secondDay, from: 0, to: 45)]

    let attachments = WeekTask(
        title: "整理附件",
        plannedDate: weekEnd,
        estimatedMinutes: 60,
        channelID: "study"
    )

    let completedGoal = WeeklyGoal(
        title: "完成研究整理",
        outcome: "资料与结构确认完毕",
        startDate: firstDay,
        endDate: weekEnd,
        tasks: [completedResearch, completedOutline]
    )
    let activeGoal = WeeklyGoal(
        title: "交付本周汇报",
        outcome: "形成可同步的周报",
        startDate: firstDay,
        endDate: weekEnd,
        tasks: [report, attachments]
    )
    let outsideGoal = WeeklyGoal(
        title: "上月目标",
        outcome: "不应进入本周统计",
        startDate: outsideWeek,
        endDate: outsideWeek,
        tasks: [WeekTask(title: "旧任务", estimatedMinutes: 600, actualMinutes: 600, status: .completed)]
    )

    return StageElevenData(
        goals: [completedGoal, activeGoal, outsideGoal],
        focusRecords: [
            FocusRecord(date: referenceDate, mode: .study, minutes: 30),
            FocusRecord(date: secondDay, mode: .meditation, minutes: 10),
            FocusRecord(date: outsideWeek, mode: .leisure, minutes: 120)
        ],
        dailySummaries: [
            DailySummary(date: referenceDate, content: "## 今日总结\n完成资料梳理。"),
            DailySummary(date: secondDay, content: "## 今日总结\n推进周报。"),
            DailySummary(date: outsideWeek, content: "不属于本周")
        ]
    )
}

private func stageElevenTimerChange(on date: Date, from oldMinutes: Int, to newMinutes: Int) -> TaskChangeRecord {
    TaskChangeRecord(
        date: date,
        field: "实际时间",
        oldValue: oldMinutes.hourMinuteClockText,
        newValue: newMinutes.hourMinuteClockText,
        source: .timer
    )
}

private func stageElevenDate(year: Int, month: Int, day: Int, hour: Int) throws -> Date {
    try #require(
        Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )
    )
}

private func stageElevenWriteSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageElevenSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

@MainActor
private func stageElevenRender<V: View>(_ view: V, size: NSSize) throws -> NSImage {
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
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw StageElevenSnapshotError.encodingFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
}

private enum StageElevenSnapshotError: Error {
    case encodingFailed
}
