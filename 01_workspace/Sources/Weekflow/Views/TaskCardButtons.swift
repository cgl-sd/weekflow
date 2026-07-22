import SwiftUI

struct TaskCardWidthPreferenceKey: PreferenceKey {
    static let defaultValue = WeekflowLayout.taskDatePopoverWidth

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

struct TaskCardPriorityButton: View {
    let priority: TaskPriority
    let showsBadge: Bool
    let help: String
    @Binding var isPopoverPresented: Bool
    let presentationAnchor: TaskCardPresentationAnchor?
    let selectPriority: (TaskPriority) -> Void
    let action: () -> Void
    @State private var hovering = false
    @AppStorage(TaskCardTypographyPreferences.metadataSizeKey)
    private var storedMetadataSize = TaskCardTypographyPreferences.defaultMetadataSize
    @AppStorage(TaskCardTypographyPreferences.iconSizeKey)
    private var storedIconSize = TaskCardTypographyPreferences.defaultIconSize

    var body: some View {
        WeekflowButton(action: action) {
            priorityLabel
            .foregroundStyle(
                showsBadge
                    ? priority.flagColor
                    : (hovering ? WeekflowPalette.iconHover : WeekflowPalette.textMuted)
            )
            .background(priorityBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering = $0 }
        .help(help)
    }

    @ViewBuilder
    private var priorityLabel: some View {
        if !showsBadge {
            Image(systemName: "flag")
                .font(.system(
                    size: iconSize,
                    weight: hovering ? .semibold : .regular
                ))
                .anchorPreference(
                    key: TaskDurationMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    presentationAnchor.map { [$0: anchor] } ?? [:]
                }
                .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                    priorityPopover
                }
                .frame(
                    width: WeekflowLayout.taskCardIconHitTarget,
                    height: WeekflowLayout.taskCardIconHitTarget,
                    alignment: .leading
                )
        } else {
            Text(priorityBadgeText)
                .font(.system(size: metadataSize, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: WeekflowLayout.taskCardIconHitTarget)
                .frame(height: WeekflowLayout.taskCardPriorityBadgeHeight)
                .anchorPreference(
                    key: TaskDurationMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    presentationAnchor.map { [$0: anchor] } ?? [:]
                }
                .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                    priorityPopover
                }
        }
    }

    private var priorityPopover: some View {
        TaskPriorityPopover(selectedPriority: priority, select: selectPriority)
    }

    @ViewBuilder
    private var priorityBackground: some View {
        if showsBadge {
            Capsule()
                .fill(priority.flagColor.opacity(hovering ? 0.18 : 0.10))
                .overlay(Capsule().stroke(priority.flagColor.opacity(0.62), lineWidth: 1))
        } else {
            Color.clear
        }
    }

    private var priorityBadgeText: String {
        switch priority {
        case .must: "紧急"
        case .should: "优先"
        case .later: "低"
        case .none: ""
        }
    }

    private var metadataSize: CGFloat {
        TaskCardTypographyPreferences.metadataSize(from: storedMetadataSize)
    }

    private var iconSize: CGFloat {
        TaskCardTypographyPreferences.iconSize(from: storedIconSize)
    }
}

/// Main tasks and subtasks intentionally share this exact completion control so
/// their symbol size, hit target and user typography adjustment cannot diverge.
struct TaskCardCompletionButton: View {
    let isCompleted: Bool
    let inactiveTint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        TaskCardIconButton(
            symbol: isCompleted ? "checkmark.circle.fill" : "checkmark.circle",
            tint: isCompleted ? WeekflowPalette.complete : inactiveTint,
            hoverSymbol: "checkmark.circle.fill",
            hoverTint: WeekflowPalette.complete,
            sizeAdjustment: TaskCardTypographyPreferences.completionIconSizeAdjustment,
            help: help,
            action: action
        )
    }
}

struct TaskCardIconButton: View {
    let symbol: String
    let tint: Color
    let hoverSymbol: String?
    let hoverTint: Color
    let sizeAdjustment: CGFloat
    let help: String
    let presentationAnchor: TaskCardPresentationAnchor?
    let action: () -> Void
    @State private var isHovering = false
    @AppStorage(TaskCardTypographyPreferences.iconSizeKey)
    private var storedIconSize = TaskCardTypographyPreferences.defaultIconSize

    init(
        symbol: String,
        tint: Color,
        hoverSymbol: String? = nil,
        hoverTint: Color = WeekflowPalette.iconHover,
        sizeAdjustment: CGFloat = 0,
        help: String,
        presentationAnchor: TaskCardPresentationAnchor? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.tint = tint
        self.hoverSymbol = hoverSymbol
        self.hoverTint = hoverTint
        self.sizeAdjustment = sizeAdjustment
        self.help = help
        self.presentationAnchor = presentationAnchor
        self.action = action
    }

    var body: some View {
        WeekflowButton(action: action) {
            Image(systemName: isHovering ? (hoverSymbol ?? symbol) : symbol)
                .font(.system(
                    size: iconSize + sizeAdjustment,
                    weight: isHovering ? .semibold : .regular
                ))
                .foregroundStyle(isHovering ? hoverTint : tint)
                .anchorPreference(
                    key: TaskDurationMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    presentationAnchor.map { [$0: anchor] } ?? [:]
                }
                .frame(
                    width: WeekflowLayout.taskCardIconHitTarget,
                    height: WeekflowLayout.taskCardIconHitTarget,
                    alignment: .leading
                )
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var iconSize: CGFloat {
        TaskCardTypographyPreferences.iconSize(from: storedIconSize)
    }
}
