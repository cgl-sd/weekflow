import AppKit
import SwiftUI

struct TitlebarSidebarToggle: NSViewRepresentable {
    @Binding var isCollapsed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            context.coordinator.installIfNeeded(from: view, isCollapsed: $isCollapsed)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            context.coordinator.installIfNeeded(from: nsView, isCollapsed: $isCollapsed)
            context.coordinator.update(isCollapsed: $isCollapsed)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.uninstall()
        }
    }

    @MainActor
    final class Coordinator {
        private weak var window: NSWindow?
        private var accessory: NSTitlebarAccessoryViewController?
        private var hostingView: NSHostingView<TitlebarToggleButton>?

        func installIfNeeded(from view: NSView, isCollapsed: Binding<Bool>) {
            guard let window = view.window else { return }

            if self.window === window, accessory != nil {
                update(isCollapsed: isCollapsed)
                return
            }

            uninstall()

            let hostingView = NSHostingView(rootView: TitlebarToggleButton(isCollapsed: isCollapsed))
            hostingView.frame = NSRect(x: 0, y: 0, width: 34, height: 28)

            let accessory = NSTitlebarAccessoryViewController()
            accessory.view = hostingView
            accessory.layoutAttribute = .left

            window.titleVisibility = .hidden
            window.addTitlebarAccessoryViewController(accessory)

            self.window = window
            self.accessory = accessory
            self.hostingView = hostingView
        }

        func update(isCollapsed: Binding<Bool>) {
            hostingView?.rootView = TitlebarToggleButton(isCollapsed: isCollapsed)
        }

        func uninstall() {
            if let accessory, let window,
               let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            accessory = nil
            hostingView = nil
            window = nil
        }

    }
}

private struct TitlebarToggleButton: View {
    @Binding var isCollapsed: Bool

    var body: some View {
        WeekflowButton {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        } label: {
            Image(systemName: isCollapsed ? "sidebar.trailing" : "sidebar.leading")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(WeekflowPalette.secondaryText)
        .help(isCollapsed ? "展开侧边栏" : "收起侧边栏")
        .accessibilityLabel(isCollapsed ? "展开侧边栏" : "收起侧边栏")
    }
}
