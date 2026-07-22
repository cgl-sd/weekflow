import AppKit
import SwiftUI

struct TaskCardKeyboardShortcutAnchor: NSViewRepresentable {
    let isActive: Bool
    let copy: () -> Void
    let cut: () -> Void
    let paste: () -> Void
    let delete: () -> Void
    var moveToNextWeek: (() -> Void)? = nil

    func makeNSView(context: Context) -> TaskCardKeyboardShortcutProbeView {
        TaskCardKeyboardShortcutProbeView()
    }

    func updateNSView(_ nsView: TaskCardKeyboardShortcutProbeView, context: Context) {
        nsView.isActive = isActive
        nsView.copyAction = copy
        nsView.cutAction = cut
        nsView.pasteAction = paste
        nsView.deleteAction = delete
        nsView.moveToNextWeekAction = moveToNextWeek
        nsView.installMonitorIfNeeded()
    }

    static func dismantleNSView(
        _ nsView: TaskCardKeyboardShortcutProbeView,
        coordinator: Void
    ) {
        nsView.invalidateMonitor()
    }
}

final class TaskCardKeyboardShortcutProbeView: NSView {
    var isActive = false
    var copyAction: () -> Void = {}
    var cutAction: () -> Void = {}
    var pasteAction: () -> Void = {}
    var deleteAction: () -> Void = {}
    var moveToNextWeekAction: (() -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            invalidateMonitor()
        } else {
            installMonitorIfNeeded()
        }
    }

    func installMonitorIfNeeded() {
        guard eventMonitor == nil, window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.isActive,
                  !self.isEditingText(in: event.window) else { return event }
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
                .subtracting([.capsLock, .numericPad, .function])
            if modifiers == [.command] {
                switch (event.charactersIgnoringModifiers?.lowercased(), event.keyCode) {
                case ("c", _): copyAction()
                case ("x", _): cutAction()
                case ("v", _): pasteAction()
                case (_, 51), (_, 117): deleteAction()
                default: return event
                }
                return nil
            }
            if modifiers == [.command, .shift], event.keyCode == 124,
               let moveToNextWeekAction {
                moveToNextWeekAction()
                return nil
            }
            return event
        }
    }

    func invalidateMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func isEditingText(in window: NSWindow?) -> Bool {
        guard let textView = window?.firstResponder as? NSTextView else { return false }
        return textView.isEditable
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
