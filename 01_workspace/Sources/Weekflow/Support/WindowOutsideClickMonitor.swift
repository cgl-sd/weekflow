import AppKit
import SwiftUI

/// Observes clicks in the owning window while leaving normal SwiftUI hit testing intact.
/// Protected rectangles are expressed in this representable's local coordinates.
struct WindowOutsideClickMonitor: NSViewRepresentable {
    let protectedRects: [CGRect]
    let monitoredEventMask: NSEvent.EventTypeMask
    let dismissOnOtherWindows: Bool
    let action: () -> Void

    init(
        protectedRect: CGRect,
        monitoredEventMask: NSEvent.EventTypeMask = OutsideClickProbeView.monitoredEventMask,
        dismissOnOtherWindows: Bool = false,
        action: @escaping () -> Void
    ) {
        protectedRects = [protectedRect]
        self.monitoredEventMask = monitoredEventMask
        self.dismissOnOtherWindows = dismissOnOtherWindows
        self.action = action
    }

    init(
        protectedRects: [CGRect],
        monitoredEventMask: NSEvent.EventTypeMask = OutsideClickProbeView.monitoredEventMask,
        dismissOnOtherWindows: Bool = false,
        action: @escaping () -> Void
    ) {
        self.protectedRects = protectedRects
        self.monitoredEventMask = monitoredEventMask
        self.dismissOnOtherWindows = dismissOnOtherWindows
        self.action = action
    }

    func makeNSView(context: Context) -> OutsideClickProbeView {
        let view = OutsideClickProbeView()
        view.protectedRects = protectedRects
        view.monitoredEventMask = monitoredEventMask
        view.dismissOnOtherWindows = dismissOnOtherWindows
        view.action = action
        return view
    }

    func updateNSView(_ nsView: OutsideClickProbeView, context: Context) {
        nsView.protectedRects = protectedRects
        nsView.dismissOnOtherWindows = dismissOnOtherWindows
        nsView.action = action
        nsView.updateMonitoredEventMask(monitoredEventMask)
        nsView.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: OutsideClickProbeView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

final class OutsideClickProbeView: NSView {
    /// SwiftUI buttons commit on mouse-up. Observing that same phase keeps a
    /// stale/animated anchor from dismissing on mouse-down and letting the
    /// button reopen its menu when the click is released.
    static let monitoredEventMask: NSEvent.EventTypeMask = .leftMouseUp

    var protectedRects: [CGRect] = []
    var monitoredEventMask = OutsideClickProbeView.monitoredEventMask
    var dismissOnOtherWindows = false
    var action: () -> Void = {}
    private var eventMonitor: Any?
    private var mouseDownBeganInsideProtectedRect = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeMonitor()
        } else {
            installMonitorIfNeeded()
        }
    }

    func installMonitorIfNeeded() {
        guard eventMonitor == nil, window != nil else { return }
        let effectiveMask = monitoredEventMask.union(.leftMouseDown)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: effectiveMask) { [weak self] event in
            guard let self, let window = self.window else { return event }

            guard event.window === window else {
                if self.dismissOnOtherWindows {
                    DispatchQueue.main.async { [weak self] in self?.action() }
                }
                return event
            }

            let localPoint = self.convert(event.locationInWindow, from: nil)
            if event.type == .leftMouseDown {
                self.mouseDownBeganInsideProtectedRect = self.protectedRects.contains {
                    $0.contains(localPoint)
                }
                if self.monitoredEventMask.contains(.leftMouseDown),
                   !self.mouseDownBeganInsideProtectedRect {
                    DispatchQueue.main.async { [weak self] in self?.action() }
                }
                return event
            }

            let beganInsideProtectedRect = self.mouseDownBeganInsideProtectedRect
            self.mouseDownBeganInsideProtectedRect = false
            if Self.shouldDismiss(
                mouseDownBeganInsideProtectedRect: beganInsideProtectedRect,
                mouseUpAt: localPoint,
                protectedRects: self.protectedRects
            ) {
                DispatchQueue.main.async { [weak self] in self?.action() }
            }
            return event
        }
    }

    func updateMonitoredEventMask(_ newValue: NSEvent.EventTypeMask) {
        guard monitoredEventMask != newValue else { return }
        removeMonitor()
        monitoredEventMask = newValue
    }

    static func shouldDismiss(clickAt point: CGPoint, protectedRect: CGRect) -> Bool {
        shouldDismiss(clickAt: point, protectedRects: [protectedRect])
    }

    static func shouldDismiss(clickAt point: CGPoint, protectedRects: [CGRect]) -> Bool {
        !protectedRects.contains(where: { $0.contains(point) })
    }

    static func shouldDismiss(
        mouseDownBeganInsideProtectedRect: Bool,
        mouseUpAt point: CGPoint,
        protectedRects: [CGRect]
    ) -> Bool {
        !mouseDownBeganInsideProtectedRect
            && shouldDismiss(clickAt: point, protectedRects: protectedRects)
    }

    func removeMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
        mouseDownBeganInsideProtectedRect = false
    }
}
