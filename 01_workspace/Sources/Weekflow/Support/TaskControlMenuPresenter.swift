import AppKit
import SwiftUI

/// Presents a lightweight application-owned menu directly below a compact
/// task control. Unlike NSPopover, the surface, pointer, dismissal, and
/// selection behavior remain consistent with the task-card menus.
struct TaskControlMenuAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let menuSize: CGSize
    let horizontalOffset: CGFloat
    let pointerCenterX: CGFloat?
    private let content: Content

    init(
        isPresented: Binding<Bool>,
        menuSize: CGSize,
        horizontalOffset: CGFloat = 0,
        pointerCenterX: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.menuSize = menuSize
        self.horizontalOffset = horizontalOffset
        self.pointerCenterX = pointerCenterX
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TaskControlMenuProbeView {
        TaskControlMenuProbeView()
    }

    func updateNSView(_ nsView: TaskControlMenuProbeView, context: Context) {
        context.coordinator.configure(
            isPresented: $isPresented,
            menuSize: menuSize,
            horizontalOffset: horizontalOffset,
            pointerCenterX: pointerCenterX,
            content: AnyView(content)
        )
        if isPresented {
            context.coordinator.presentOrUpdate(from: nsView)
        } else {
            context.coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: TaskControlMenuProbeView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let pointerSize = CGSize(
            width: WeekflowLayout.taskDurationMenuPointerWidth,
            height: WeekflowLayout.taskDurationMenuPointerHeight
        )
        private var menuSize = CGSize(width: 176, height: 274)
        private var horizontalOffset: CGFloat = 0
        private var requestedPointerCenterX: CGFloat?
        private var panel: NSPanel?
        private var outsideClickMonitor: Any?
        private var scrollEventMonitor: Any?
        private var observedClipViews: [NSClipView] = []
        private var isPresented: Binding<Bool>?
        private var content: AnyView?
        private weak var anchor: NSView?
        private var hasAdjustedScrollForPresentation = false

        func configure(
            isPresented: Binding<Bool>,
            menuSize: CGSize,
            horizontalOffset: CGFloat,
            pointerCenterX: CGFloat?,
            content: AnyView
        ) {
            self.isPresented = isPresented
            self.menuSize = menuSize
            self.horizontalOffset = horizontalOffset
            requestedPointerCenterX = pointerCenterX
            self.content = content
        }

        func presentOrUpdate(from anchor: NSView) {
            guard let isPresented, let content, let window = anchor.window else { return }
            self.anchor = anchor
            let panelSize = CGSize(
                width: menuSize.width,
                height: menuSize.height + pointerSize.height
            )
            if !hasAdjustedScrollForPresentation {
                hasAdjustedScrollForPresentation = true
                if scrollToMakeRoomBelow(anchor: anchor, panelHeight: panelSize.height) {
                    DispatchQueue.main.async { [weak self, weak anchor] in
                        guard let self, let anchor else { return }
                        self.presentOrUpdate(from: anchor)
                    }
                    return
                }
            }

            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            let originX = anchorOnScreen.minX + horizontalOffset
            let originY = anchorOnScreen.minY - panelSize.height - 3
            let pointerCenterX = min(
                max(
                    requestedPointerCenterX ?? anchorOnScreen.midX - originX,
                    pointerSize.width / 2
                ),
                panelSize.width - pointerSize.width / 2
            )

            let surface = TaskControlMenuSurface(
                content: content,
                menuSize: menuSize,
                pointerSize: pointerSize,
                pointerCenterX: pointerCenterX
            )
            let hostingView = NSHostingView(rootView: surface)
            hostingView.frame = CGRect(origin: .zero, size: panelSize)

            let panel = panel ?? makePanel()
            panel.contentView = hostingView
            panel.setContentSize(panelSize)
            panel.setFrameOrigin(CGPoint(x: originX, y: originY))
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            self.panel = panel

            if outsideClickMonitor == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    guard isPresented.wrappedValue, self?.panel?.isVisible == true else { return }
                    self?.installOutsideClickMonitor(isPresented: isPresented)
                    self?.installScrollTracking()
                }
            }
        }

        func dismiss() {
            panel?.orderOut(nil)
            hasAdjustedScrollForPresentation = false
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
            if let scrollEventMonitor {
                NSEvent.removeMonitor(scrollEventMonitor)
                self.scrollEventMonitor = nil
            }
            for clipView in observedClipViews {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
            observedClipViews.removeAll()
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
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.hidesOnDeactivate = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
            return panel
        }

        private func installOutsideClickMonitor(isPresented: Binding<Bool>) {
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] event in
                guard let self, let panel = self.panel else { return event }
                guard event.window !== panel else { return event }
                if let anchor,
                   let window = anchor.window,
                   event.window === window {
                    let point = anchor.convert(event.locationInWindow, from: nil)
                    if anchor.bounds.contains(point) { return event }
                }
                isPresented.wrappedValue = false
                self.dismiss()
                return event
            }
        }

        private func installScrollTracking() {
            guard observedClipViews.isEmpty, let anchor else { return }
            observedClipViews = ancestorClipViews(of: anchor)
            for clipView in observedClipViews {
                clipView.postsBoundsChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(scrollViewBoundsDidChange),
                    name: NSView.boundsDidChangeNotification,
                    object: clipView
                )
            }
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self,
                      let panel,
                      event.window === anchor.window || event.window === panel else { return event }
                repositionPanel()
                DispatchQueue.main.async { [weak self] in
                    self?.repositionPanel()
                }
                return event
            }
            repositionPanel()
        }

        @objc private func scrollViewBoundsDidChange() {
            repositionPanel()
        }

        private func repositionPanel() {
            guard let anchor,
                  let window = anchor.window,
                  let panel else { return }
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            let panelSize = panel.frame.size
            let originX = anchorOnScreen.minX + horizontalOffset
            let originY = anchorOnScreen.minY - panelSize.height - 3
            let proposedPanelFrame = CGRect(
                origin: CGPoint(x: originX, y: originY),
                size: panelSize
            )
            guard isFullyVisible(
                anchorFrame: anchorOnScreen,
                panelFrame: proposedPanelFrame,
                in: window
            ) else {
                panel.orderOut(nil)
                return
            }
            panel.setFrameOrigin(proposedPanelFrame.origin)
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }

        private func ancestorClipViews(of view: NSView) -> [NSClipView] {
            var result: [NSClipView] = []
            var ancestor = view.superview
            while let current = ancestor {
                if let clipView = current as? NSClipView {
                    result.append(clipView)
                }
                ancestor = current.superview
            }
            return result
        }

        private func isFullyVisible(
            anchorFrame: CGRect,
            panelFrame: CGRect,
            in window: NSWindow
        ) -> Bool {
            for clipView in observedClipViews where clipView.window === window {
                let clipInWindow = clipView.convert(clipView.bounds, to: nil)
                let clipOnScreen = window.convertToScreen(clipInWindow)
                guard clipOnScreen.intersects(anchorFrame),
                      panelFrame.minY >= clipOnScreen.minY,
                      panelFrame.maxY <= clipOnScreen.maxY else { return false }
            }
            return true
        }

        private func scrollToMakeRoomBelow(anchor: NSView, panelHeight: CGFloat) -> Bool {
            guard let window = anchor.window,
                  let scrollView = anchor.enclosingScrollView,
                  let documentView = scrollView.documentView else { return false }
            let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorOnScreen = window.convertToScreen(anchorInWindow)
            let contentInWindow = window.contentView?.bounds ?? window.contentLayoutRect
            let contentOnScreen = window.convertToScreen(contentInWindow)
            let visibleScreenBottom = window.screen?.visibleFrame.minY ?? contentOnScreen.minY
            let usableBottom = max(contentOnScreen.minY, visibleScreenBottom) + 8
            let availableHeight = anchorOnScreen.minY - usableBottom - 3
            let shortage = panelHeight - availableHeight
            guard shortage > 0.5 else { return false }

            let clipView = scrollView.contentView
            let maximumOffset = max(documentView.bounds.height - clipView.bounds.height, 0)
            let currentOffset = clipView.bounds.origin.y
            let targetOffset = min(currentOffset + shortage + 8, maximumOffset)
            guard targetOffset > currentOffset + 0.5 else { return false }
            clipView.scroll(to: CGPoint(x: clipView.bounds.origin.x, y: targetOffset))
            scrollView.reflectScrolledClipView(clipView)
            return true
        }
    }
}

final class TaskControlMenuProbeView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct TaskControlMenuSurface: View {
    let content: AnyView
    let menuSize: CGSize
    let pointerSize: CGSize
    let pointerCenterX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: menuSize.width, height: menuSize.height, alignment: .topLeading)
                .background(WeekflowPalette.surface)
                .clipShape(WeekflowRoundedRectangle(cornerRadius: 7))
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 7)
                        .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
                .offset(y: pointerSize.height - 1)

            TaskDurationMenuPointer()
                .fill(WeekflowPalette.surface)
                .overlay {
                    TaskDurationMenuPointerOutline()
                        .stroke(WeekflowPalette.borderStrong.opacity(0.9), lineWidth: 1)
                }
                .frame(width: pointerSize.width, height: pointerSize.height)
                .position(x: pointerCenterX, y: pointerSize.height / 2)
        }
        .frame(
            width: menuSize.width,
            height: menuSize.height + pointerSize.height,
            alignment: .topLeading
        )
    }
}
