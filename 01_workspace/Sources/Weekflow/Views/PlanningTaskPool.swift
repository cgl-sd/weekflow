import SwiftUI

struct PlanningTaskPool: View {
    @Bindable var store: WeekflowStore
    let targetDate: Date?
    let assignmentDate: Date
    var fillsAvailableHeight = false
    let dragStarted: (TaskDragToken) -> Void
    let taskAssigned: (UUID) -> Void
    private let contentInset: CGFloat = 12
    private let cardWidthReduction: CGFloat = 10
    @State private var verticalScrollerTrackWidth = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: .legacy
    )

    private var poolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        store.weeklyPlanningPoolEntries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "tray")
                    .foregroundStyle(WeekflowPalette.iconDefault)
                Text("来自每周计划的任务池")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, contentInset)

            if poolEntries.isEmpty {
                Text("任务池为空，可在每周计划中添加任务。")
                    .font(.system(size: 11))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .padding(.vertical, 12)
                    .padding(.horizontal, contentInset)
            } else {
                GeometryReader { proxy in
                    let cardWidth = max(
                        proxy.size.width - verticalScrollerTrackWidth - cardWidthReduction,
                        1
                    )
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 7) {
                            ForEach(poolEntries, id: \.task.id) { entry in
                                PlanningTaskPoolCard(
                                    entry: entry,
                                    assignedToTarget: targetDate.map { entry.task.isAssigned(on: $0) } ?? false,
                                    store: store,
                                    dragStarted: dragStarted,
                                    assignToTarget: {
                                        if assignPlanningPoolTaskToBottom(
                                            store: store,
                                            goalID: entry.goal.id,
                                            taskID: entry.task.id,
                                            date: assignmentDate
                                        ) {
                                            taskAssigned(entry.task.id)
                                        }
                                    },
                                    removeFromTarget: {
                                        store.removeTaskAssignment(
                                            goalID: entry.goal.id,
                                            taskID: entry.task.id,
                                            from: assignmentDate
                                        )
                                    }
                                )
                            }
                        }
                        .frame(width: cardWidth, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(
                            ZeroInsetVerticalScroller(
                                isVisible: true,
                                columnWidth: proxy.size.width,
                                scrollRequest: nil,
                                onTrackWidthChange: { measuredWidth in
                                    guard abs(verticalScrollerTrackWidth - measuredWidth) >= 0.5 else {
                                        return
                                    }
                                    verticalScrollerTrackWidth = measuredWidth
                                }
                            )
                        )
                    }
                }
                .frame(maxHeight: fillsAvailableHeight ? .infinity : 220)
                .padding(.leading, contentInset)
                .padding(.bottom, contentInset)
            }
        }
        .padding(.top, contentInset)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 9))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 9).stroke(WeekflowPalette.border))
    }
}

struct PlanningTaskPoolCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let assignedToTarget: Bool
    @Bindable var store: WeekflowStore
    let dragStarted: (TaskDragToken) -> Void
    let assignToTarget: () -> Void
    let removeFromTarget: () -> Void
    @State private var isHovering = false
    @State private var isAssignmentControlHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.task.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(entry.goal.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if assignedToTarget {
                    WeekflowButton(action: removeFromTarget) {
                        Label("已添加", systemImage: "checkmark")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(
                                isAssignmentControlHovering
                                    ? WeekflowPalette.textPrimary
                                    : WeekflowPalette.complete
                            )
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                isAssignmentControlHovering
                                    ? WeekflowPalette.complete.opacity(0.14)
                                    : .clear,
                                in: Capsule()
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { isAssignmentControlHovering = $0 }
                    .help("点击取消添加")
                } else if !entry.task.assignedDates.isEmpty {
                    Text("已安排 \(entry.task.assignedDates.count) 天")
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(WeekflowPalette.textMuted)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovering ? WeekflowPalette.surfaceHover : WeekflowPalette.appBackground,
            in: WeekflowRoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 5, y: 2)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .pointingHandCursor()
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .onTapGesture(count: 2, perform: assignToTarget)
        .onDrag {
            let token = TaskDragToken(goalID: entry.goal.id, taskID: entry.task.id)
            dragStarted(token)
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                Text(entry.goal.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(width: 190, alignment: .leading)
            .frame(minHeight: 54, alignment: .leading)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong, lineWidth: 1)
            }
        }
        .help("拖动或双击添加到当天任务")
    }
}

struct PlanningPoolDropPreview: Equatable {
    let token: TaskDragToken
    let before: TaskReference?

    static func == (lhs: PlanningPoolDropPreview, rhs: PlanningPoolDropPreview) -> Bool {
        lhs.token.goalID == rhs.token.goalID
            && lhs.token.taskID == rhs.token.taskID
            && lhs.before == rhs.before
    }
}

struct PlanningColumnTaskDropDelegate: DropDelegate {
    @Binding var draggedTaskToken: TaskDragToken?
    let date: Date
    let rowFrames: [UUID: CGRect]
    let store: WeekflowStore
    @Binding var isDropTarget: Bool
    @Binding var poolDropPreview: PlanningPoolDropPreview?
    var taskAssigned: (UUID) -> Void = { _ in }

    func validateDrop(info: DropInfo) -> Bool {
        draggedTaskToken != nil
    }

    func dropEntered(info: DropInfo) {
        guard draggedTaskToken?.sourceDate == nil else {
            homeDelegate.dropEntered(info: info)
            return
        }
        isDropTarget = true
        updatePoolPreview(at: info.location.y)
    }

    func dropExited(info: DropInfo) {
        guard draggedTaskToken?.sourceDate == nil else {
            homeDelegate.dropExited(info: info)
            return
        }
        isDropTarget = false
        poolDropPreview = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedTaskToken?.sourceDate == nil else {
            return homeDelegate.dropUpdated(info: info)
        }
        updatePoolPreview(at: info.location.y)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let token = draggedTaskToken else { return false }
        guard token.sourceDate == nil else {
            return homeDelegate.performDrop(info: info)
        }

        updatePoolPreview(at: info.location.y)
        let target = poolDropPreview?.before
        store.relocateTask(
            goalID: token.goalID,
            taskID: token.taskID,
            from: nil,
            to: date,
            persistImmediately: false
        )
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            store.reorderTask(
                goalID: token.goalID,
                taskID: token.taskID,
                before: target,
                on: date
            )
        }
        store.ensureDailyPlanningTaskSchedule(
            on: date,
            newlyAssigned: TaskReference(goalID: token.goalID, taskID: token.taskID)
        )
        store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
        taskAssigned(token.taskID)
        isDropTarget = false
        poolDropPreview = nil
        draggedTaskToken = nil
        return true
    }

    private var homeDelegate: HomeColumnTaskDropDelegate {
        HomeColumnTaskDropDelegate(
            draggedTaskToken: $draggedTaskToken,
            date: date,
            rowFrames: { rowFrames },
            store: store,
            isDropTarget: $isDropTarget
        )
    }

    private func updatePoolPreview(at y: CGFloat) {
        guard let token = draggedTaskToken else { return }
        let target = store.tasks(on: date).first { entry in
            entry.task.id != token.taskID
                && (rowFrames[entry.task.id]?.midY ?? -.infinity) > y
        }.map { TaskReference(goalID: $0.goal.id, taskID: $0.task.id) }
        let preview = PlanningPoolDropPreview(token: token, before: target)
        guard preview != poolDropPreview else { return }
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            poolDropPreview = preview
        }
    }
}

@MainActor
func planningDisplayedEntries(
    store: WeekflowStore,
    date: Date,
    preview: PlanningPoolDropPreview?
) -> [(goal: WeeklyGoal, task: WeekTask)] {
    var entries = store.tasks(on: date)
    guard let preview,
          let goal = store.goals.first(where: { $0.id == preview.token.goalID }),
          let task = goal.tasks.first(where: { $0.id == preview.token.taskID }) else {
        return entries
    }

    entries.removeAll { $0.task.id == preview.token.taskID }
    let previewEntry = (goal: goal, task: task)
    if let target = preview.before,
       let targetIndex = entries.firstIndex(where: {
           $0.goal.id == target.goalID && $0.task.id == target.taskID
       }) {
        entries.insert(previewEntry, at: targetIndex)
    } else {
        entries.append(previewEntry)
    }
    return entries
}

@MainActor
@discardableResult
func assignPlanningPoolTaskToBottom(
    store: WeekflowStore,
    goalID: UUID,
    taskID: UUID,
    date: Date
) -> Bool {
    guard let task = store.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }),
          !task.isAssigned(on: date) else { return false }
    store.relocateTask(
        goalID: goalID,
        taskID: taskID,
        from: nil,
        to: date,
        persistImmediately: false
    )
    store.ensureDailyPlanningTaskSchedule(
        on: date,
        newlyAssigned: TaskReference(goalID: goalID, taskID: taskID)
    )
    // Scheduling may synchronize the weekly goal projection. Apply the final
    // ordering afterwards so that the user's explicit append remains last.
    store.reorderTask(
        goalID: goalID,
        taskID: taskID,
        before: nil,
        on: date
    )
    store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
    return true
}

@MainActor
func removePlanningTaskFromDay(
    store: WeekflowStore,
    goalID: UUID,
    taskID: UUID,
    date: Date
) {
    guard let task = store.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }) else { return }
    if task.isAssigned(on: date) {
        store.removeTaskAssignment(goalID: goalID, taskID: taskID, from: date)
    } else {
        store.moveTaskToBacklog(goalID: goalID, taskID: taskID, atTop: false)
    }
}

struct ShutdownTimeMetric: View {
    let title: String
    let minutes: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                .font(.system(size: 19, weight: .semibold))
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(WeekflowPalette.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: WeekflowRoundedRectangle(cornerRadius: 8))
    }
}

struct ChannelTimeDonut: View {
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    @Bindable var store: WeekflowStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChartPalettePreferences.storageKey)
    private var chartPaletteRawValue = ChartPalettePreferences.defaultPreset

    private var chartPalette: ChartPalettePreset {
        ChartPalettePreferences.preset(for: chartPaletteRawValue)
    }

    private var slices: [(channel: TaskChannel?, minutes: Int)] {
        let grouped = Dictionary(grouping: entries) { $0.task.channelID }
        return grouped.map { channelID, values in
            let minutes = values.reduce(0) {
                $0 + DailyShutdownTimeDistribution.reviewMinutes(for: $1.task)
            }
            return (store.channel(for: channelID), minutes)
        }
        .filter { $0.minutes > 0 }
        .sorted { $0.minutes > $1.minutes }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Canvas { context, size in
                    let total = max(slices.reduce(0) { $0 + $1.minutes }, 1)
                    let diameter = min(size.width, size.height)
                    let rect = CGRect(
                        x: (size.width - diameter) / 2,
                        y: (size.height - diameter) / 2,
                        width: diameter,
                        height: diameter
                    ).insetBy(dx: 3, dy: 3)
                    var start = Angle.degrees(-90)
                    if slices.isEmpty {
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(WeekflowPalette.surfaceSelected.opacity(0.72))
                        )
                    } else {
                        for slice in slices {
                            let angle = 360 * Double(slice.minutes) / Double(total)
                            let end = start + .degrees(angle)
                            var path = Path()
                            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
                            path.addArc(
                                center: CGPoint(x: rect.midX, y: rect.midY),
                                radius: rect.width / 2,
                                startAngle: start,
                                endAngle: end,
                                clockwise: false
                            )
                            path.closeSubpath()
                            context.fill(
                                path,
                                with: .color(chartPalette.taskColor(
                                    channelID: slice.channel?.id,
                                    channels: store.channels,
                                    colorScheme: colorScheme
                                ))
                            )
                            start = end
                        }
                    }
                }
                .frame(width: 166, height: 166)

                if slices.isEmpty {
                    Text("暂无计时")
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                }
            }

            if !slices.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(chartPalette.taskColor(
                                    channelID: slice.channel?.id,
                                    channels: store.channels,
                                    colorScheme: colorScheme
                                ))
                                .frame(width: 7, height: 7)
                            Text(slice.channel?.title ?? "未分类")
                                .lineLimit(1)
                            Text(slice.minutes.hourMinuteClockText)
                                .monospacedDigit()
                                .foregroundStyle(WeekflowPalette.textMuted)
                    }
                        .font(.system(size: 9.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
