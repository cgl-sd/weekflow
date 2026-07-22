import AppKit
import Observation
import SwiftUI

enum FocusStatusPanelPlacement {
    struct Result: Equatable {
        let origin: CGPoint
        let pointerOffset: CGFloat
    }

    static func resolve(
        statusItemFrame: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        screenMargin: CGFloat = 6,
        verticalGap: CGFloat = 2
    ) -> Result {
        let unclampedX = statusItemFrame.midX - panelSize.width / 2
        let minimumX = visibleFrame.minX + screenMargin
        let maximumX = visibleFrame.maxX - panelSize.width - screenMargin
        let originX = min(max(unclampedX, minimumX), max(minimumX, maximumX))
        let originY = statusItemFrame.minY - panelSize.height - verticalGap
        return Result(
            origin: CGPoint(x: originX.rounded(), y: originY.rounded()),
            pointerOffset: statusItemFrame.midX - (originX + panelSize.width / 2)
        )
    }
}

/// Owns the focus status item so its panel and pointer can share one exact
/// screen-space anchor. SwiftUI's MenuBarExtra intentionally keeps that
/// placement private, which made the system window drift relative to the item.
@MainActor
final class FocusStatusItemController: NSObject {
    private enum Metrics {
        static let contentWidth: CGFloat = 256
        static let horizontalShadowInset: CGFloat = 8
        static let bottomShadowInset: CGFloat = 8
        static let pointerHeight: CGFloat = 9
    }

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FocusStatusPanelSurface>?
    private var pointerOffset: CGFloat?
    private weak var timer: FocusTimerService?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var observationGeneration = 0

    func install(timer: FocusTimerService) {
        guard self.timer !== timer || statusItem == nil else { return }
        uninstall()
        self.timer = timer

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else {
            NSStatusBar.system.removeStatusItem(statusItem)
            return
        }
        button.target = self
        button.action = #selector(togglePanel(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.toolTip = "专注模式"
        self.statusItem = statusItem

        refreshStatusItem()
        observeTimerChanges(generation: observationGeneration)
    }

    func uninstall() {
        observationGeneration += 1
        dismiss()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        panel?.contentView = nil
        hostingView = nil
        pointerOffset = nil
        timer = nil
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if panel?.isVisible == true {
            dismiss()
        } else {
            present(from: sender)
        }
    }

    private func observeTimerChanges(generation: Int) {
        guard let timer, generation == observationGeneration else { return }
        withObservationTracking {
            _ = timer.isRunning
            _ = timer.selectedMode
            _ = timer.linkedTaskTitle
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.observationGeneration else { return }
                self.refreshStatusItem()
                DispatchQueue.main.async { [weak self] in
                    self?.repositionVisiblePanel()
                }
                self.observeTimerChanges(generation: generation)
            }
        }
    }

    private func refreshStatusItem() {
        guard let timer, let button = statusItem?.button else { return }
        button.title = ""
        let symbol = timer.isRunning ? timer.selectedMode.runningSymbol : timer.selectedMode.symbol
        button.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: timer.selectedMode.title
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        statusItem?.length = NSStatusItem.variableLength
    }

    private func repositionVisiblePanel() {
        guard let timer,
              let panel,
              panel.isVisible,
              let button = statusItem?.button else { return }
        button.window?.contentView?.layoutSubtreeIfNeeded()
        let targetSize = panelSize(for: timer)
        guard let placement = panelPlacement(
            from: button,
            panelSize: targetSize
        ) else { return }

        if panel.frame.size != targetSize {
            panel.setContentSize(targetSize)
            hostingView?.frame = CGRect(origin: .zero, size: targetSize)
        }
        updateHostedSurfaceIfNeeded(
            timer: timer,
            pointerOffset: placement.pointerOffset
        )
        panel.setFrameOrigin(placement.origin)
    }

    private func present(from button: NSStatusBarButton) {
        guard let timer else { return }
        let panelSize = panelSize(for: timer)
        guard let placement = panelPlacement(from: button, panelSize: panelSize) else { return }

        let panel = panel ?? makePanel()
        let hostingView = hostingView ?? makeHostingView(
            timer: timer,
            pointerOffset: placement.pointerOffset,
            size: panelSize
        )
        updateHostedSurfaceIfNeeded(
            timer: timer,
            pointerOffset: placement.pointerOffset
        )
        panel.contentView = hostingView
        panel.setContentSize(panelSize)
        hostingView.frame = CGRect(origin: .zero, size: panelSize)
        panel.setFrameOrigin(placement.origin)
        panel.orderFrontRegardless()
        self.panel = panel
        installOutsideClickMonitors()
    }

    private func panelPlacement(
        from button: NSStatusBarButton,
        panelSize: CGSize
    ) -> FocusStatusPanelPlacement.Result? {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return nil }
        let statusFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return FocusStatusPanelPlacement.resolve(
            statusItemFrame: statusFrame,
            panelSize: panelSize,
            visibleFrame: screen.visibleFrame
        )
    }

    private func makeHostingView(
        timer: FocusTimerService,
        pointerOffset: CGFloat,
        size: CGSize
    ) -> NSHostingView<FocusStatusPanelSurface> {
        let hostingView = NSHostingView(
            rootView: FocusStatusPanelSurface(
                timer: timer,
                pointerOffset: pointerOffset
            )
        )
        hostingView.frame = CGRect(origin: .zero, size: size)
        self.hostingView = hostingView
        self.pointerOffset = pointerOffset
        return hostingView
    }

    private func updateHostedSurfaceIfNeeded(
        timer: FocusTimerService,
        pointerOffset: CGFloat
    ) {
        guard let hostingView else { return }
        guard self.pointerOffset.map({ abs($0 - pointerOffset) > 0.25 }) ?? true else { return }
        hostingView.rootView = FocusStatusPanelSurface(
            timer: timer,
            pointerOffset: pointerOffset
        )
        self.pointerOffset = pointerOffset
    }

    private func panelSize(for timer: FocusTimerService) -> CGSize {
        let contentHeight: CGFloat = timer.linkedTaskTitle == nil ? 296 : 318
        return CGSize(
            width: Metrics.contentWidth + Metrics.horizontalShadowInset * 2,
            height: contentHeight + Metrics.pointerHeight + Metrics.bottomShadowInset
        )
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
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary, .canJoinAllSpaces]
        return panel
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, event.window !== self.panel else { return event }
            if let button = self.statusItem?.button,
               event.window === button.window {
                let pointInButton = button.convert(event.locationInWindow, from: nil)
                if button.bounds.contains(pointInButton) {
                    return event
                }
            }
            self.dismiss()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    private func dismiss() {
        panel?.orderOut(nil)
        removeOutsideClickMonitors()
    }

    private func removeOutsideClickMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }
}

struct FocusStatusPanelSurface: View {
    @Bindable var timer: FocusTimerService
    let pointerOffset: CGFloat

    var body: some View {
        VStack(spacing: -1) {
            FocusStatusPanelPointer()
                .fill(WeekflowPalette.floatingPanelSurface)
                .overlay {
                    FocusStatusPanelPointerOutline()
                        .stroke(WeekflowPalette.borderStrong.opacity(0.72), lineWidth: 1)
                }
                .frame(width: 18, height: 9)
                .offset(x: pointerOffset)
                .contentShape(FocusStatusPanelPointer())
                .zIndex(2)

            FocusMenuBarPanel(timer: timer)
                .clipShape(WeekflowRoundedRectangle(cornerRadius: 9))
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 9)
                        .stroke(WeekflowPalette.borderStrong.opacity(0.72), lineWidth: 1)
                }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}

private struct FocusStatusPanelPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

private struct FocusStatusPanelPointerOutline: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
    }
}
