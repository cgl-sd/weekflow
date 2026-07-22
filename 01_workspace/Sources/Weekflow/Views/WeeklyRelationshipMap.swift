import SwiftUI

struct WeeklyPlanningRelationshipMap: View {
    @Bindable var store: WeekflowStore
    let weekDays: [Date]
    let weekRangeLabel: String
    let openGoal: (WeeklyGoal.ID) -> Void
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void
    @State private var hoveredNode: RelationshipHoverNode?
    @State private var draggedTaskToken: TaskDragToken?
    @State private var dropTargetDate: Date?
    @State private var availableWidth: CGFloat = 626

    private enum RelationshipHoverNode: Equatable {
        case goal(WeeklyGoal.ID)
        case task(WeekTask.ID)
        case date(Date)
    }

    private var canvasWidth: CGFloat { max(489, availableWidth - 52) }
    private var goalNodeWidth: CGFloat { min(max(canvasWidth * 0.26, 150), 210) }
    private var taskNodeWidth: CGFloat { min(max(canvasWidth * 0.24, 155), 190) }
    private var dateNodeWidth: CGFloat { min(max(canvasWidth * 0.24, 154), 190) }
    private var columnSpacing: CGFloat {
        max((canvasWidth - goalNodeWidth - taskNodeWidth - dateNodeWidth) / 2, 10)
    }
    private let goalColumnX: CGFloat = 0
    private var taskColumnX: CGFloat { goalNodeWidth + columnSpacing }
    private var dateColumnX: CGFloat { taskColumnX + taskNodeWidth + columnSpacing }
    private let taskRowStep: CGFloat = 72
    private let taskNodeHeight: CGFloat = 54
    private let dateNodeHeight: CGFloat = 46
    private let goalNodeHeight: CGFloat = 82
    private let goalNodeSpacing: CGFloat = 12

    private var entries: [(goal: WeeklyGoal, task: WeekTask)] {
        store.weeklyPlanningPoolEntries
    }

    private var displayedGoals: [WeeklyGoal] {
        store.activeGoals.filter { goal in entries.contains { $0.goal.id == goal.id } }
    }

    private var relationshipDates: [Date] {
        weekDays.map { SystemBusinessCalendar.current.calendar.startOfDay(for: $0) }
    }

    private var rawGoalCenters: [CGFloat] {
        let desiredCenters = displayedGoals.map { displayedGoal in
            let taskIndices = entries.indices.filter { entries[$0].goal.id == displayedGoal.id }
            guard let first = taskIndices.first, let last = taskIndices.last else {
                return goalNodeHeight / 2 + 12
            }
            return (taskCenterY(at: first) + taskCenterY(at: last)) / 2
        }
        return WeeklyRelationshipLayout.nonOverlappingCenters(
            desiredCenters: desiredCenters,
            nodeHeight: goalNodeHeight,
            spacing: goalNodeSpacing
        )
    }

    private var goalGroupHeight: CGFloat {
        guard let first = rawGoalCenters.first, let last = rawGoalCenters.last else { return 0 }
        return last - first + goalNodeHeight
    }

    private var relationshipCanvasHeight: CGFloat {
        max(
            max(CGFloat(entries.count) * taskRowStep + 20, 280),
            max(
                CGFloat(relationshipDates.count) * 58 + 20,
                goalGroupHeight + 24
            )
        )
    }

    private var goalVerticalOffset: CGFloat {
        WeeklyRelationshipLayout.centeredOffset(
            centers: rawGoalCenters,
            nodeHeight: goalNodeHeight,
            canvasHeight: relationshipCanvasHeight
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            relationshipHeader
            relationshipSurface
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WeeklyRelationshipAvailableWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(WeeklyRelationshipAvailableWidthPreferenceKey.self) { width in
            if width > 0 { availableWidth = width }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var relationshipSurface: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "还没有可展示的任务关系",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("创建周目标和子目标后，这里会显示它们与每日分配的关系。")
                )
                .frame(maxWidth: .infinity, minHeight: 360)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        relationshipColumnHeaders
                        relationshipCanvas
                    }
                    .padding(.horizontal, 10)
                    .frame(width: canvasWidth + 20, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(16)
        .background(WeekflowPalette.surface.opacity(0.72), in: WeekflowRoundedRectangle(cornerRadius: 14))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 14).stroke(WeekflowPalette.border))
    }

    private var relationshipHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("本周关系图")
                        .font(.largeTitle.weight(.bold))
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                Text(weekRangeLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            relationshipMetric("周目标", displayedGoals.count)
            relationshipMetric("任务", entries.count)
            relationshipMetric("日期", relationshipDates.count)
        }
    }

    private var relationshipColumnHeaders: some View {
        ZStack(alignment: .leading) {
            Text("周目标")
                .frame(width: goalNodeWidth, alignment: .leading)
                .offset(x: goalColumnX)
            Text("任务池")
                .frame(width: taskNodeWidth, alignment: .leading)
                .offset(x: taskColumnX)
            Text("每日分配")
                .frame(width: dateNodeWidth, alignment: .leading)
                .offset(x: dateColumnX)
        }
        .frame(width: canvasWidth, height: 16, alignment: .leading)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(WeekflowPalette.textMuted)
    }

    private var relationshipCanvas: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawRelationshipLines(in: &context)
            }
            .allowsHitTesting(false)

            ForEach(displayedGoals) { goal in
                let tint = channelTint(for: goal)
                relationshipGoalNode(
                    goal,
                    channel: store.channel(for: goal.channelID),
                    tint: tint,
                    isHovered: hoveredNode == .goal(goal.id)
                )
                .position(
                    x: goalColumnX + goalNodeWidth / 2,
                    y: goalCenterY(for: goal)
                )
            }

            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                relationshipTaskNode(
                    entry,
                    tint: channelTint(for: entry.goal),
                    isHovered: hoveredNode == .task(entry.task.id)
                )
                .position(
                    x: taskColumnX + taskNodeWidth / 2,
                    y: taskCenterY(at: index)
                )
                .zIndex(hoveredNode == .task(entry.task.id) ? 5 : 1)
            }

            ForEach(relationshipDates.indices, id: \.self) { index in
                let date = relationshipDates[index]
                relationshipDateNode(
                    date,
                    entries: store.weeklyPlanningTasks(on: date),
                    isHovered: hoveredNode == .date(date),
                    isDropTarget: dropTargetDate.map {
                        SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date)
                    } == true
                )
                .position(
                    x: dateColumnX + dateNodeWidth / 2,
                    y: dateCenterY(at: index)
                )
                .zIndex(hoveredNode == .date(date) ? 5 : 1)
            }

            if dropTargetDate == nil,
               case let .date(date) = hoveredNode,
               let index = relationshipDates.firstIndex(where: {
                   SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date)
               }) {
                relationshipDateAssignmentPreview(
                    date: date,
                    entries: store.weeklyPlanningTasks(on: date)
                )
                .position(
                    x: max(dateColumnX - 112, 112),
                    y: min(
                        max(dateCenterY(at: index) + 72, 72),
                        relationshipCanvasHeight - 72
                    )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .zIndex(20)
            }
        }
        .frame(width: canvasWidth, height: relationshipCanvasHeight, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: hoveredNode)
    }

    private func drawRelationshipLines(in context: inout GraphicsContext) {
        for goal in displayedGoals {
            let tint = channelTint(for: goal)
            let start = CGPoint(x: goalColumnX + goalNodeWidth, y: goalCenterY(for: goal))
            for index in entries.indices where entries[index].goal.id == goal.id {
                let end = CGPoint(x: taskColumnX, y: taskCenterY(at: index))
                context.stroke(
                    curvedPath(from: start, to: end),
                    with: .color(tint.opacity(0.42)),
                    lineWidth: 1.2
                )
            }
        }

        for taskIndex in entries.indices {
            let entry = entries[taskIndex]
            let tint = channelTint(for: entry.goal)
            let start = CGPoint(
                x: taskColumnX + taskNodeWidth,
                y: taskCenterY(at: taskIndex)
            )
            for dateIndex in relationshipDates.indices {
                let date = relationshipDates[dateIndex]
                let isPlannedOnDate = entry.task.plannedDate.map {
                    SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date)
                } == true
                guard entry.task.isAssigned(on: date) || isPlannedOnDate else { continue }
                let end = CGPoint(x: dateColumnX, y: dateCenterY(at: dateIndex))
                context.stroke(
                    curvedPath(from: start, to: end),
                    with: .color(tint.opacity(0.46)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
            }
        }

        if let draggedTaskToken,
           let dropTargetDate,
           let taskIndex = entries.firstIndex(where: { $0.task.id == draggedTaskToken.taskID }),
           let dateIndex = relationshipDates.firstIndex(where: {
               SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: dropTargetDate)
           }) {
            let entry = entries[taskIndex]
            let previewPath = curvedPath(
                from: CGPoint(
                    x: taskColumnX + taskNodeWidth,
                    y: taskCenterY(at: taskIndex)
                ),
                to: CGPoint(
                    x: dateColumnX,
                    y: dateCenterY(at: dateIndex)
                )
            )
            context.stroke(
                previewPath,
                with: .color(channelTint(for: entry.goal).opacity(0.9)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
            )
        }
    }

    private func curvedPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        let controlOffset = max((end.x - start.x) * 0.48, 22)
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + controlOffset, y: start.y),
            control2: CGPoint(x: end.x - controlOffset, y: end.y)
        )
        return path
    }

    private func taskCenterY(at index: Int) -> CGFloat {
        18 + taskNodeHeight / 2 + CGFloat(index) * taskRowStep
    }

    private func goalCenterY(for goal: WeeklyGoal) -> CGFloat {
        guard let index = displayedGoals.firstIndex(where: { $0.id == goal.id }) else {
            return relationshipCanvasHeight / 2
        }
        return rawGoalCenters[index] + goalVerticalOffset
    }

    private func dateCenterY(at index: Int) -> CGFloat {
        guard relationshipDates.count > 1 else { return relationshipCanvasHeight / 2 }
        let top = dateNodeHeight / 2 + 12
        let bottom = relationshipCanvasHeight - dateNodeHeight / 2 - 12
        return top + (bottom - top) * CGFloat(index) / CGFloat(relationshipDates.count - 1)
    }

    private func channelTint(for goal: WeeklyGoal) -> Color {
        store.channel(for: goal.channelID)?.color ?? WeekflowPalette.iconDefault
    }

    private func relationshipGoalNode(
        _ goal: WeeklyGoal,
        channel: TaskChannel?,
        tint: Color,
        isHovered: Bool
    ) -> some View {
        WeekflowButton { openGoal(goal.id) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: channel?.resolvedIconName ?? "scope")
                    Text(channel?.title ?? "未设置 Channel")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(tint)
                Text(goal.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text("\(Int(goal.progress * 100))%")
                    Text("·")
                    Text(goal.plannedMinutes.hourMinuteClockText)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(WeekflowPalette.textMuted)
            }
            .padding(10)
            .frame(width: goalNodeWidth, alignment: .leading)
            .frame(height: goalNodeHeight, alignment: .leading)
            .background(
                tint.opacity(isHovered ? 0.17 : 0.09),
                in: WeekflowRoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 9)
                    .stroke(tint.opacity(isHovered ? 0.7 : 0.3), lineWidth: isHovered ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            updateHover(.goal(goal.id), isHovering: hovering)
        }
    }

    private func relationshipTaskNode(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        tint: Color,
        isHovered: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .opacity(isHovered ? 1 : 0.45)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 6) {
                Text(entry.task.estimatedMinutes.hourMinuteClockText)
                if entry.task.status == .completed {
                    Label("已完成", systemImage: "checkmark")
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(WeekflowPalette.textMuted)
        }
        .padding(.horizontal, 10)
        .frame(width: taskNodeWidth, height: taskNodeHeight, alignment: .leading)
        .background(
            isHovered ? tint.opacity(0.17) : WeekflowPalette.surface,
            in: WeekflowRoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(isHovered ? 0.7 : 0.28), lineWidth: isHovered ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        .pointingHandCursor()
        .onTapGesture { openTask(entry) }
        .onHover { hovering in
            updateHover(.task(entry.task.id), isHovering: hovering)
        }
        .onDrag {
            let token = TaskDragToken(goalID: entry.goal.id, taskID: entry.task.id)
            draggedTaskToken = token
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            Text(entry.task.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(width: taskNodeWidth, height: taskNodeHeight, alignment: .leading)
                .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
                .overlay(WeekflowRoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.55)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("点击编辑；拖动到右侧日期进行安排")
    }

    private func relationshipDateNode(
        _ date: Date,
        entries: [(goal: WeeklyGoal, task: WeekTask)],
        isHovered: Bool,
        isDropTarget: Bool
    ) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).weekday(.short)))
                    .font(.system(size: 9.5, weight: .medium))
                Text(date.formatted(.dateTime.month().day()))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 0)
            if isDropTarget {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textSecondary)
            } else {
                Text("\(entries.count) 项")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
        }
        .foregroundStyle(isHovered ? WeekflowPalette.textPrimary : WeekflowPalette.textSecondary)
        .padding(.horizontal, 10)
        .frame(width: dateNodeWidth, height: dateNodeHeight)
        .background(
            isHovered || isDropTarget ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover,
            in: WeekflowRoundedRectangle(cornerRadius: 9)
        )
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 9)
                .stroke(
                    isHovered || isDropTarget ? WeekflowPalette.borderStrong : WeekflowPalette.border,
                    style: StrokeStyle(
                        lineWidth: isDropTarget ? 2 : (isHovered ? 1.5 : 1),
                        dash: isDropTarget ? [5, 3] : []
                    )
                )
        }
        .contentShape(Rectangle())
        .pointingHandCursor()
        .onHover { hovering in
            updateHover(.date(date), isHovering: hovering)
        }
        .onDrop(
            of: [.utf8PlainText],
            delegate: WeeklyRelationshipDateDropDelegate(
                draggedTaskToken: $draggedTaskToken,
                dropTargetDate: $dropTargetDate,
                date: date,
                store: store
            )
        )
    }

    private func updateHover(_ node: RelationshipHoverNode, isHovering: Bool) {
        if isHovering {
            hoveredNode = node
        } else if hoveredNode == node {
            hoveredNode = nil
        }
    }

    private func relationshipDateAssignmentPreview(
        date: Date,
        entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).weekday(.wide).month().day()))
                .font(.system(size: 11.5, weight: .semibold))
            Divider()
            if entries.isEmpty {
                Text("当天暂无任务")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
            } else {
                ForEach(Array(entries.prefix(4).enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.task.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                        Text(entry.goal.title)
                            .font(.system(size: 9))
                            .foregroundStyle(WeekflowPalette.textMuted)
                            .lineLimit(1)
                    }
                }
                if entries.count > 4 {
                    Text("另有 \(entries.count - 4) 项…")
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
            }
        }
        .padding(10)
        .frame(width: 214, alignment: .leading)
        .background(.regularMaterial, in: WeekflowRoundedRectangle(cornerRadius: 9))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 9).stroke(WeekflowPalette.borderStrong.opacity(0.8)))
        .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)
        .allowsHitTesting(false)
    }

    private func relationshipMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(WeekflowPalette.textMuted)
        }
        .frame(width: 48, alignment: .leading)
    }
}

struct WeeklyRelationshipAvailableWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum WeeklyRelationshipDropCoordinator {
    @MainActor
    static func assign(_ token: TaskDragToken, to date: Date, in store: WeekflowStore) {
        store.relocateTask(
            goalID: token.goalID,
            taskID: token.taskID,
            from: token.sourceDate,
            to: date
        )
        store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
    }
}

struct WeeklyRelationshipDateDropDelegate: DropDelegate {
    @Binding var draggedTaskToken: TaskDragToken?
    @Binding var dropTargetDate: Date?
    let date: Date
    let store: WeekflowStore

    func validateDrop(info: DropInfo) -> Bool {
        draggedTaskToken != nil
    }

    func dropEntered(info: DropInfo) {
        dropTargetDate = date
    }

    func dropExited(info: DropInfo) {
        if dropTargetDate.map({ SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date) }) == true {
            dropTargetDate = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let token = draggedTaskToken else { return false }
        WeeklyRelationshipDropCoordinator.assign(token, to: date, in: store)
        draggedTaskToken = nil
        dropTargetDate = nil
        return true
    }
}

