import AppKit
import SwiftUI

private struct PointingHandCursorCoveredKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var pointingHandCursorIsCovered: Bool {
        get { self[PointingHandCursorCoveredKey.self] }
        set { self[PointingHandCursorCoveredKey.self] = newValue }
    }
}

/// The app-wide button primitive. Keeping the cursor region inside the
/// primitive means buttons in sheets, toolbars and custom popovers cannot
/// accidentally fall back to the arrow when their hover content changes.
struct WeekflowButton<Label: View>: View {
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    init(
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        SwiftUI.Button(role: role, action: action) {
            // Plain macOS buttons otherwise hit-test only the opaque parts of
            // their label (for example the strokes of an xmark).  Our hover
            // surfaces use the complete label bounds, so make the activation
            // surface use those same bounds as well.
            label
                .contentShape(Rectangle())
        }
        // Respect a larger explicit cursor surface when a styled button wraps
        // this primitive; otherwise install the primitive's own region.
        .pointingHandCursor(coversDescendants: false)
    }
}

extension WeekflowButton where Label == Text {
    init(
        _ titleKey: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) {
            Text(titleKey)
        }
    }

    init<S: StringProtocol>(
        _ title: S,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(role: role, action: action) {
            Text(verbatim: String(title))
        }
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pointingHandCursorIsCovered) private var isCovered

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled && !isCovered {
            if #available(macOS 15.0, *) {
                content.pointerStyle(.link)
            } else {
                content
                    .overlay {
                        PointingHandCursorRegion()
                    }
            }
        } else {
            content
        }
    }
}

private struct ContinuousPointingHandCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.pointingHandCursorIsCovered) private var isCovered

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled && !isCovered {
            if #available(macOS 15.0, *) {
                content
                    .environment(\.pointingHandCursorIsCovered, true)
                    .pointerStyle(.link)
            } else {
                content
                    .environment(\.pointingHandCursorIsCovered, true)
                    .overlay {
                        PointingHandCursorRegion()
                    }
            }
        } else {
            content
                .environment(\.pointingHandCursorIsCovered, true)
        }
    }
}

private struct StablePointingHandHoverModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    let hoverChanged: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            if #available(macOS 15.0, *) {
                content
                    .environment(\.pointingHandCursorIsCovered, true)
                    .pointerStyle(.link)
                    .overlay {
                        StablePointingHandHoverRegion(hoverChanged: hoverChanged)
                    }
            } else {
                content
                    .environment(\.pointingHandCursorIsCovered, true)
                    .overlay {
                        StablePointingHandHoverRegion(hoverChanged: hoverChanged)
                    }
            }
        } else {
            content
                .environment(\.pointingHandCursorIsCovered, true)
        }
    }
}

/// A narrow AppKit bridge for compact controls whose hover highlight must
/// survive the visual state update it triggers. On macOS 15+, SwiftUI's native
/// pointer style remains the cursor owner; this view owns only hover tracking.
private struct StablePointingHandHoverRegion: NSViewRepresentable {
    let hoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> StablePointingHandHoverView {
        StablePointingHandHoverView(hoverChanged: hoverChanged)
    }

    func updateNSView(_ nsView: StablePointingHandHoverView, context: Context) {
        nsView.hoverChanged = hoverChanged
    }
}

final class StablePointingHandHoverView: NSView {
    static let trackingOptions: NSTrackingArea.Options = [
        .activeInKeyWindow,
        .inVisibleRect,
        .mouseEnteredAndExited,
        .mouseMoved,
        .cursorUpdate
    ]

    var hoverChanged: (Bool) -> Void
    private var trackingArea: NSTrackingArea?

    init(hoverChanged: @escaping (Bool) -> Void) {
        self.hoverChanged = hoverChanged
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if #unavailable(macOS 15.0) {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let nextTrackingArea = NSTrackingArea(
            rect: .zero,
            options: Self.trackingOptions,
            owner: self
        )
        addTrackingArea(nextTrackingArea)
        trackingArea = nextTrackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        if #unavailable(macOS 15.0) {
            NSCursor.pointingHand.set()
        }
        hoverChanged(true)
    }

    override func mouseMoved(with event: NSEvent) {
        if #unavailable(macOS 15.0) {
            NSCursor.pointingHand.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if #unavailable(macOS 15.0) {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
        if window == nil {
            hoverChanged(false)
        }
    }
}

/// macOS 14 compatibility region. macOS 15 and newer use SwiftUI's native
/// pointer style, avoiding cursor ownership races while hover content changes.
private struct PointingHandCursorRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> PointingHandCursorView {
        PointingHandCursorView()
    }

    func updateNSView(_ nsView: PointingHandCursorView, context: Context) {}
}

/// Owns the cursor once per window instead of allowing each transient SwiftUI
/// overlay to compete with AppKit's default arrow cursor. Cursor rect handling
/// is disabled only while the pointer is inside a registered interactive
/// region, then re-enabled before AppKit processes the event that leaves it.
@MainActor
final class PointingHandCursorWindowController {
    private(set) weak var protectedWindow: NSWindow?

    func update(matchingWindow: NSWindow?) {
        if matchingWindow !== protectedWindow {
            releaseProtectedWindow()
            if let matchingWindow {
                matchingWindow.disableCursorRects()
                protectedWindow = matchingWindow
                NSCursor.pointingHand.set()
            }
        } else if matchingWindow != nil, NSCursor.current != .pointingHand {
            NSCursor.pointingHand.set()
        }
    }

    func releaseProtectedWindow() {
        guard let protectedWindow else { return }
        protectedWindow.enableCursorRects()
        self.protectedWindow = nil
    }
}

@MainActor
private final class PointingHandCursorCoordinator {
    static let shared = PointingHandCursorCoordinator()

    private let regions = NSHashTable<PointingHandCursorView>.weakObjects()
    private let windowController = PointingHandCursorWindowController()
    private var eventMonitor: Any?
    private var refreshScheduled = false
    private var pendingPointerLocation: NSPoint?

    private init() {}

    func register(_ region: PointingHandCursorView) {
        regions.add(region)
        installEventMonitorIfNeeded()
        requestRefresh()
    }

    func unregister(_ region: PointingHandCursorView) {
        regions.remove(region)
        if regions.allObjects.isEmpty {
            removeEventMonitor()
            windowController.releaseProtectedWindow()
        }
        requestRefresh()
    }

    func requestRefresh(at pointerLocation: NSPoint? = nil) {
        if let pointerLocation { pendingPointerLocation = pointerLocation }
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            let location = self.pendingPointerLocation ?? NSEvent.mouseLocation
            self.pendingPointerLocation = nil
            self.refreshCursor(at: location)
        }
    }

    private func installEventMonitorIfNeeded() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseEntered,
                .mouseExited,
                .mouseMoved,
                .leftMouseDown,
                .leftMouseUp,
                .leftMouseDragged,
                .rightMouseDown,
                .rightMouseUp,
                .rightMouseDragged
            ]
        ) { [weak self] event in
            let screenPoint = event.window.map {
                $0.convertPoint(toScreen: event.locationInWindow)
            } ?? NSEvent.mouseLocation
            self?.requestRefresh(at: screenPoint)
            return event
        }
    }

    private func removeEventMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func refreshCursor(at pointerLocation: NSPoint = NSEvent.mouseLocation) {
        let matchingWindow = regions.allObjects.lazy.compactMap { region in
            region.containsScreenPoint(pointerLocation) ? region.window : nil
        }.first
        windowController.update(matchingWindow: matchingWindow)
    }
}

final class PointingHandCursorView: NSView {
    static let trackingOptions: NSTrackingArea.Options = [
        .activeInKeyWindow,
        .inVisibleRect,
        .mouseEnteredAndExited,
        .mouseMoved
    ]

    private var registeredBoundsSize: NSSize = .zero
    private var cursorTrackingArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: Self.trackingOptions,
            owner: self
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
        super.updateTrackingAreas()
        schedulePointingHandRefresh()
    }

    override func mouseEntered(with event: NSEvent) {
        schedulePointingHandRefresh()
    }

    override func mouseMoved(with event: NSEvent) {
        schedulePointingHandRefresh()
    }

    override func mouseExited(with event: NSEvent) {
        schedulePointingHandRefresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registeredBoundsSize = bounds.size
        window?.invalidateCursorRects(for: self)
        if window == nil {
            PointingHandCursorCoordinator.shared.unregister(self)
        } else {
            PointingHandCursorCoordinator.shared.register(self)
        }
    }

    override func layout() {
        super.layout()
        guard bounds.size != registeredBoundsSize else { return }
        registeredBoundsSize = bounds.size
        window?.invalidateCursorRects(for: self)
        schedulePointingHandRefresh()
    }

    /// SwiftUI may restore the arrow while it reconciles a hover-driven view
    /// update. Refresh on the next main-loop turn so this AppKit region is the
    /// final cursor authority for the completed event, without using a cursor
    /// push/pop stack.
    private func schedulePointingHandRefresh() {
        PointingHandCursorCoordinator.shared.requestRefresh()
    }

    func containsScreenPoint(_ screenPoint: NSPoint) -> Bool {
        guard let window, !bounds.isEmpty, !isHiddenOrHasHiddenAncestor else {
            return false
        }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = convert(windowPoint, from: nil)
        return bounds.contains(localPoint) && visibleRect.contains(localPoint)
    }
}

extension View {
    /// Installs one non-intercepting AppKit cursor region over the complete
    /// interactive surface. Descendant regions are suppressed by default so a
    /// styled button cannot accidentally register both its primitive and its
    /// outer hover surface as competing cursor owners.
    @ViewBuilder
    func pointingHandCursor(coversDescendants: Bool = true) -> some View {
        if coversDescendants {
            modifier(ContinuousPointingHandCursorModifier())
        } else {
            modifier(PointingHandCursorModifier())
        }
    }

    /// Uses one stable AppKit region for both hover state and the pointing-hand
    /// cursor. Intended for compact navigation controls that redraw on hover.
    func stablePointingHandHover(
        _ hoverChanged: @escaping (Bool) -> Void
    ) -> some View {
        modifier(StablePointingHandHoverModifier(hoverChanged: hoverChanged))
    }
}
