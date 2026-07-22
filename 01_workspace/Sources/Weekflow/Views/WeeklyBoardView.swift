import SwiftUI

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

struct WeeklyPlanningRangeAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

enum WeeklyPlanningRangeBoundary {
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

struct WeeklyHeaderActionButton: View {
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

struct WeeklyHeaderUndoButton: View {
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

