import AppKit
import SwiftUI

/// Registers the visible bounds of a foreground surface. Context-click probes
/// below that surface consult this registry before responding, so overlay
/// panels keep their normal interaction while covered content stays inert.
struct SecondaryClickOcclusionRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> SecondaryClickOcclusionView {
        SecondaryClickOcclusionView()
    }

    func updateNSView(_ nsView: SecondaryClickOcclusionView, context: Context) {
        SecondaryClickOcclusionRegistry.register(nsView)
    }

    static func dismantleNSView(_ nsView: SecondaryClickOcclusionView, coordinator: ()) {
        SecondaryClickOcclusionRegistry.unregister(nsView)
    }
}

final class SecondaryClickOcclusionView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            SecondaryClickOcclusionRegistry.unregister(self)
        } else {
            SecondaryClickOcclusionRegistry.register(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum SecondaryClickOcclusionRegistry {
    private static let views = NSHashTable<NSView>.weakObjects()

    static func register(_ view: NSView) {
        views.add(view)
    }

    static func unregister(_ view: NSView) {
        views.remove(view)
    }

    static func contains(_ locationInWindow: NSPoint, in window: NSWindow) -> Bool {
        views.allObjects.contains { view in
            guard view.window === window, !view.isHidden, view.alphaValue > 0 else { return false }
            return view.bounds.contains(view.convert(locationInWindow, from: nil))
        }
    }

    static func frames(in window: NSWindow) -> [CGRect] {
        views.allObjects.compactMap { view in
            guard view.window === window, !view.isHidden, view.alphaValue > 0 else { return nil }
            return view.convert(view.bounds, to: nil)
        }
    }
}
