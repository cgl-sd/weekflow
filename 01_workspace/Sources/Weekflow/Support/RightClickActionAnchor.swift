import AppKit
import SwiftUI

/// Detects a secondary click across the full bounds of its SwiftUI host without
/// placing an AppKit view above the card or disturbing primary-click gestures.
struct RightClickActionAnchor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> RightClickProbeView {
        let view = RightClickProbeView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: RightClickProbeView, context: Context) {
        nsView.action = action
        nsView.installMonitorIfNeeded()
    }

    static func dismantleNSView(_ nsView: RightClickProbeView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

final class RightClickProbeView: NSView {
    var action: () -> Void = {}
    private var eventMonitor: Any?

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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  event.window === window else { return event }

            if SecondaryClickOcclusionRegistry.contains(event.locationInWindow, in: window) {
                return event
            }

            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }
            DispatchQueue.main.async { [weak self] in self?.action() }
            return nil
        }
    }

    func removeMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}
