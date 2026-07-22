import SwiftUI

struct TaskDetailTarget: Identifiable {
    let goalID: UUID
    let taskID: UUID
    let isWeeklyGoalDetail: Bool
    let isNewWeeklyGoal: Bool
    var id: UUID { taskID }

    init(
        goalID: UUID,
        taskID: UUID,
        isWeeklyGoalDetail: Bool = false,
        isNewWeeklyGoal: Bool = false
    ) {
        self.goalID = goalID
        self.taskID = taskID
        self.isWeeklyGoalDetail = isWeeklyGoalDetail
        self.isNewWeeklyGoal = isNewWeeklyGoal
    }
}

struct TaskHistoryItem: Identifiable {
    let id: String
    let date: Date
    let title: String
}

enum TaskDetailMenu: Hashable {
    case channel
    case priority
    case startDate
    case dueDate
    case more
    case startTime
    case actualTime
    case estimatedTime
    case subtaskActualTime(UUID)
    case subtaskEstimatedTime(UUID)
}

enum TaskDetailMorePage {
    case actions
    case recurrence
    case goalLink
}

struct TaskDetailMenuAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [TaskDetailMenu: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TaskDetailMenu: Anchor<CGRect>],
        nextValue: () -> [TaskDetailMenu: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct TaskDetailSubtaskRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct TaskDetailTextWeightHover: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .fontWeight(isHovering ? .semibold : .medium)
            .foregroundStyle(
                isHovering ? WeekflowPalette.primaryText : WeekflowPalette.textMuted
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}

let taskDetailSubtaskCoordinateSpace = "task-detail-subtasks"
let taskDetailDragHandleWidth: CGFloat = 16
let taskDetailDragHandleLeadingOffset: CGFloat = -26

var taskDetailDragHandleCenterFromRowLeading: CGFloat {
    taskDetailDragHandleLeadingOffset + taskDetailDragHandleWidth / 2
}

struct TaskDetailDragHandle: View {
    let isVisible: Bool
    let isDragging: Bool

    var body: some View {
        VStack(spacing: 2.5) {
            dragDotRow
            dragDotRow
            dragDotRow
        }
        .frame(width: taskDetailDragHandleWidth, height: 28)
        .foregroundStyle(
            isDragging
                ? WeekflowPalette.objective
                : WeekflowPalette.textMuted.opacity(0.82)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? (isDragging ? 1.12 : 1) : 0.72)
        .offset(x: isVisible ? 0 : -3)
        .animation(.easeOut(duration: 0.14), value: isVisible)
        .animation(.easeInOut(duration: 0.16), value: isDragging)
    }

    private var dragDotRow: some View {
        HStack(spacing: 2.5) {
            Circle().frame(width: 2.5, height: 2.5)
            Circle().frame(width: 2.5, height: 2.5)
        }
    }
}

