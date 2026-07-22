import SwiftUI

enum WeeklyPlanningPresentation: String, CaseIterable, Identifiable {
    case sections
    case relationships

    var id: String { rawValue }
    var title: String { self == .sections ? "分区图" : "关系图" }
    var symbol: String { self == .sections ? "rectangle.3.group" : "point.3.connected.trianglepath.dotted" }
}

enum WeeklyRelationshipLayout {
    static func nonOverlappingCenters(
        desiredCenters: [CGFloat],
        nodeHeight: CGFloat,
        spacing: CGFloat,
        topInset: CGFloat = 12
    ) -> [CGFloat] {
        var previousCenter: CGFloat?
        return desiredCenters.map { desiredCenter in
            let minimumCenter = previousCenter.map { $0 + nodeHeight + spacing }
                ?? (topInset + nodeHeight / 2)
            let center = max(desiredCenter, minimumCenter)
            previousCenter = center
            return center
        }
    }

    static func centeredOffset(
        centers: [CGFloat],
        nodeHeight: CGFloat,
        canvasHeight: CGFloat
    ) -> CGFloat {
        guard let first = centers.first, let last = centers.last else { return 0 }
        let groupHeight = last - first + nodeHeight
        let centeredTop = (canvasHeight - groupHeight) / 2
        return centeredTop - (first - nodeHeight / 2)
    }
}

struct WeeklyBoardView: View {
    @Bindable var store: WeekflowStore
    @Binding var presentedTask: TaskDetailTarget?
    @Binding private var presentation: WeeklyPlanningPresentation
    private let usesScrollContainer: Bool
    private let referenceDate: Date
    @State private var draggedTaskToken: TaskDragToken?
    @State private var planningStartDate: Date
    @State private var planningEndDate: Date
    @State private var planningDisplayedMonth: Date
    @State private var planningRangeBoundary: WeeklyPlanningRangeBoundary = .start
    @State private var isPlanningRangeInteractionActive = false
    @State private var showsPlanningRange = false
    private let calendar = SystemBusinessCalendar.current.calendar

    init(
        store: WeekflowStore,
        presentedTask: Binding<TaskDetailTarget?>,
        usesScrollContainer: Bool = true,
        referenceDate: Date = .now,
        presentation: Binding<WeeklyPlanningPresentation> = .constant(.sections)
    ) {
        self.store = store
        _presentedTask = presentedTask
        self.usesScrollContainer = usesScrollContainer
        self.referenceDate = referenceDate
        _presentation = presentation
        let range = WeeklyPlanningRangePreferences.range(for: referenceDate)
        _planningStartDate = State(initialValue: range.start)
        _planningEndDate = State(initialValue: range.end)
        _planningDisplayedMonth = State(
            initialValue: SystemBusinessCalendar.current.calendar.dateInterval(of: .month, for: range.start)?.start ?? range.start
        )
    }

    var body: some View {
        Group {
            if usesScrollContainer {
                ScrollView { boardContent }
            } else {
                boardContent
            }
        }
        .overlayPreferenceValue(WeeklyPlanningRangeAnchorPreferenceKey.self) { anchor in
            GeometryReader { proxy in
                if showsPlanningRange, let anchor {
                    planningRangeOverlay(anchorFrame: proxy[anchor], containerSize: proxy.size)
                }
            }
        }
    }

    private var boardContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if presentation == .sections {
                header
                goals
                taskPool
                weekBoard
            } else {
                WeeklyPlanningRelationshipMap(
                    store: store,
                    weekDays: weekDays,
                    weekRangeLabel: weekRangeLabel,
                    openGoal: { openGoal($0) },
                    openTask: openTask
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            WeekflowButton { showsPlanningRange.toggle() } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("本周规划").font(.largeTitle.weight(.bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WeekflowPalette.textMuted)
                    }
                    Text(weekRangeLabel).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 7))
            .anchorPreference(key: WeeklyPlanningRangeAnchorPreferenceKey.self, value: .bounds) { $0 }
            Spacer()
            WeeklyHeaderActionButton(
                title: "新建周目标",
                symbol: "plus",
                isPrimary: true,
                action: createGoal
            )
            WeeklyHeaderActionButton(
                title: "自动分配",
                symbol: "wand.and.stars",
                action: { store.autoDistributeTaskPool() }
            )
                .disabled(store.weeklyPlanningPoolEntries.isEmpty)
            if store.canUndoAutomaticDistribution {
                WeeklyHeaderUndoButton(action: store.undoAutomaticDistribution)
            }
        }
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("周目标").font(.title3.weight(.semibold))
            if store.activeGoals.isEmpty { Text("创建一个周目标，作为本周行动的方向。 ").foregroundStyle(.secondary) }
            ForEach(store.activeGoals) { goal in
                WeeklyGoalTreeCard(
                    goal: goal,
                    store: store,
                    pasteWeekReference: planningStartDate,
                    edit: { openGoal(goal.id) }
                )
            }
        }
    }

    private var taskPool: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("任务池", systemImage: "tray").font(.title3.weight(.semibold))
                Spacer()
                Text("拖动或选择日期")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if planningPoolEntries.isEmpty {
                Text("任务池为空。请先为周目标添加子目标。")
                    .foregroundStyle(.secondary).font(.callout)
            } else {
                if !nextWeekPoolEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.questionmark")
                            Text("时间未确定 · 下周内执行")
                                .font(.system(size: 12, weight: .semibold))
                            Text(nextWeekRangeLabel)
                                .font(.system(size: 10.5))
                                .foregroundStyle(WeekflowPalette.textMuted)
                        }
                        .foregroundStyle(WeekflowPalette.objective)

                        taskPoolFlow(nextWeekPoolEntries)
                    }
                    .padding(12)
                    .background(WeekflowPalette.objective.opacity(0.06), in: WeekflowRoundedRectangle(cornerRadius: 10))
                    .overlay(
                        WeekflowRoundedRectangle(cornerRadius: 10)
                            .stroke(WeekflowPalette.objective.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                    )
                }

                if !generalPoolEntries.isEmpty {
                    taskPoolFlow(generalPoolEntries)
                }
            }
        }
        .padding(16).background(.regularMaterial, in: WeekflowRoundedRectangle(cornerRadius: 14))
    }

    private var planningPoolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        store.weeklyPlanningPoolEntries
    }

    private var nextWeekPoolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        planningPoolEntries.filter { $0.task.executionWeekStart != nil }
    }

    private var generalPoolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        planningPoolEntries.filter { $0.task.executionWeekStart == nil }
    }

    private var nextWeekRangeLabel: String {
        guard let start = nextWeekPoolEntries.compactMap(\.task.executionWeekStart).min(),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return "" }
        return "\(start.formatted(.dateTime.month().day()))–\(end.formatted(.dateTime.month().day()))"
    }

    private func taskPoolFlow(
        _ entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(store.activeGoals.filter { goal in entries.contains { $0.goal.id == goal.id } }) { goal in
                let goalChannel = store.channel(for: goal.channelID)
                let goalTint = goalChannel?.color ?? WeekflowPalette.iconDefault
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: goalChannel?.resolvedIconName ?? "circle")
                            .foregroundStyle(goalTint)
                        Text(goal.title)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("\(entries.filter { $0.goal.id == goal.id }.count) 项")
                            .font(.system(size: 10))
                            .foregroundStyle(WeekflowPalette.textMuted)
                    }

                    FlowLayout(spacing: 10) {
                        ForEach(entries.filter { $0.goal.id == goal.id }, id: \.task.id) { entry in
                            WeeklyTaskPoolCard(
                                entry: entry,
                                tint: goalTint,
                                store: store,
                                calendarAnchorDate: planningStartDate,
                                dragStarted: { draggedTaskToken = $0 }
                            )
                        }
                    }
                }
                .padding(10)
                .background(
                    goalTint.opacity(0.045),
                    in: WeekflowRoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 10)
                        .stroke(goalTint.opacity(0.18), lineWidth: 1)
                }
            }
        }
    }

    private var weekBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("每日分配").font(.title3.weight(.semibold))
                Spacer()
                Text("横向滚动查看周一至周日")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(weekDays, id: \.self) { date in
                        WeekDayColumn(
                            date: date,
                            entries: store.weeklyPlanningTasks(on: date),
                            store: store,
                            draggedTaskToken: $draggedTaskToken
                        )
                    }
                }
                .padding(.bottom, 8)
                .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
            }
            .frame(minHeight: 270, alignment: .topLeading)
            .scrollIndicators(.visible)
        }
    }

    private var weekDays: [Date] {
        let start = calendar.startOfDay(for: planningStartDate)
        let end = calendar.startOfDay(for: planningEndDate)
        let count = min(max((calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1, 1), 31)
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekRangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "本周" }
        return "\(first.formatted(.dateTime.month().day())) – \(last.formatted(.dateTime.month().day()))"
    }

    private func planningRangeOverlay(anchorFrame: CGRect, containerSize: CGSize) -> some View {
        let panelSize = CGSize(width: 236, height: 306)
        let inset: CGFloat = 8
        let proposedX = anchorFrame.minX
        let maximumX = max(containerSize.width - panelSize.width - inset, inset)
        let panelX = min(max(proposedX, inset), maximumX)
        let panelTop = anchorFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        let panelFrame = CGRect(origin: CGPoint(x: panelX, y: panelTop), size: panelSize)

        return ZStack(alignment: .topLeading) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    planningBoundaryButton(.start, date: planningStartDate)
                    planningBoundaryButton(.end, date: planningEndDate)
                }

                CompactTaskMonthCalendar(
                    displayedMonth: $planningDisplayedMonth,
                    selectedDate: planningRangeBoundary == .start
                        ? planningStartDate
                        : planningEndDate,
                    highlightsToday: true,
                    minimumDate: planningRangeBoundary == .end ? planningStartDate : nil,
                    highlightedRangeStart: planningStartDate,
                    highlightedRangeEnd: planningEndDate,
                    select: selectPlanningBoundaryDate
                )
                .padding(8)
                .frame(
                    width: WeekflowLayout.taskDetailDateMenuWidth,
                    height: WeekflowLayout.taskDetailCalendarMenuHeight
                )
            }
            .padding(8)
            .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        isPlanningRangeInteractionActive = true
                    }
                    .onEnded { _ in
                        // The window monitor resolves on the same mouse-up.
                        // Clear the protection after its queued dismissal check.
                        DispatchQueue.main.async {
                            isPlanningRangeInteractionActive = false
                        }
                    }
            )
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 6))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 6)
                    .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            .position(x: panelFrame.midX, y: panelFrame.midY)
            .zIndex(2)

            TaskDurationMenuPointer()
                .fill(WeekflowPalette.surface)
                .overlay {
                    TaskDurationMenuPointerOutline()
                        .stroke(WeekflowPalette.borderStrong.opacity(0.9), lineWidth: 1)
                }
                .frame(
                    width: WeekflowLayout.taskDurationMenuPointerWidth,
                    height: WeekflowLayout.taskDurationMenuPointerHeight
                )
                .position(
                    x: anchorFrame.midX,
                    y: panelFrame.minY - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .zIndex(3)

            WindowOutsideClickMonitor(
                protectedRects: [panelFrame, anchorFrame],
                action: {
                    guard WeeklyPlanningRangeDismissalPolicy.shouldDismiss(
                        isInteractingInsidePanel: isPlanningRangeInteractionActive
                    ) else { return }
                    showsPlanningRange = false
                }
            )
            .frame(width: containerSize.width, height: containerSize.height)
            .allowsHitTesting(false)
        }
        .zIndex(1_000)
    }

    private func planningBoundaryButton(
        _ boundary: WeeklyPlanningRangeBoundary,
        date: Date
    ) -> some View {
        let isActive = planningRangeBoundary == boundary
        return WeekflowButton {
            planningRangeBoundary = boundary
            planningDisplayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(boundary.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isActive ? WeekflowPalette.objective : WeekflowPalette.textMuted)
                Text(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day()))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textPrimary)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(
                isActive ? WeekflowPalette.objective.opacity(0.10) : WeekflowPalette.surfaceHover,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isActive
                            ? WeekflowPalette.objective.opacity(0.65)
                            : WeekflowPalette.border,
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func selectPlanningBoundaryDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        switch planningRangeBoundary {
        case .start:
            planningStartDate = day
            if planningEndDate < day { planningEndDate = day }
            planningRangeBoundary = .end
        case .end:
            planningEndDate = max(day, planningStartDate)
        }
        WeeklyPlanningRangePreferences.save(
            start: planningStartDate,
            end: planningEndDate,
            for: referenceDate,
            calendar: calendar
        )
    }

    private func createGoal() {
        let goalID = store.addGoal(
            title: "",
            outcome: "",
            startDate: planningStartDate,
            endDate: planningEndDate,
            persistImmediately: false
        )
        openGoal(goalID, isNew: true)
    }

    private func openGoal(_ goalID: UUID, isNew: Bool = false) {
        guard let taskID = store.ensurePrimaryTask(forGoalID: goalID) else { return }
        presentedTask = TaskDetailTarget(
            goalID: goalID,
            taskID: taskID,
            isWeeklyGoalDetail: true,
            isNewWeeklyGoal: isNew
        )
    }

    private func openTask(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        presentedTask = TaskDetailTarget(goalID: entry.goal.id, taskID: entry.task.id)
    }
}

private struct WeeklyPlanningRangeAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private enum WeeklyPlanningRangeBoundary {
    case start
    case end

    var title: String {
        switch self {
        case .start: "开始日期"
        case .end: "截止日期"
        }
    }
}

enum WeeklyPlanningRangeDismissalPolicy {
    static func shouldDismiss(isInteractingInsidePanel: Bool) -> Bool {
        !isInteractingInsidePanel
    }
}

private struct WeeklyHeaderActionButton: View {
    let title: String
    let symbol: String
    var isPrimary = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isPrimary ? .white : WeekflowPalette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    isPrimary
                        ? WeekflowPalette.objective.opacity(isHovering ? 0.84 : 1)
                        : (isHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surface),
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    if !isPrimary {
                        WeekflowRoundedRectangle(cornerRadius: 7)
                            .stroke(WeekflowPalette.border, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct WeeklyHeaderUndoButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Label("撤销分配", systemImage: "arrow.uturn.backward")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isHovering ? WeekflowPalette.textPrimary : WeekflowPalette.textMuted
                )
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(
                    isHovering ? WeekflowPalette.surfaceHover : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
        .help("撤销最近一次自动分配")
    }
}

private struct WeeklyPlanningRelationshipMap: View {
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

private struct WeeklyRelationshipAvailableWidthPreferenceKey: PreferenceKey {
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

private struct WeeklyRelationshipDateDropDelegate: DropDelegate {
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

private struct WeeklyGoalTreeCard: View {
    let goal: WeeklyGoal
    @Bindable var store: WeekflowStore
    let pasteWeekReference: Date
    let edit: () -> Void
    @State private var isHovering = false
    @State private var showsContextPopover = false

    private var goalChannelColor: Color? {
        store.channel(for: goal.channelID)?.color
    }

    private var goalCardFill: Color {
        goalChannelColor?.opacity(isHovering ? 0.13 : 0.075)
            ?? (isHovering ? WeekflowPalette.surfaceHover : .clear)
    }

    private var goalCardBorder: Color {
        goalChannelColor?.opacity(isHovering ? 0.62 : 0.34)
            ?? (isHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
    }

    private var primaryTask: WeekTask? {
        guard let primaryTaskID = goal.primaryTaskID,
              let primaryTask = goal.tasks.first(where: { $0.id == primaryTaskID }) else { return nil }
        return primaryTask
    }

    private var totalEstimatedMinutes: Int {
        guard !goal.subgoals.isEmpty else {
            return primaryTask?.estimatedMinutes ?? goal.plannedMinutes
        }
        return goal.subgoals.reduce(0) { total, subgoal in
            total + estimatedMinutes(for: subgoal)
        }
    }

    private var completionCountText: String {
        if goal.subgoals.isEmpty {
            return "\(goal.completedAt == nil ? 0 : 1)/1"
        }
        return "\(goal.subgoals.filter(\.isCompleted).count)/\(goal.subgoals.count)"
    }

    private func estimatedMinutes(for subgoal: GoalSubgoal) -> Int {
        primaryTask?.subtasks.first(where: { $0.id == subgoal.id })?.plannedMinutes ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                WeekflowButton(action: edit) {
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 22, height: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WeekflowPalette.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                Label(
                                    "预计 \(TaskTimeDisplay.estimated(minutes: totalEstimatedMinutes))",
                                    systemImage: "clock"
                                )
                                Label("完成 \(completionCountText)", systemImage: "checkmark.circle")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Int(goal.progress * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WeekflowPalette.textSecondary)
                            WeekflowDailyProgressTrack(
                                fraction: goal.progress,
                                hasProgress: goal.progress > 0,
                                accessibilityLabel: "周目标完成进度",
                                accessibilityValue: "已完成 \(Int(goal.progress * 100))%"
                            )
                            .frame(width: 72, height: WeekflowLayout.homeDailyProgressHeight)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, goal.subgoals.isEmpty ? 10 : 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                WeekflowButton {
                    store.setGoalCompleted(id: goal.id, completed: goal.progress < 1)
                } label: {
                    Image(systemName: goal.progress >= 1 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(goal.progress >= 1 ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.top, 10)
                .help(goal.progress >= 1 ? "标记为未完成" : "标记为已完成")
            }

            ForEach(goal.subgoals) { subgoal in
                ZStack(alignment: .leading) {
                    WeekflowButton(action: edit) {
                        HStack(spacing: 12) {
                            Color.clear.frame(width: 22, height: 32)
                            Text(subgoal.title)
                                .font(.system(size: 13))
                                .strikethrough(subgoal.isCompleted)
                            Spacer()
                            Label(
                                "预计 \(TaskTimeDisplay.estimated(minutes: estimatedMinutes(for: subgoal)))",
                                systemImage: "clock"
                            )
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    WeekflowButton {
                        store.toggleSubgoal(goalID: goal.id, subgoalID: subgoal.id)
                    } label: {
                        Image(systemName: subgoal.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(subgoal.isCompleted ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                            .frame(width: 22, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
        .background {
            WeekflowRoundedRectangle(cornerRadius: 10)
                .fill(WeekflowPalette.surface)
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 10)
                        .fill(goalCardFill)
                }
        }
        .background {
            TaskCardContextMenuAnchor(
                isPresented: $showsContextPopover,
                menuHeight: 178,
                onOpen: {}
            ) {
                WeeklyGoalContextPopover(
                    copy: {
                        store.copyGoalToClipboard(id: goal.id)
                        showsContextPopover = false
                    },
                    cut: {
                        store.copyGoalToClipboard(id: goal.id, cutsSource: true)
                        showsContextPopover = false
                    },
                    paste: {
                        _ = store.pasteGoalClipboard(
                            toWeekContaining: pasteWeekReference,
                            afterGoalID: goal.id
                        )
                        showsContextPopover = false
                    },
                    canPaste: store.hasGoalClipboard,
                    delete: {
                        store.deleteGoal(id: goal.id)
                        showsContextPopover = false
                    },
                    moveToNextWeek: {
                        store.moveGoalToNextWeek(id: goal.id)
                        showsContextPopover = false
                    }
                )
            }
        }
        .background {
            TaskCardKeyboardShortcutAnchor(
                isActive: isHovering || showsContextPopover,
                copy: {
                    store.copyGoalToClipboard(id: goal.id)
                    showsContextPopover = false
                },
                cut: {
                    store.copyGoalToClipboard(id: goal.id, cutsSource: true)
                    showsContextPopover = false
                },
                paste: {
                    _ = store.pasteGoalClipboard(
                        toWeekContaining: pasteWeekReference,
                        afterGoalID: goal.id
                    )
                    showsContextPopover = false
                },
                delete: {
                    store.deleteGoal(id: goal.id)
                    showsContextPopover = false
                },
                moveToNextWeek: {
                    store.moveGoalToNextWeek(id: goal.id)
                    showsContextPopover = false
                }
            )
        }
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 10)
                .stroke(goalCardBorder, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if let goalChannelColor {
                WeekflowRoundedRectangle(cornerRadius: 2)
                    .fill(goalChannelColor)
                    .frame(width: 3)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { store.highlightedTask = nil }
        }
        .pointingHandCursor(coversDescendants: true)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

struct WeeklyTaskPoolCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let tint: Color
    @Bindable var store: WeekflowStore
    let calendarAnchorDate: Date
    var dragStarted: (TaskDragToken) -> Void = { _ in }
    @State private var isHovering = false
    @State private var showsAssignmentPicker = false
    @State private var isAssignmentButtonHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                WeekflowRoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 5, height: 22)
                Text(subgoalTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(relationshipTitle)
                .font(.system(size: 10.5))
                .foregroundStyle(WeekflowPalette.textSecondary)
                .lineLimit(1)

            WeekflowButton {
                showsAssignmentPicker.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                    Text(assignmentActionLabel)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(
                    showsAssignmentPicker || isAssignmentButtonHovering
                        ? WeekflowPalette.objective
                        : WeekflowPalette.textSecondary
                )
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .onHover { isAssignmentButtonHovering = $0 }
            .background {
                TaskControlMenuAnchor(
                    isPresented: $showsAssignmentPicker,
                    menuSize: CGSize(width: 176, height: 274),
                    horizontalOffset: -WeekflowLayout.taskDurationMenuPointerWidth,
                    pointerCenterX: WeekflowLayout.taskDurationMenuPointerWidth * 1.5
                ) {
                    WeeklyTaskPoolDayPicker(
                        weekStart: calendarAnchorDate,
                        selectedDates: entry.task.assignedDates,
                        isUnset: entry.task.assignedDates.isEmpty && entry.task.plannedDate == nil,
                        toggle: toggleAssignment,
                        clear: clearAssignments
                    )
                    .frame(width: 176, height: 274, alignment: .topLeading)
                }
            }
        }
        .padding(8)
        .frame(width: 205, height: WeekflowLayout.weeklyTaskPoolCardHeight, alignment: .topLeading)
        .boxHoverChrome(
            isHovering: isHovering,
            cornerRadius: 9,
            fill: tint.opacity(0.09),
            border: tint.opacity(0.25),
            hoverBorder: tint.opacity(0.55)
        )
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 9))
        .pointingHandCursor()
        .onDrag {
            let token = TaskDragToken(goalID: entry.goal.id, taskID: entry.task.id)
            dragStarted(token)
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    WeekflowRoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 5, height: 22)
                    Text(subgoalTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(relationshipTitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .lineLimit(1)
                Label(assignmentActionLabel, systemImage: "calendar.badge.plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeekflowPalette.objective)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 205, height: WeekflowLayout.weeklyTaskPoolCardHeight, alignment: .topLeading)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 9))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.45), lineWidth: 1)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var subgoalTitle: String {
        guard let subgoalID = entry.task.subgoalID,
              let subgoal = entry.goal.subgoals.first(where: { $0.id == subgoalID }) else {
            return entry.task.title
        }
        return subgoal.title
    }

    private var relationshipTitle: String {
        entry.task.subgoalID == nil ? " " : entry.goal.title
    }

    private var weekDates: [Date] {
        let start = SystemBusinessCalendar.current.calendar.startOfDay(for: calendarAnchorDate)
        return (0..<7).compactMap {
            SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var assignmentActionLabel: String {
        let calendar = SystemBusinessCalendar.current.calendar
        let selected = weekDates.filter { date in
            entry.task.assignedDates.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        guard !selected.isEmpty else { return "安排" }
        return selected.map {
            $0.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).weekday(.short))
        }.joined(separator: "、")
    }

    private func toggleAssignment(_ date: Date) {
        if entry.task.isAssigned(on: date) {
            store.removeTaskAssignment(goalID: entry.goal.id, taskID: entry.task.id, from: date)
        } else {
            store.assignTask(goalID: entry.goal.id, taskID: entry.task.id, to: date)
        }
    }

    private func clearAssignments() {
        store.unassignTask(goalID: entry.goal.id, taskID: entry.task.id)
    }
}

private struct WeeklyTaskPoolDayPicker: View {
    let weekStart: Date
    let selectedDates: [Date]
    let isUnset: Bool
    let toggle: (Date) -> Void
    let clear: () -> Void

    private var dates: [Date] {
        let start = SystemBusinessCalendar.current.calendar.startOfDay(for: weekStart)
        return (0..<7).compactMap {
            SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("安排日期")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)

            Divider()

            ForEach(dates, id: \.self) { date in
                WeeklyTaskPoolDayRow(
                    leadingText: weekdayText(for: date),
                    detailText: monthDayText(for: date),
                    selected: selectedDates.contains {
                        SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date)
                    },
                    action: { toggle(date) }
                )
            }

            Divider()

            WeeklyTaskPoolDayRow(
                leadingText: "不设置",
                detailText: nil,
                selected: isUnset,
                action: clear
            )
        }
        .frame(width: 176, height: 274, alignment: .topLeading)
        .background(WeekflowPalette.surface)
    }

    private func weekdayText(for date: Date) -> String {
        date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).weekday(.short)
        )
    }

    private func monthDayText(for date: Date) -> String {
        date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).month().day()
        )
    }
}

private struct WeeklyTaskPoolDayRow: View {
    let leadingText: String
    let detailText: String?
    let selected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Text(leadingText)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .frame(width: 38, alignment: .leading)
                if let detailText {
                    Text(detailText)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.objective)
                }
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                isHovering || selected ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
        .padding(.horizontal, 4)
        .accessibilityLabel([leadingText, detailText].compactMap { $0 }.joined(separator: " "))
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

struct WeekDayColumn: View {
    let date: Date
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    @Bindable var store: WeekflowStore
    @Binding var draggedTaskToken: TaskDragToken?
    @State private var isDropTarget = false
    @State private var taskRowFrames: [UUID: CGRect] = [:]

    private var dragCoordinateSpace: String {
        "weekly-day-drop-\(SystemBusinessCalendar.current.day(containing: date).persistenceKey)"
    }

    init(
        date: Date,
        entries: [(goal: WeeklyGoal, task: WeekTask)],
        store: WeekflowStore,
        draggedTaskToken: Binding<TaskDragToken?> = .constant(nil)
    ) {
        self.date = date
        self.entries = entries
        self.store = store
        _draggedTaskToken = draggedTaskToken
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.headline)
                    Text(date.formatted(.dateTime.month().day())).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) 项")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Divider()
            ForEach(entries, id: \.task.id) { entry in
                WeeklyAssignedTaskCard(
                    entry: entry,
                    date: date,
                    tint: store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault,
                    channelTitle: store.channel(for: entry.task.channelID)?.title,
                    dragStarted: { draggedTaskToken = $0 },
                    remove: {
                        if entry.task.isAssigned(on: date) {
                            store.removeTaskAssignment(goalID: entry.goal.id, taskID: entry.task.id, from: date)
                        } else {
                            store.moveTask(goalID: entry.goal.id, taskID: entry.task.id, to: nil)
                        }
                    }
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: WeeklyTaskRowFramePreferenceKey.self,
                            value: [
                                entry.task.id: proxy.frame(in: .named(dragCoordinateSpace))
                            ]
                        )
                    }
                }
            }
            Spacer(minLength: 70)
        }
        .padding(12)
        .frame(width: 190, alignment: .topLeading)
        .frame(minHeight: 230, alignment: .topLeading)
        .background(
            isDropTarget ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover,
            in: WeekflowRoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            WeekflowRoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDropTarget ? WeekflowPalette.borderStrong : WeekflowPalette.border,
                    style: StrokeStyle(lineWidth: isDropTarget ? 2 : 1, dash: isDropTarget ? [6, 4] : [])
                )
        )
        .overlay {
            if isDropTarget {
                VStack {
                    Spacer()
                    Label("放到这里", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 12)
                }
            }
        }
        .contentShape(Rectangle())
        .coordinateSpace(name: dragCoordinateSpace)
        .onPreferenceChange(WeeklyTaskRowFramePreferenceKey.self) {
            taskRowFrames = $0
        }
        .onDrop(
            of: [.utf8PlainText],
            delegate: HomeColumnTaskDropDelegate(
                draggedTaskToken: $draggedTaskToken,
                date: date,
                rowFrames: { taskRowFrames },
                store: store,
                isDropTarget: $isDropTarget
            )
        )
        .animation(.easeOut(duration: 0.14), value: isDropTarget)
    }
}

private struct WeeklyTaskRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct WeeklyAssignedTaskCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let date: Date
    let tint: Color
    let channelTitle: String?
    let dragStarted: (TaskDragToken) -> Void
    let remove: () -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 7) {
                Circle()
                    .fill(entry.task.status == .completed ? WeekflowPalette.complete : tint)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
                Text(entry.task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isHovering {
                    WeekflowButton(action: remove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .foregroundStyle(WeekflowPalette.iconDefault)
                    .help("移除这一天的分配")
                }
            }

            Text(entry.goal.title)
                .font(.system(size: 9.5))
                .foregroundStyle(WeekflowPalette.textMuted)
                .lineLimit(1)

            HStack {
                Label(entry.task.estimatedMinutes.hourMinuteClockText, systemImage: "clock")
                Spacer()
                if let channel = channelTitle {
                    Label(channel, systemImage: "number")
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(tint)
        }
        .padding(7)
        .frame(
            maxWidth: .infinity,
            minHeight: WeekflowLayout.weeklyAssignedTaskCardMinimumHeight,
            alignment: .topLeading
        )
        .boxHoverChrome(
            isHovering: isHovering,
            cornerRadius: 8,
            fill: entry.task.status == .completed
                ? WeekflowPalette.complete.opacity(0.09)
                : tint.opacity(0.08),
            border: tint.opacity(0.25),
            hoverBorder: tint.opacity(0.55)
        )
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
        .pointingHandCursor()
        .onDrag {
            let token = TaskDragToken(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                sourceDate: date
            )
            dragStarted(token)
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(entry.goal.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .lineLimit(1)
            }
            .padding(7)
            .frame(
                width: 166,
                height: WeekflowLayout.weeklyAssignedTaskCardMinimumHeight,
                alignment: .topLeading
            )
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.45), lineWidth: 1)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

}

/// A simple wrapping layout makes the weekly task pool work at different window widths.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += lineHeight + spacing; lineHeight = 0 }
            x += size.width + spacing; lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += lineHeight + spacing; lineHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; lineHeight = max(lineHeight, size.height)
        }
    }
}
