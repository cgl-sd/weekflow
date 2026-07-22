import AppKit
import SwiftUI

/// A narrow AppKit bridge for the one text-system behavior SwiftUI does not
/// expose reliably: detecting Backspace while the insertion point is at zero.
struct TaskDetailSubtaskTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var focusRequest: Int?
    let onSubmit: () -> Void
    let onDeleteAtStart: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 14)
        textField.textColor = .labelColor
        textField.placeholderString = placeholder
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }
        if textField.placeholderString != placeholder {
            textField.placeholderString = placeholder
        }
        if let focusRequest,
           context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                guard textField.window?.makeFirstResponder(textField) == true else { return }
                textField.currentEditor()?.selectedRange = NSRange(
                    location: textField.stringValue.utf16.count,
                    length: 0
                )
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TaskDetailSubtaskTextField
        var lastFocusRequest: Int?

        init(parent: TaskDetailSubtaskTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                let selection = textView.selectedRange()
                guard selection.location == 0, selection.length == 0 else { return false }
                parent.onDeleteAtStart()
                return true
            }
            return false
        }
    }
}
