import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func calendarInteractionReferenceSurfacesKeepTheirAcceptedGeometry() throws {
    let contextMenu = TaskCardContextPopover(
        hasStartTime: true,
        addToCalendar: {},
        addToCalendarAt: { _ in },
        clearFromCalendar: {},
        moveToBacklog: {},
        moveToTopOfBacklog: {},
        copy: {},
        cut: {},
        paste: {},
        canPaste: true,
        delete: {}
    )
    let hoverCard = CalendarHoverCard(
        model: CalendarHoverCardModel(
            title: "完善 Weekflow 看板",
            timeRange: "14:00–16:45",
            calendarName: "Weekflow 日历",
            channelName: "汇报材料",
            color: .purple,
            priority: .should,
            isCommitted: true,
            isTask: true
        ),
        pointerOnRight: true,
        openTask: {},
        pinTask: {},
        hoverChanged: { _ in }
    )

    let menuImage = render(contextMenu, size: CGSize(width: 218, height: 278))
    let hoverImage = render(hoverCard, size: CGSize(width: 156, height: 136))

    #expect(menuImage.size == CGSize(width: 218, height: 278))
    #expect(hoverImage.size == CGSize(width: 156, height: 136))

    if ProcessInfo.processInfo.environment["WEEKFLOW_RENDER_COMPARISON"] == "1" {
        try writePNG(menuImage, to: "/tmp/weekflow-task-context-menu.png")
        try writePNG(hoverImage, to: "/tmp/weekflow-calendar-hover-card.png")
    }
}

@MainActor
private func render<V: View>(_ view: V, size: CGSize) -> NSImage {
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    guard let representation = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        return NSImage(size: size)
    }
    host.cacheDisplay(in: host.bounds, to: representation)
    let image = NSImage(size: size)
    image.addRepresentation(representation)
    return image
}

private func writePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

@MainActor
@Test func expandedAssistantPanelOccludesCoveredTaskCardContextClicks() {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 900, height: 600),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    let overlay = SecondaryClickOcclusionView(frame: CGRect(x: 620, y: 0, width: 280, height: 600))
    window.contentView = root
    root.addSubview(overlay)
    SecondaryClickOcclusionRegistry.register(overlay)
    defer { SecondaryClickOcclusionRegistry.unregister(overlay) }

    #expect(SecondaryClickOcclusionRegistry.contains(CGPoint(x: 700, y: 240), in: window))
    #expect(!SecondaryClickOcclusionRegistry.contains(CGPoint(x: 400, y: 240), in: window))
}

@MainActor
@Test func taskContextMenuChoosesTheSideWithUsableSpaceAndPresentsDirectly() {
    #expect(TaskCardContextMenuPlacement.side(
        menuWidth: 226,
        anchorFrame: CGRect(x: 240, y: 100, width: 250, height: 90),
        leftContentEdge: 210,
        rightContentEdge: 1_030
    ) == .right)
    #expect(TaskCardContextMenuPlacement.side(
        menuWidth: 226,
        anchorFrame: CGRect(x: 500, y: 100, width: 250, height: 90),
        leftContentEdge: 210,
        rightContentEdge: 770
    ) == .left)

    let window = NSWindow(
        contentRect: CGRect(x: 100, y: 100, width: 900, height: 600),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    let anchor = NSView(frame: CGRect(x: 240, y: 360, width: 250, height: 90))
    window.contentView?.addSubview(anchor)
    var isPresented = false
    let binding = Binding(
        get: { isPresented },
        set: { isPresented = $0 }
    )
    let coordinator = TaskCardContextMenuAnchor<EmptyView>.Coordinator()
    coordinator.configure(isPresented: binding, onOpen: {}, content: AnyView(EmptyView()))
    coordinator.open(from: anchor)
    defer { coordinator.dismiss() }

    #expect(isPresented)
    #expect(coordinator.isVisible)
}
