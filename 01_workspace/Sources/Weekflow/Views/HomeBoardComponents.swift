import SwiftUI

struct TaskDurationMenuOverflowPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        guard let next = nextValue() else { return }
        value = max(value ?? 0, next)
    }
}

struct TaskTimerDividerPointerOverlay: View {
    let taskID: UUID
    let anchors: [TaskCardPresentationAnchor: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let timerAnchor = anchors[.timerButton(taskID)],
               let dividerAnchor = anchors[.timerDivider(taskID)] {
                pointer(
                    timerFrame: proxy[timerAnchor],
                    dividerFrame: proxy[dividerAnchor]
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func pointer(timerFrame: CGRect, dividerFrame: CGRect) -> some View {
        TaskDurationMenuPointer()
            .fill(WeekflowPalette.surface)
            .overlay {
                TaskDurationMenuPointerOutline()
                    .stroke(WeekflowPalette.borderStrong.opacity(0.9), lineWidth: 1)
            }
            .frame(
                width: WeekflowLayout.taskTimerDividerPointerWidth,
                height: WeekflowLayout.taskTimerDividerPointerHeight
            )
            .position(
                x: timerFrame.midX,
                y: dividerFrame.midY
                    - WeekflowLayout.taskTimerDividerPointerHeight / 2
                    + 0.5
            )
    }
}

/// The date bubble normally has a complete outline. When its trailing edge is
/// exactly shared with the visible native scroller, only that vertical segment
/// is omitted so the scroller line can act as the menu boundary.
struct TaskDateMenuBorder: Shape {
    let cornerRadius: CGFloat
    let hidesTrailingEdge: Bool

    func path(in rect: CGRect) -> Path {
        guard hidesTrailingEdge else {
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        }

        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

struct HomeDayProgressBar: View {
    let progress: DailyTaskProgress

    var body: some View {
        WeekflowDailyProgressTrack(
            fraction: progress.fraction,
            hasProgress: progress.isVisible,
            accessibilityLabel: "当天完成进度",
            accessibilityValue: "已完成 \(progress.completedTaskCount) 项，共 \(progress.totalTaskCount) 项"
        )
    }
}

struct DailyPlanButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        WeekflowButton(action: action) {
            Label("计划", systemImage: "calendar.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(WeekflowPalette.objective, in: WeekflowRoundedRectangle(cornerRadius: 7))
                .shadow(color: WeekflowPalette.objective.opacity(0.25), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .pointingHandCursor(coversDescendants: true)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .help("计划这一天")
        .accessibilityHidden(!isVisible)
    }
}

struct HomeAddTaskButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @AppStorage(TaskCardTypographyPreferences.taskTextSizeKey)
    private var storedTaskTextSize = TaskCardTypographyPreferences.defaultTaskTextSize

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("添加任务")
                    .font(.system(size: taskTextSize, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: WeekflowLayout.homeAddTaskHeight, alignment: .leading)
            .padding(.horizontal, 14)
            .boxHoverChrome(isHovering: isHovering, cornerRadius: 8)
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help("给这一天添加任务")
    }

    private var taskTextSize: CGFloat {
        TaskCardTypographyPreferences.taskTextSize(from: storedTaskTextSize)
    }
}

