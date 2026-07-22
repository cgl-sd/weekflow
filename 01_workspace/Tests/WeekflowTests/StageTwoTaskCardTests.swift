import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@Test func stageTwoTaskCardMetricsMeetCompactDensityAndHitTargets() {
    #expect(WeekflowLayout.taskCardMetadataVisualSize == 9)
    #expect(WeekflowLayout.taskCardIconSize == 11.5)
    #expect(WeekflowLayout.taskCardIconSize > WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskPopoverIconSize == 11.5)
    #expect(WeekflowLayout.taskCardIconHitTarget == 25)
    #expect(WeekflowLayout.taskCardPriorityBadgeHeight == 16)
    #expect(WeekflowLayout.taskCardPriorityBadgeHeight < WeekflowLayout.taskCardIconHitTarget)
    #expect((24...26).contains(WeekflowLayout.taskCardIconHitTarget))
    #expect((1...3).contains(WeekflowLayout.taskCardIconSpacing))
    #expect(WeekflowLayout.taskCardTitleFontSize == 13)
    #expect(WeekflowLayout.homeAddTaskFontSize == 13)
    #expect(WeekflowLayout.taskCardTitleFontSize == WeekflowLayout.homeAddTaskFontSize)
    #expect(WeekflowLayout.taskCardChannelFontSize == WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskCardTimerFontSize == WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskCardStartTimeFontSize == WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskCardSubtaskFontSize == 11)
    #expect(WeekflowLayout.taskCardPriorityFontSize == WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskCardMetadataHitTargetHeight == 32)
    #expect(WeekflowLayout.taskCardMetadataHitTargetHeight > WeekflowLayout.taskCardIconHitTarget)
    #expect((10...12).contains(WeekflowLayout.taskCardHorizontalPadding))
    #expect((6...8).contains(WeekflowLayout.taskCardVerticalPadding))
    #expect(WeekflowLayout.taskCardMinimumHeight == 84)
    #expect(WeekflowLayout.taskCardTitleTopPadding < WeekflowLayout.taskCardVerticalPadding)
    #expect(WeekflowLayout.taskCardFooterTopPadding < WeekflowLayout.taskCardVerticalPadding)
    #expect(WeekflowLayout.taskCardFooterLeadingInset == 0)
    #expect(WeekflowLayout.taskDatePopoverMaximumHeight > WeekflowLayout.taskCardMinimumHeight)
}

@Test func stageTwoTaskCardTimerUsesClockFormatAndShowsActualAgainstEstimate() {
    let planned = WeekTask(title: "未开始", estimatedMinutes: 60)
    let progressed = WeekTask(title: "已进行", estimatedMinutes: 60, actualMinutes: 15)

    #expect(planned.taskCardTimerText == "01:00")
    #expect(progressed.taskCardTimerText == "00:15 / 01:00")

    let comparisonWidth = ("99:59 / 99:59" as NSString).size(withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: WeekflowLayout.taskCardTimerFontSize, weight: .regular)
    ]).width + 12
    #expect(comparisonWidth <= WeekflowLayout.taskTimerComparisonMinimumWidth)
}

@Test func stageTwoChannelsRetainDistinctConfiguredColors() {
    let channels = TaskChannel.defaults
    #expect(Set(channels.map(\.colorName)).count >= 4)
    #expect(channels.first(where: { $0.id == "work" })?.colorName == "orange")
    #expect(channels.first(where: { $0.id == "research" })?.colorName == "blue")
    #expect(channels.first(where: { $0.id == "study" })?.colorName == "red")
    #expect(TaskPriority.none.flagSymbol == "flag")
    #expect(TaskPriority.must.flagSymbol == "flag.fill")
    #expect(!TaskPriority.none.showsOnTaskCard)
    #expect(TaskPriority.must.showsOnTaskCard)
    #expect(TaskPriority.should.showsOnTaskCard)
    #expect(TaskPriority.later.showsOnTaskCard)
    #expect(TaskPriority.must.label == "紧急")
    #expect(TaskPriority.should.label == "优先")
    #expect(TaskPriority.later.label == "低优先级")
}

@MainActor
@Test func stageTwoTaskCardKeepsTheSameSizeWhileHoverControlsAppear() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageTwoHoverSize-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)

    let normalRenderer = ImageRenderer(content:
        SunsamaTaskCard(entry: entry, store: store)
            .frame(width: 210)
    )
    let hoveredRenderer = ImageRenderer(content:
        SunsamaTaskCard(entry: entry, store: store, initiallyHovering: true)
            .frame(width: 210)
    )

    let normalSize = try #require(normalRenderer.nsImage).size
    let hoveredSize = try #require(hoveredRenderer.nsImage).size
    #expect(normalSize == hoveredSize)
    #expect(normalSize.height >= WeekflowLayout.taskCardMinimumHeight)
}

@MainActor
@Test func stageTwoTaskCardsRenderAtAcceptedBoardColumnWidth() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageTwoCards-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    var goal = WeeklyGoal(
        title: "任务卡验收",
        outcome: "验证卡片密度",
        startDate: .now,
        endDate: .now
    )
    let startTime = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: .now)
    goal.tasks = [
        WeekTask(
            title: "有开始时间且已经记录实际用时的任务",
            plannedDate: .now,
            startTime: startTime,
            estimatedMinutes: 60,
            actualMinutes: 15,
            status: .completed,
            channelID: "work",
            priority: .must
        ),
        WeekTask(
            title: "没有开始时间的超长任务名称用于验证省略和右侧时间不被推出卡片",
            plannedDate: .now,
            estimatedMinutes: 95,
            channelID: "research",
            priority: .none
        )
    ]

    let viewportWidth: CGFloat = 951
        - WeekflowLayout.homeBoardLeadingPadding
        - WeekflowLayout.homeBoardTrailingPadding
    let spacing: CGFloat = 18
    let columnWidth = (viewportWidth - spacing * (WeekflowLayout.boardVisibleDayCount - 1))
        / WeekflowLayout.boardVisibleDayCount
    let view = VStack(spacing: 8) {
        SunsamaTaskCard(entry: (goal, goal.tasks[0]), store: store)
        SunsamaTaskCard(entry: (goal, goal.tasks[1]), store: store)
        SunsamaTaskCard(
            entry: (goal, goal.tasks[1]),
            store: store,
            initiallyExpandedTimer: true,
            initiallyHovering: true
        )
    }
    .padding(10)
    .frame(width: columnWidth, height: 440, alignment: .top)
    .background(WeekflowPalette.appBackground)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size.width == columnWidth)
    #expect(image.size.height == 440)
    try writeStageTwoSnapshotIfRequested(image, name: "任务卡-阶段2有无开始时间")
}

private func writeStageTwoSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageTwoSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageTwoSnapshotError: Error {
    case encodingFailed
}
