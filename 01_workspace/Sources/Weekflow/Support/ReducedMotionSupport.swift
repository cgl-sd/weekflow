import SwiftUI

private struct WeekflowReducedMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            guard reduceMotion else { return }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }
}

extension View {
    /// One root-level policy covers every explicit hover, popup, drag and timer
    /// animation. `disablesAnimations` also prevents descendant `.animation`
    /// modifiers from reintroducing motion when macOS Reduce Motion is enabled.
    func weekflowReducedMotion() -> some View {
        modifier(WeekflowReducedMotionModifier())
    }
}
