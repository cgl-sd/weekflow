import SwiftUI

struct TaskCardContextPopover: View {
    let hasStartTime: Bool
    let addToCalendar: () -> Void
    let addToCalendarAt: (Int) -> Void
    let clearFromCalendar: () -> Void
    let moveToBacklog: () -> Void
    let moveToTopOfBacklog: () -> Void
    let copy: () -> Void
    let cut: () -> Void
    let paste: () -> Void
    let canPaste: Bool
    let delete: () -> Void

    @State private var showsTimeChoices = false

    var body: some View {
        Group {
            if showsTimeChoices {
                timeChoices
            } else {
                actionMenu
            }
        }
        .frame(width: 218)
        .background(WeekflowPalette.surface)
    }

    private var actionMenu: some View {
        VStack(spacing: 1) {
            row(
                symbol: "calendar.badge.plus",
                title: "添加到日历",
                trailing: hasStartTime ? "X" : "›"
            ) {
                if hasStartTime {
                    addToCalendar()
                } else {
                    showsTimeChoices = true
                }
            }

            row(
                symbol: "calendar.badge.minus",
                title: "从日历移除",
                trailing: "⌘  X",
                isEnabled: hasStartTime
            ) {
                clearFromCalendar()
            }

            row(symbol: "tray.and.arrow.down", title: "移入待办箱", trailing: "Z   ›") {
                moveToBacklog()
            }

            row(symbol: "tray.and.arrow.up", title: "移到待办箱顶部", trailing: "⇧  Z") {
                moveToTopOfBacklog()
            }

            row(symbol: "doc.on.doc", title: "复制", trailing: "⌘  C") {
                copy()
            }

            row(symbol: "scissors", title: "剪切", trailing: "⌘  X") {
                cut()
            }

            row(
                symbol: "doc.on.clipboard",
                title: "粘贴",
                trailing: "⌘  V",
                isEnabled: canPaste
            ) {
                paste()
            }

            row(
                symbol: "trash",
                title: "删除",
                trailing: "⌘  ⌫"
            ) {
                delete()
            }
        }
        .padding(6)
    }

    private var timeChoices: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    showsTimeChoices = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Text("选择开始时间")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
            }
            .foregroundStyle(WeekflowPalette.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(stride(from: 360, through: 1_440, by: 30)), id: \.self) { minute in
                        Button {
                            addToCalendarAt(minute)
                        } label: {
                            Text(String(format: "%02d:%02d", minute / 60, minute % 60))
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(WeekflowPalette.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .padding(.horizontal, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ContextMenuRowButtonStyle())
                        .pointingHandCursor()
                    }
                }
                .padding(5)
            }
            .frame(height: 160)
        }
    }

    private func row(
        symbol: String,
        title: String,
        trailing: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isDestructive ? WeekflowPalette.danger : WeekflowPalette.textMuted)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(isDestructive ? WeekflowPalette.danger : WeekflowPalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: title == "移到待办箱顶部" ? 38 : 32)
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(ContextMenuRowButtonStyle())
        .pointingHandCursor()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct WeeklyGoalContextPopover: View {
    let copy: () -> Void
    let cut: () -> Void
    let paste: () -> Void
    let canPaste: Bool
    let delete: () -> Void
    let moveToNextWeek: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            row(symbol: "doc.on.doc", title: "复制", trailing: "⌘  C", action: copy)
            row(symbol: "scissors", title: "剪切", trailing: "⌘  X", action: cut)
            row(
                symbol: "doc.on.clipboard",
                title: "粘贴",
                trailing: "⌘  V",
                isEnabled: canPaste,
                action: paste
            )
            row(symbol: "trash", title: "删除", trailing: "⌘  ⌫", action: delete)
            row(
                symbol: "arrow.right.circle",
                title: "移动到下一周",
                trailing: "⇧⌘  →",
                action: moveToNextWeek
            )
        }
        .padding(6)
        .frame(width: 218)
        .background(WeekflowPalette.surface)
    }

    private func row(
        symbol: String,
        title: String,
        trailing: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                Spacer(minLength: 8)
                if !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(ContextMenuRowButtonStyle())
        .pointingHandCursor()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.42)
    }
}

struct ContextMenuRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? WeekflowPalette.surfaceSelected
                    : (isHovering ? WeekflowPalette.surfaceHover : .clear),
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .onHover { isHovering = $0 }
    }
}
