import SwiftUI

private enum SidebarMetrics {
    static let sidebarHorizontalPadding: CGFloat = 22
    static let rowHorizontalPadding: CGFloat = 6
    static let rowIconWidth: CGFloat = 18
    static let rowIconTextSpacing: CGFloat = 8
    static let groupTitleLeadingPadding: CGFloat = 0
    static let groupRowSpacing: CGFloat = 0
    static let rowVisualSpacingInset: CGFloat = 1
    static let sectionSpacing: CGFloat = 18
    static let rowFontSize: CGFloat = 14
    static let rowMinHeight: CGFloat = 28
    static let completionFontSize: CGFloat = 10
    static let workspaceTitleFontSize: CGFloat = 18
}

private enum WorkspaceMenuPanel: Identifiable {
    case settings
    case analytics

    var id: Self { self }
    var title: String {
        switch self {
        case .settings: "设置"
        case .analytics: "分析统计"
        }
    }
    var symbol: String {
        switch self {
        case .settings: "gearshape"
        case .analytics: "chart.line.uptrend.xyaxis"
        }
    }
}

enum SidebarRowVisualState: Equatable {
    case normal
    case highlighted

    static func resolve(isSelected: Bool, isHovering: Bool) -> SidebarRowVisualState {
        isSelected || isHovering ? .highlighted : .normal
    }
}

struct AppSidebarView: View {
    @Bindable var store: WeekflowStore
    @Binding var destination: AppDestination
    @State private var activeMenuPanel: WorkspaceMenuPanel?
    @State private var isWorkspaceMenuPresented = false
    @State private var isWorkspaceHeaderHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: SidebarMetrics.sectionSpacing) {
                SidebarGroup(items: [.home, .focus], selection: $destination)
                SidebarGroup(title: "每日安排", items: [.dailyPlanning, .dailyShutdown], selection: $destination)
                SidebarGroup(title: "每周安排", items: [.weeklyPlanning, .weeklyReview], selection: $destination)
                SidebarGroup(title: "归档", items: [.archive, .trash], selection: $destination)
                Spacer(minLength: 72)
            }
            .padding(.top, 46)

            sidebarHeader
                .frame(height: 28, alignment: .topLeading)
                .zIndex(2)
        }
        .padding(.horizontal, SidebarMetrics.sidebarHorizontalPadding)
        // Align the workspace title with the toolbar controls and assistant rail.
        .padding(.top, 16)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WeekflowPalette.sidebar)
        .sheet(item: $activeMenuPanel) { panel in
            WorkspaceMenuSheet(panel: panel, store: store)
                .presentationBackground(.regularMaterial)
        }
    }

    private var sidebarHeader: some View {
        Button {
            isWorkspaceMenuPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("WeekFlow")
                    .font(.system(size: SidebarMetrics.workspaceTitleFontSize, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 7)
            .frame(minHeight: 28, alignment: .leading)
            .background(
                isWorkspaceHeaderHovering || isWorkspaceMenuPresented
                    ? WeekflowPalette.surfaceSelected
                    : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 7)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isWorkspaceHeaderHovering = $0 }
        .padding(.horizontal, -7)
        .overlay(alignment: .topLeading) {
            if isWorkspaceMenuPresented {
                WorkspaceMenuPopover(
                    open: openMenuPanel,
                    dismiss: { isWorkspaceMenuPresented = false }
                )
                .offset(y: 32)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
                .zIndex(30)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isWorkspaceMenuPresented)
        .animation(.easeInOut(duration: 0.1), value: isWorkspaceHeaderHovering)
        .accessibilityLabel("WeekFlow 菜单")
    }

    private func openMenuPanel(_ panel: WorkspaceMenuPanel) {
        isWorkspaceMenuPresented = false
        DispatchQueue.main.async {
            activeMenuPanel = panel
        }
    }
}

private struct WorkspaceMenuPopover: View {
    let open: (WorkspaceMenuPanel) -> Void
    let dismiss: () -> Void

    private let menuWidth: CGFloat = 176
    private let menuHeight: CGFloat = 72
    private let pointerHeight = WeekflowLayout.taskDurationMenuPointerHeight

    var body: some View {
        let menuFrame = CGRect(x: 0, y: pointerHeight, width: menuWidth, height: menuHeight)
        let headerFrame = CGRect(x: 0, y: -32, width: 118, height: 28)

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame, headerFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                WorkspaceMenuRow(panel: .settings) { open(.settings) }
                WorkspaceMenuRow(panel: .analytics) { open(.analytics) }
            }
            .padding(6)
            .frame(width: menuWidth, height: menuHeight, alignment: .topLeading)
            .workspacePopoverSurface(cornerRadius: 7)
            .offset(y: pointerHeight)

            WorkspaceMenuPointer(anchorX: 45)
        }
        .frame(width: menuWidth, height: menuHeight + pointerHeight, alignment: .topLeading)
    }
}

private struct WorkspaceMenuPointer: View {
    let anchorX: CGFloat

    var body: some View {
        TaskDurationMenuPointer()
            .fill(WeekflowPalette.surface)
            .overlay {
                TaskDurationMenuPointerOutline()
                    .stroke(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .frame(
                width: WeekflowLayout.taskDurationMenuPointerWidth,
                height: WeekflowLayout.taskDurationMenuPointerHeight
            )
            .position(
                x: anchorX,
                y: WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
            )
            .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
            .zIndex(2)
    }
}

private extension View {
    func workspacePopoverSurface(cornerRadius: CGFloat) -> some View {
        background(
            WeekflowPalette.surface,
            in: WeekflowRoundedRectangle(cornerRadius: cornerRadius)
        )
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
    }
}

private struct WorkspaceMenuRow: View {
    let panel: WorkspaceMenuPanel
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(panel.title, systemImage: panel.symbol)
                .font(.system(size: 14))
                .foregroundStyle(WeekflowPalette.primaryText)
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .padding(.horizontal, 8)
                .background(isHovering ? WeekflowPalette.selected : .clear, in: WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}

private struct WorkspaceMenuSheet: View {
    let panel: WorkspaceMenuPanel
    @Bindable var store: WeekflowStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            panelContent

            WindowOutsideClickMonitor(
                protectedRect: CGRect(origin: .zero, size: panelSize),
                dismissOnOtherWindows: true,
                action: { dismiss() }
            )
            .allowsHitTesting(false)
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
    }

    private var panelSize: CGSize {
        panel == .settings ? CGSize(width: 860, height: 620) : CGSize(width: 360, height: 220)
    }

    @ViewBuilder
    private var panelContent: some View {
        if panel == .settings {
            ChannelSettingsView(store: store, initialSection: .general)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Label("分析统计", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.title2.weight(.semibold))
                Text("分析统计将在这里展示本周完成率、任务投入时间和每日负荷。")
                Spacer()
                HStack {
                    Spacer()
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .pointingHandCursor()
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 360, height: 220, alignment: .topLeading)
        }
    }
}

private struct SidebarGroup: View {
    var title: String? = nil
    let items: [AppDestination]
    @Binding var selection: AppDestination

    var body: some View {
        VStack(alignment: .leading, spacing: SidebarMetrics.groupRowSpacing) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                    .padding(.leading, SidebarMetrics.groupTitleLeadingPadding)
                    .padding(.bottom, 2)
            }
            ForEach(items) { item in
                SidebarRow(item: item, selection: $selection)
            }
        }
    }
}

struct SidebarRow: View {
    let item: AppDestination
    @Binding var selection: AppDestination
    let forcedHover: Bool?
    @State private var isHovering = false

    init(
        item: AppDestination,
        selection: Binding<AppDestination>,
        forcedHover: Bool? = nil
    ) {
        self.item = item
        _selection = selection
        self.forcedHover = forcedHover
    }

    private var isSelected: Bool { selection == item }
    private var visualState: SidebarRowVisualState {
        .resolve(isSelected: isSelected, isHovering: forcedHover ?? isHovering)
    }
    private var isHighlighted: Bool { visualState == .highlighted }
    var body: some View {
        Button {
            selection = item
        } label: {
            HStack(spacing: SidebarMetrics.rowIconTextSpacing) {
                Image(systemName: item.symbol)
                    .font(.system(size: SidebarMetrics.rowFontSize, weight: .regular))
                    .frame(width: SidebarMetrics.rowIconWidth, alignment: .center)
                Text(item.rawValue)
                    .font(.system(size: SidebarMetrics.rowFontSize, weight: .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .foregroundStyle(isHighlighted ? WeekflowPalette.textPrimary : WeekflowPalette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowMinHeight, alignment: .leading)
            .padding(.horizontal, SidebarMetrics.rowHorizontalPadding)
            .background(
                isHighlighted ? WeekflowPalette.surfaceSelected : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 7)
            )
            .padding(.vertical, SidebarMetrics.rowVisualSpacingInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { hovering in
            guard forcedHover == nil else { return }
            withAnimation(.easeInOut(duration: 0.14)) { isHovering = hovering }
        }
        .accessibilityHint("打开\(item.rawValue)")
    }
}
