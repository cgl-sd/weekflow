import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func stageTenInlineDurationPersistsIndependentlyForAllModes() throws {
    let suiteName = "WeekflowStageTenDurations-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let scheduler = StageTenNotificationScheduler()
    let timer = FocusTimerService(defaults: defaults, notificationScheduler: scheduler)

    #expect(FocusMode.allCases.allSatisfy { timer.minutes(for: $0) == 60 })
    timer.updateCurrentDurationMinutes(35)
    timer.select(.study)
    timer.updateCurrentDurationMinutes(85)
    timer.select(.leisure)
    timer.updateCurrentDurationMinutes(125)

    let restored = FocusTimerService(defaults: defaults, notificationScheduler: scheduler)
    #expect(restored.minutes(for: .meditation) == 35)
    #expect(restored.minutes(for: .study) == 85)
    #expect(restored.minutes(for: .leisure) == 125)
}

@MainActor
@Test func stageTenLinkedTaskRemainsBackendOnlyAndWritesActualTimeAndFocusRecord() throws {
    let suiteName = "WeekflowStageTenTask-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: StageTenNotificationScheduler()
    )
    let reference = TaskReference(goalID: UUID(), taskID: UUID())
    var taskSeconds = 0
    var focusRecords: [(FocusMode, Int)] = []
    timer.configureTaskWriter { received, seconds in
        #expect(received == reference)
        taskSeconds += seconds
    }
    timer.configureFocusWriter { mode, seconds, _ in
        focusRecords.append((mode, seconds))
    }

    timer.linkTask(reference, title: "完成验收", estimatedMinutes: 45)
    #expect(timer.formattedRemaining == "45:00")
    timer.start(now: .now)
    timer.advance(by: 125)
    timer.pause()

    #expect(taskSeconds == 125)
    #expect(focusRecords.count == 1)
    #expect(focusRecords.first?.0 == .meditation)
    #expect(focusRecords.first?.1 == 125)
}

@MainActor
@Test func stageTenStandaloneMeditationStartsWithoutAStaleTaskLink() throws {
    let suiteName = "WeekflowStageTenStandalone-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: StageTenNotificationScheduler()
    )

    #expect(timer.selectedMode == .meditation)
    #expect(timer.linkedTask == nil)
    #expect(timer.linkedTaskTitle == nil)
    #expect(timer.formattedRemaining == "60:00")
}

@MainActor
@Test func stageTenMenuBarModeSwitchSettlesCurrentSessionBeforeSwitching() throws {
    let suiteName = "WeekflowStageTenSwitch-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: StageTenNotificationScheduler()
    )
    var recordedSeconds = 0
    timer.configureFocusWriter { _, seconds, _ in recordedSeconds += seconds }

    timer.start(now: .now)
    timer.advance(by: 65)
    timer.stopAndSelect(.study)

    #expect(recordedSeconds == 65)
    #expect(timer.selectedMode == .study)
    #expect(!timer.isRunning)
    #expect(!timer.hasStarted)
    #expect(timer.formattedRemaining == "60:00")
}

@MainActor
@Test func stageTenMaximumCountdownUsesSingleLineHourMinuteSecondFormat() throws {
    let suiteName = "WeekflowStageTenSingleLine-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: StageTenNotificationScheduler()
    )

    timer.updateCurrentDurationMinutes(FocusTimerService.maximumDurationMinutes)

    #expect(timer.formattedRemaining == "04:00:00")
    #expect(!timer.formattedRemaining.contains("\n"))
}

@Test func stageTenStatusPanelAndPointerShareTheStatusItemAnchor() {
    let centered = FocusStatusPanelPlacement.resolve(
        statusItemFrame: CGRect(x: 700, y: 880, width: 100, height: 24),
        panelSize: CGSize(width: 272, height: 313),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )

    #expect(centered.origin.x + 136 == 750)
    #expect(centered.pointerOffset == 0)
    #expect(centered.origin.y + 313 + 2 == 880)

    let clampedAtRightEdge = FocusStatusPanelPlacement.resolve(
        statusItemFrame: CGRect(x: 1_390, y: 880, width: 40, height: 24),
        panelSize: CGSize(width: 272, height: 313),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
    )

    #expect(clampedAtRightEdge.origin.x == 1_162)
    #expect(clampedAtRightEdge.origin.x + 136 + clampedAtRightEdge.pointerOffset == 1_410)
}

@MainActor
@Test func stageTenFocusViewRendersSingleCentralControlAtLockedCanvas() throws {
    let suiteName = "WeekflowStageTenRender-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let timer = FocusTimerService(
        defaults: defaults,
        notificationScheduler: StageTenNotificationScheduler()
    )
    timer.select(.study)
    timer.updateCurrentDurationMinutes(75)
    let view = FocusView(timer: timer)
        .frame(width: 951, height: 676, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    let hostingView = NSHostingView(rootView: view)
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

    #expect(timer.formattedRemaining == "75:00")
    #expect(FocusTimerService.durationStepMinutes == 5)
    try writeStageTenSnapshotIfRequested(hostingView, name: "专注模式-中心计时组件-阶段10")

    let editingView = FocusView(timer: timer, initiallyEditingDuration: true)
        .frame(width: 951, height: 676, alignment: .topLeading)
        .background(WeekflowPalette.appBackground)
    let editingHostingView = NSHostingView(rootView: editingView)
    editingHostingView.frame = hostingView.frame
    window.contentView = editingHostingView
    editingHostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    editingHostingView.layoutSubtreeIfNeeded()
    try writeStageTenSnapshotIfRequested(editingHostingView, name: "专注模式-内嵌时长滑轨-阶段10")

    timer.updateCurrentDurationMinutes(FocusTimerService.maximumDurationMinutes)
    let statusPanelView = FocusStatusPanelSurface(timer: timer, pointerOffset: 0)
        .frame(width: 272, height: 313)
    let statusPanelHostingView = NSHostingView(rootView: statusPanelView)
    statusPanelHostingView.frame = NSRect(x: 0, y: 0, width: 272, height: 313)
    window.contentView = statusPanelHostingView
    statusPanelHostingView.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    statusPanelHostingView.layoutSubtreeIfNeeded()
    try writeStageTenSnapshotIfRequested(statusPanelHostingView, name: "专注模式-状态栏自定义弹窗-阶段10")
}

@MainActor
private final class StageTenNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {}
    func sendCompletion(mode: FocusMode, minutes: Int) {}
}

@MainActor
private func writeStageTenSnapshotIfRequested(_ view: NSView, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw StageTenSnapshotError.encodingFailed
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageTenSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageTenSnapshotError: Error {
    case encodingFailed
}
