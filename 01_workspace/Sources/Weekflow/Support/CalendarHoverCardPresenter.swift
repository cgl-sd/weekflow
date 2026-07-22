import AppKit
import SwiftUI

struct CalendarHoverCardModel {
    let title: String
    let timeRange: String
    let calendarName: String
    let channelName: String
    let color: Color
    let priority: TaskPriority?
    let isCommitted: Bool
    let isTask: Bool
}

struct CalendarHoverCardAnchor: NSViewRepresentable {
    let isPresented: Bool
    let model: CalendarHoverCardModel
    let openTask: () -> Void
    let pinTask: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isPresented else {
            context.coordinator.scheduleDismiss()
            return
        }
        DispatchQueue.main.async {
            context.coordinator.present(
                from: nsView,
                model: model,
                openTask: openTask,
                pinTask: pinTask
            )
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismissImmediately()
    }

    @MainActor
    final class Coordinator {
        private var panel: NSPanel?
        private var dismissWorkItem: DispatchWorkItem?
        private let cardSize = CGSize(width: 148, height: 136)
        private let pointerWidth: CGFloat = 8
        private let gap: CGFloat = 2

        func present(
            from anchor: NSView,
            model: CalendarHoverCardModel,
            openTask: @escaping () -> Void,
            pinTask: (() -> Void)?
        ) {
            guard let window = anchor.window else { return }
            dismissWorkItem?.cancel()
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let fullWidth = cardSize.width + pointerWidth
            let fitsLeft = anchorOnScreen.minX - gap - fullWidth >= visibleFrame.minX + 8
            let cardIsLeft = fitsLeft
            let x = cardIsLeft
                ? anchorOnScreen.minX - gap - fullWidth
                : min(anchorOnScreen.maxX + gap, visibleFrame.maxX - fullWidth - 8)
            let y = min(
                max(anchorOnScreen.maxY + 8 - cardSize.height, visibleFrame.minY + 8),
                visibleFrame.maxY - cardSize.height - 8
            )

            let content = CalendarHoverCard(
                model: model,
                pointerOnRight: cardIsLeft,
                openTask: { [weak self] in
                    self?.dismissImmediately()
                    openTask()
                },
                pinTask: {
                    pinTask?()
                },
                hoverChanged: { [weak self] hovering in
                    if hovering {
                        self?.dismissWorkItem?.cancel()
                    } else {
                        self?.scheduleDismiss()
                    }
                }
            )
            let hostingView = NSHostingView(rootView: content)
            let size = CGSize(width: fullWidth, height: cardSize.height)
            hostingView.frame = CGRect(origin: .zero, size: size)

            let panel = panel ?? makePanel()
            panel.contentView = hostingView
            panel.setContentSize(size)
            panel.setFrameOrigin(CGPoint(x: x, y: y))
            panel.orderFrontRegardless()
            self.panel = panel
        }

        func scheduleDismiss() {
            dismissWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.panel?.orderOut(nil)
            }
            dismissWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: item)
        }

        func dismissImmediately() {
            dismissWorkItem?.cancel()
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
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            return panel
        }
    }
}

struct CalendarHoverCard: View {
    let model: CalendarHoverCardModel
    let pointerOnRight: Bool
    let openTask: () -> Void
    let pinTask: () -> Void
    let hoverChanged: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !pointerOnRight { pointer(pointsRight: false) }
            card
            if pointerOnRight { pointer(pointsRight: true) }
        }
        .onHover { hovering in
            isHovering = hovering
            hoverChanged(hovering)
        }
    }

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            WeekflowButton(action: openTask) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 32)

                    Text(model.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .lineLimit(2)
                        .padding(.bottom, 8)

                    detailRow(symbol: "clock", text: model.timeRange)
                    detailRow(symbol: "number", text: model.channelName, tint: model.color)
                }
                .padding(9)
                .frame(width: 148, height: 136, alignment: .topLeading)
            }
            .buttonStyle(.plain)
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .pointingHandCursor()

            HStack(spacing: 6) {
                priorityLabel
                Spacer(minLength: 4)
                if model.isTask {
                    WeekflowButton(action: pinTask) {
                        Image(systemName: model.isCommitted ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(model.isCommitted ? model.color : WeekflowPalette.textSecondary)
                            .frame(width: 27, height: 27)
                            .background(WeekflowPalette.surfaceHover, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(model.isCommitted ? "取消固定" : "固定到日历")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 148, height: 136, alignment: .topLeading)
        .background(
            isHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surface,
            in: WeekflowRoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 9)
                .stroke(WeekflowPalette.border.opacity(0.75), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var priorityLabel: some View {
        if let priority = model.priority {
            if priority == .none {
                Image(systemName: "flag")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .frame(width: 27, height: 27)
            } else {
                Text(priority.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(priority.flagColor)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(priority.flagColor.opacity(0.10), in: Capsule())
                    .overlay {
                        Capsule().stroke(priority.flagColor.opacity(0.62), lineWidth: 1)
                    }
            }
        }
    }

    private func pointer(pointsRight: Bool) -> some View {
        CalendarHoverPointer()
            .fill(WeekflowPalette.surface)
            .frame(width: 8, height: 16)
            .rotationEffect(pointsRight ? .zero : .degrees(180))
            .padding(.top, 14)
    }

    private func detailRow(symbol: String, text: String, tint: Color = WeekflowPalette.textSecondary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 15)
            Text(text)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(WeekflowPalette.textSecondary)
                .lineLimit(1)
        }
        .frame(height: 21)
    }
}

private struct CalendarHoverPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
