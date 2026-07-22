import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func stageTwelveLongPickersStayBoundedAndScrollInternally() throws {
    let channels = (1...30).map {
        TaskChannel(id: "channel-\($0)", title: "频道 \($0)", colorName: $0.isMultiple(of: 2) ? "purple" : "orange")
    }
    let goals = (1...20).map {
        WeeklyGoal(
            title: "周目标 \($0) · 保持一行但允许较长标题",
            outcome: "验收弹窗内部滚动",
            startDate: .now,
            endDate: .now
        )
    }

    let channelPicker = ComposerChannelPicker(
        channels: channels,
        selection: .constant(nil),
        query: .constant(""),
        onManage: {}
    )
    let channelHost = try hostedPopover(channelPicker)
    #expect(channelHost.frame.width == WeekflowLayout.composerChannelPopoverWidth)
    #expect(channelHost.frame.height <= WeekflowLayout.composerChannelPopoverMaximumHeight)
    #expect(hasOverflowingVerticalScrollView(in: channelHost))

    let goalPicker = ComposerGoalPicker(goals: goals, selection: .constant(goals.first?.id))
    let goalHost = try hostedPopover(goalPicker)
    #expect(goalHost.frame.width == WeekflowLayout.composerGoalPopoverWidth)
    #expect(goalHost.frame.height <= WeekflowLayout.composerGoalPopoverMaximumHeight)
    #expect(hasOverflowingVerticalScrollView(in: goalHost))

    let taskChannelPicker = TaskChannelPopover(
        channels: channels,
        selectedChannelID: channels.first?.id,
        select: { _ in },
        manage: {}
    )
    let taskChannelHost = try hostedPopover(taskChannelPicker)
    #expect(taskChannelHost.frame.width == WeekflowLayout.taskChannelPopoverWidth)
    #expect(taskChannelHost.frame.height <= WeekflowLayout.taskChannelPopoverMaximumHeight)
    #expect(hasOverflowingVerticalScrollView(in: taskChannelHost))

    let comparison = HStack(alignment: .top, spacing: 14) {
        channelPicker
        goalPicker
        taskChannelPicker
    }
    .padding(16)
    .frame(width: 800, height: 320, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)
    let comparisonHost = NSHostingView(rootView: comparison)
    comparisonHost.frame = NSRect(x: 0, y: 0, width: 800, height: 320)
    let comparisonWindow = NSWindow(
        contentRect: comparisonHost.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    comparisonWindow.contentView = comparisonHost
    comparisonHost.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    comparisonHost.layoutSubtreeIfNeeded()
    let image = try snapshotStageTwelve(comparisonHost)
    try writeStageTwelveSnapshotIfRequested(image, name: "长列表弹窗-内部滚动-阶段12")
    _ = comparisonWindow
}

@MainActor
@Test func stageTwelveFilterWithThirtyChannelsUsesTheSameBoundedPolicy() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowStageTwelveFilter-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder), referenceDate: .now)
    store.channels = (1...30).map {
        TaskChannel(id: "filter-\($0)", title: "筛选频道 \($0)", colorName: "purple")
    }

    let view = TaskFilterPopover(store: store, selection: .constant("all"))
    let host = try hostedPopover(view)
    #expect(host.frame.width == WeekflowLayout.taskFilterPopoverWidth)
    #expect(host.frame.height <= WeekflowLayout.taskFilterPopoverMaximumHeight)
    #expect(hasOverflowingVerticalScrollView(in: host))
}

@MainActor
private func hostedPopover<V: View>(_ view: V) throws -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    let fittingSize = host.fittingSize
    #expect(fittingSize.width > 0)
    #expect(fittingSize.height > 0)
    host.frame = NSRect(origin: .zero, size: fittingSize)
    let window = NSWindow(
        contentRect: host.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    return host
}

@MainActor
private func hasOverflowingVerticalScrollView(in view: NSView) -> Bool {
    descendantScrollViews(of: view).contains { scrollView in
        guard let documentView = scrollView.documentView else { return false }
        return scrollView.hasVerticalScroller && documentView.frame.height > scrollView.contentView.bounds.height
    }
}

@MainActor
private func descendantScrollViews(of view: NSView) -> [NSScrollView] {
    var result = view as? NSScrollView == nil ? [] : [view as! NSScrollView]
    for subview in view.subviews {
        result.append(contentsOf: descendantScrollViews(of: subview))
    }
    return result
}

@MainActor
private func snapshotStageTwelve(_ view: NSView) throws -> NSImage {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw StageTwelveSnapshotError.encodingFailed
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(bitmap)
    return image
}

private func writeStageTwelveSnapshotIfRequested(_ image: NSImage, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw StageTwelveSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum StageTwelveSnapshotError: Error {
    case encodingFailed
}
