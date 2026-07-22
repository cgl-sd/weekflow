import AppKit
import SwiftUI

enum TaskCardContextMenuSide: Equatable {
    case left
    case right
}

enum TaskCardContextMenuPlacement {
    static func side(
        menuWidth: CGFloat,
        anchorFrame: CGRect,
        leftContentEdge: CGFloat,
        rightContentEdge: CGFloat
    ) -> TaskCardContextMenuSide {
        let rightSpace = rightContentEdge - anchorFrame.maxX - 4
        let leftSpace = anchorFrame.minX - leftContentEdge - 4
        return rightSpace >= menuWidth || rightSpace >= leftSpace ? .right : .left
    }
}

struct TaskCardContextMenuAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    private let menuHeight: CGFloat
    private let onOpen: () -> Void
    private let content: Content

    init(
        isPresented: Binding<Bool>,
        menuHeight: CGFloat = 210,
        onOpen: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.menuHeight = menuHeight
        self.onOpen = onOpen
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TaskCardContextMenuProbeView {
        TaskCardContextMenuProbeView()
    }

    func updateNSView(_ nsView: TaskCardContextMenuProbeView, context: Context) {
        context.coordinator.configure(
            isPresented: $isPresented,
            menuHeight: menuHeight,
            onOpen: onOpen,
            content: AnyView(content)
        )
        nsView.action = { [weak coordinator = context.coordinator, weak nsView] in
            guard let nsView else { return }
            coordinator?.open(from: nsView)
        }
        nsView.installMonitorIfNeeded()

        if !isPresented {
            context.coordinator.dismiss()
        } else if !context.coordinator.isVisible {
            context.coordinator.present(
                from: nsView,
                isPresented: $isPresented,
                content: AnyView(content)
            )
        }
    }

    static func dismantleNSView(_ nsView: TaskCardContextMenuProbeView, coordinator: Coordinator) {
        nsView.invalidateMonitor()
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        private var menuHeight: CGFloat = 210
        private var menuSize: CGSize { CGSize(width: 226, height: menuHeight) }
        private var panel: NSPanel?
        private var localEventMonitor: Any?
        private var isPresented: Binding<Bool>?
        private var onOpen: (() -> Void)?
        private var content: AnyView?

        var isVisible: Bool { panel?.isVisible == true }

        func configure(
            isPresented: Binding<Bool>,
            menuHeight: CGFloat = 210,
            onOpen: @escaping () -> Void,
            content: AnyView
        ) {
            self.isPresented = isPresented
            self.menuHeight = menuHeight
            self.onOpen = onOpen
            self.content = content
        }

        func open(from anchor: NSView) {
            guard let isPresented, let content else { return }
            onOpen?()
            isPresented.wrappedValue = true
            present(from: anchor, isPresented: isPresented, content: content)
        }

        func present(
            from anchor: NSView,
            isPresented: Binding<Bool>,
            content: AnyView
        ) {
            guard let window = anchor.window else { return }
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let windowContentInWindow = window.contentView?.bounds ?? window.contentLayoutRect
            let windowContentOnScreen = window.convertToScreen(windowContentInWindow)
            let occlusionFrames = SecondaryClickOcclusionRegistry.frames(in: window)
                .map(window.convertToScreen)
            let rightContentEdge = occlusionFrames
                .filter { $0.minX >= anchorOnScreen.maxX }
                .map(\.minX)
                .min()
                ?? (windowContentOnScreen.maxX - WeekflowLayout.assistantRailWidth)
            let leftContentEdge = windowContentOnScreen.minX
            let side = TaskCardContextMenuPlacement.side(
                menuWidth: menuSize.width,
                anchorFrame: anchorOnScreen,
                leftContentEdge: leftContentEdge,
                rightContentEdge: rightContentEdge
            )
            let presentsOnRight = side == .right

            let proposedX = presentsOnRight
                ? anchorOnScreen.maxX + 4
                : anchorOnScreen.minX - menuSize.width - 4
            let origin = CGPoint(
                x: min(
                    max(proposedX, visibleFrame.minX + 6),
                    visibleFrame.maxX - menuSize.width - 6
                ),
                y: min(
                    max(anchorOnScreen.maxY - menuSize.height + 8, visibleFrame.minY + 6),
                    visibleFrame.maxY - menuSize.height - 6
                )
            )

            let surface = TaskCardContextMenuSurface(
                content: content,
                pointerOnRight: !presentsOnRight,
                menuHeight: menuHeight
            )
            let hostingView = NSHostingView(rootView: surface)
            hostingView.frame = CGRect(origin: .zero, size: menuSize)

            let panel = panel ?? makePanel()
            panel.contentView = hostingView
            panel.setContentSize(menuSize)
            panel.setFrameOrigin(origin)
            panel.orderFrontRegardless()
            self.panel = panel
            // Install after the context-click that opened the panel has fully
            // left AppKit's local-monitor chain; otherwise the opening event
            // can be mistaken for an outside click and close the panel again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard isPresented.wrappedValue, self?.panel?.isVisible == true else { return }
                self?.installOutsideClickMonitor(isPresented: isPresented)
            }
        }

        func dismiss() {
            panel?.orderOut(nil)
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
                self.localEventMonitor = nil
            }
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
            panel.level = .popUpMenu
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            return panel
        }

        private func installOutsideClickMonitor(isPresented: Binding<Bool>) {
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
            }
            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                guard event.window !== panel else { return event }
                isPresented.wrappedValue = false
                self.dismiss()
                return event
            }
        }
    }
}

final class TaskCardContextMenuProbeView: NSView {
    var action: () -> Void = {}
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

    func invalidateMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct TaskCardContextMenuSurface: View {
    let content: AnyView
    let pointerOnRight: Bool
    let menuHeight: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !pointerOnRight { pointer(pointsRight: false) }

            content
                .frame(width: 218, height: menuHeight, alignment: .top)
                .background(
                    WeekflowPalette.surface,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .clipShape(WeekflowRoundedRectangle(cornerRadius: 7))
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 7)
                        .stroke(WeekflowPalette.border.opacity(0.82), lineWidth: 1)
                }

            if pointerOnRight {
                pointer(pointsRight: true)
            }
        }
        .frame(width: 226, height: menuHeight, alignment: .topLeading)
    }

    private func pointer(pointsRight: Bool) -> some View {
        TaskCardContextPointer()
            .fill(WeekflowPalette.surface)
            .frame(width: 8, height: 16)
            .rotationEffect(pointsRight ? .degrees(180) : .zero)
            .padding(.top, 14)
    }
}

private struct TaskCardContextPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
