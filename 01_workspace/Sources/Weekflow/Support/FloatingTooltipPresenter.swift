import AppKit
import SwiftUI

/// Screen-safe geometry for the tooltip's separate AppKit window.
/// Keeping this calculation free of window state makes all four screen edges
/// testable without presenting an `NSPanel`.
enum FloatingTooltipPositioning {
    static let gap: CGFloat = 9
    static let screenInset: CGFloat = 6
    static let maximumWidth: CGFloat = 280

    struct Placement: Equatable {
        let origin: CGPoint
        let size: CGSize
        let isAboveAnchor: Bool
    }

    static func placement(
        anchorFrame: CGRect,
        requestedSize: CGSize,
        visibleFrame: CGRect
    ) -> Placement {
        let availableWidth = max(0, visibleFrame.width - screenInset * 2)
        let availableHeight = max(0, visibleFrame.height - screenInset * 2)
        let size = CGSize(
            width: min(maximumWidth, availableWidth, max(0, requestedSize.width)),
            height: min(availableHeight, max(0, requestedSize.height))
        )

        let minimumX = visibleFrame.minX + screenInset
        let maximumX = max(minimumX, visibleFrame.maxX - screenInset - size.width)
        let centeredX = anchorFrame.midX - size.width / 2
        let x = min(max(centeredX, minimumX), maximumX)

        let minimumY = visibleFrame.minY + screenInset
        let maximumY = max(minimumY, visibleFrame.maxY - screenInset - size.height)
        let belowY = anchorFrame.minY - gap - size.height
        let aboveY = anchorFrame.maxY + gap
        let fitsBelow = belowY >= minimumY
        let fitsAbove = aboveY <= maximumY

        // The normal position is below the control. Near the lower screen edge
        // it flips above; if neither side fully fits, the selected side is
        // clamped into the visible frame instead of leaving the display.
        let isAboveAnchor = !fitsBelow && (fitsAbove || aboveY > belowY)
        let proposedY = isAboveAnchor ? aboveY : belowY
        let y = min(max(proposedY, minimumY), maximumY)

        return Placement(
            origin: CGPoint(x: x, y: y),
            size: size,
            isAboveAnchor: isAboveAnchor
        )
    }
}

/// Presents the task-composer help bubble above macOS popover windows.
/// SwiftUI z-indexing cannot cross the separate window used by `popover`, so
/// this deliberately small AppKit bridge owns only the transient tooltip panel.
struct FloatingTooltipAnchor: NSViewRepresentable {
    let isPresented: Bool
    let text: String
    let shortcut: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented else {
            context.coordinator.dismiss()
            return
        }
        DispatchQueue.main.async {
            context.coordinator.present(from: nsView, text: text, shortcut: shortcut)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?

        func present(from anchor: NSView, text: String, shortcut: String?) {
            guard let window = anchor.window else { return }

            let bubble = FloatingTooltipBubble(text: text, shortcut: shortcut)
            let hostingView = NSHostingView(rootView: bubble)
            let fittingSize = hostingView.fittingSize

            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            let visibleFrame = window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? anchorOnScreen.insetBy(dx: -1_000, dy: -1_000)
            let placement = FloatingTooltipPositioning.placement(
                anchorFrame: anchorOnScreen,
                requestedSize: fittingSize,
                visibleFrame: visibleFrame
            )

            hostingView.frame = NSRect(origin: .zero, size: placement.size)

            let panel = panel ?? makePanel()
            panel.contentView = hostingView
            panel.setContentSize(placement.size)
            panel.setFrameOrigin(placement.origin)
            panel.orderFrontRegardless()
            self.panel = panel
        }

        func dismiss() {
            panel?.orderOut(nil)
        }

        private func makePanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: true
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            return panel
        }
    }
}

private struct FloatingTooltipBubble: View {
    let text: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 7) {
            Text(text)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(WeekflowPalette.canvas, in: WeekflowRoundedRectangle(cornerRadius: 4))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(WeekflowPalette.primaryText)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(WeekflowPalette.surfaceSelected, in: WeekflowRoundedRectangle(cornerRadius: 5))
        .frame(height: WeekflowLayout.composerTooltipHeight)
        .frame(maxWidth: FloatingTooltipPositioning.maximumWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
