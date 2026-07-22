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

private struct TaskHistoryItem: Identifiable {
    let id: String
    let date: Date
    let title: String
}

private enum TaskDetailMenu: Hashable {
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

private enum TaskDetailMorePage {
    case actions
    case recurrence
    case goalLink
}

private struct TaskDetailMenuAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [TaskDetailMenu: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [TaskDetailMenu: Anchor<CGRect>],
        nextValue: () -> [TaskDetailMenu: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TaskDetailSubtaskRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TaskDetailTextWeightHover: ViewModifier {
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

private let taskDetailSubtaskCoordinateSpace = "task-detail-subtasks"
private let taskDetailDragHandleWidth: CGFloat = 16
private let taskDetailDragHandleLeadingOffset: CGFloat = -26

private var taskDetailDragHandleCenterFromRowLeading: CGFloat {
    taskDetailDragHandleLeadingOffset + taskDetailDragHandleWidth / 2
}

private struct TaskDetailDragHandle: View {
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

struct TaskDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WeekflowStore
    let target: TaskDetailTarget
    private let menuDismissToken: Int
    private let usesScrollContainer: Bool
    private let onClose: (() -> Void)?

    @State private var title: String
    @State private var description: String
    @State private var notes: String
    @State private var channelID: String?
    @State private var priority: TaskPriority
    @State private var plannedDate: Date
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var startTime: Date
    @State private var hasStartTime: Bool
    @State private var estimatedMinutes: Int
    @State private var actualMinutes: Int
    @State private var initialTask: WeekTask?
    @State private var sessionOpeningTask: WeekTask?
    @State private var sessionCommitted = false
    @State private var subtaskRevealToken = 0
    @State private var focusedSubtaskID: UUID?
    @State private var hoveredSubtaskID: UUID?
    @State private var isAddSubtaskHovered = false
    @State private var draggedSubtaskID: UUID?
    @State private var draggedSubtaskPreviewLocation: CGPoint?
    @State private var dropTargetSubtaskID: UUID?
    @State private var subtaskRowFrames: [UUID: CGRect] = [:]
    @State private var activeMenu: TaskDetailMenu?
    @State private var morePage: TaskDetailMorePage = .actions
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isClosing = false

    private var entry: (goal: WeeklyGoal, task: WeekTask)? {
        store.activeTasks.first { $0.goal.id == target.goalID && $0.task.id == target.taskID }
            ?? store.archivedTasks.first { $0.goal.id == target.goalID && $0.task.id == target.taskID }
            ?? store.deletedTasks.first { $0.goal.id == target.goalID && $0.task.id == target.taskID }
    }

    init(
        store: WeekflowStore,
        target: TaskDetailTarget,
        menuDismissToken: Int = 0,
        usesScrollContainer: Bool = true,
        onClose: (() -> Void)? = nil
    ) {
        self.store = store
        self.target = target
        self.menuDismissToken = menuDismissToken
        self.usesScrollContainer = usesScrollContainer
        self.onClose = onClose
        let goal = store.goals.first(where: { $0.id == target.goalID })
        let task = goal?.tasks.first(where: { $0.id == target.taskID })
        let isPrimaryGoalDetail = goal?.primaryTaskID == task?.id
        _title = State(initialValue: task?.title ?? "")
        _description = State(initialValue: task?.description ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _channelID = State(initialValue: task?.channelID)
        _priority = State(initialValue: task?.priority ?? .none)
        _plannedDate = State(
            initialValue: task?.plannedDate
                ?? (isPrimaryGoalDetail ? goal?.startDate : nil)
                ?? .now
        )
        _dueDate = State(initialValue: task?.dueDate ?? task?.plannedDate ?? .now)
        _hasDueDate = State(initialValue: task?.dueDate != nil)
        _startTime = State(initialValue: task?.startTime ?? .now)
        _hasStartTime = State(initialValue: task?.startTime != nil)
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 60)
        _actualMinutes = State(initialValue: task?.actualMinutes ?? 0)
        _initialTask = State(initialValue: task)
        _sessionOpeningTask = State(initialValue: task)
    }

    var body: some View {
        Group {
            if let entry {
                DetailPageStructure {
                    propertyBar(entry)
                } content: {
                    if usesScrollContainer {
                        ScrollViewReader { proxy in
                            ScrollView { detailContent(entry) }
                                .scrollIndicators(.hidden)
                                .onChange(of: subtaskRevealToken) { _, _ in
                                    guard let focusedSubtaskID else { return }
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        proxy.scrollTo(focusedSubtaskID, anchor: .center)
                                    }
                                }
                        }
                    } else {
                        detailContent(entry)
                    }
                }
                .overlayPreferenceValue(TaskDetailMenuAnchorPreferenceKey.self) { anchors in
                    GeometryReader { proxy in
                        if let activeMenu, let anchor = anchors[activeMenu] {
                            ZStack(alignment: .topLeading) {
                                detailMenuOverlay(
                                    activeMenu,
                                    anchorFrame: proxy[anchor],
                                    containerSize: proxy.size,
                                    entry: entry
                                )
                                WindowOutsideClickMonitor(
                                    protectedRects: [
                                        detailMenuPanelFrame(
                                            activeMenu,
                                            anchorFrame: proxy[anchor],
                                            containerSize: proxy.size
                                        )
                                    ] + anchors.values.map { proxy[$0] },
                                    action: { self.activeMenu = nil }
                                )
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .onDisappear {
                    if !isClosing {
                        finishEditingSession(entry)
                    }
                }
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { activeMenu = nil }
                }
            } else {
                ContentUnavailableView("任务不存在", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(
            width: WeekflowLayout.taskDetailSheetWidth,
            height: WeekflowLayout.taskDetailSheetHeight,
            alignment: .topLeading
        )
        .background(WeekflowPalette.surface)
        .onChange(of: menuDismissToken) { _, _ in activeMenu = nil }
        .onExitCommand {
            if let entry {
                closeResponsively(entry)
            } else {
                closeDetail()
            }
        }
    }

    private func propertyBar(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        DetailPagePropertyBar {
            categoryPopoverButton(store.channel(for: channelID))
        } values: {
            propertyValues(entry)
        } actions: {
            propertyActions(entry)
        }
    }

    private func propertyValues(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(spacing: 8) {
            priorityPopoverButton
            if !target.isWeeklyGoalDetail {
                propertyPopoverButton(
                    title: "开始日期",
                    value: plannedDate.formatted(.dateTime.month().day()),
                    symbol: "calendar",
                    menu: .startDate
                )
                propertyPopoverButton(
                    title: "截止日期",
                    value: dueDatePropertyValue,
                    symbol: "calendar.badge.clock",
                    menu: .dueDate
                )
            }
            archivePropertyButton(entry)
        }
    }

    private func archivePropertyButton(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        Button {
            guard !isClosing,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            autosaveTask?.cancel()
            save(entry)
            activeMenu = nil
            isClosing = true
            sessionCommitted = true
            closeDetail()
            DispatchQueue.main.async {
                if target.isWeeklyGoalDetail {
                    store.archiveGoal(id: entry.goal.id)
                } else {
                    store.archiveTask(goalID: entry.goal.id, taskID: entry.task.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("归档")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
                HStack(spacing: 5) {
                    Image(systemName: "archivebox")
                        .foregroundStyle(WeekflowPalette.textMuted.opacity(0.68))
                    Text("未归档")
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                .font(.system(size: 12.5, weight: .medium))
            }
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 42, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }

    private var dueDatePropertyValue: String {
        let calendar = Calendar.current
        let effectiveDueDate = hasDueDate ? dueDate : plannedDate
        if calendar.isDateInToday(plannedDate),
           calendar.isDate(effectiveDueDate, inSameDayAs: plannedDate) {
            return "今天"
        }
        return effectiveDueDate.formatted(.dateTime.month().day())
    }

    private func propertyActions(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(spacing: 4) {
            ZStack {
                Label(target.isWeeklyGoalDetail ? "子目标" : "子任务", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .hidden()
                Button { toggleMoreMenu() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 42)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
                .accessibilityLabel("更多")
                .anchorPreference(
                    key: TaskDetailMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    [.more: anchor]
                }
            }
            .frame(height: 42)
            Color.clear
                .frame(width: 30, height: 42)
                .allowsHitTesting(false)
            Button {
                closeResponsively(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 30, height: 42)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
        }
    }

    private func categoryPopoverButton(_ channel: TaskChannel?) -> some View {
        Button { toggleMenu(.channel) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("分类")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
                HStack(spacing: 4) {
                    if let channel {
                        Image(systemName: channel.resolvedIconName)
                            .foregroundStyle(channel.color)
                    }
                    Text(channel?.title ?? "未分类")
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(WeekflowPalette.primaryText)
            }
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 42, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
        .anchorPreference(key: TaskDetailMenuAnchorPreferenceKey.self, value: .bounds) {
            [.channel: $0]
        }
    }

    private var priorityPopoverButton: some View {
        Button { toggleMenu(.priority) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("每日优先级")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
                HStack(spacing: 5) {
                    Image(systemName: priority.flagSymbol)
                        .foregroundStyle(priority.flagColor)
                    Text(priority == .none ? "优先级" : priority.label)
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(priority == .none ? WeekflowPalette.textMuted : WeekflowPalette.primaryText)
            }
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
        .anchorPreference(key: TaskDetailMenuAnchorPreferenceKey.self, value: .bounds) {
            [.priority: $0]
        }
    }

    private func propertyPopoverButton(
        title: String,
        value: String,
        symbol: String,
        menu: TaskDetailMenu
    ) -> some View {
        Button { toggleMenu(menu) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(WeekflowPalette.textMuted)
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                    Text(value)
                }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.primaryText)
            }
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 42, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
        .anchorPreference(
            key: TaskDetailMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [menu: anchor]
        }
    }

    private func detailMenuAction(
        _ title: String,
        symbol: String,
        tint: Color = WeekflowPalette.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .regular))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                Spacer()
            }
            .foregroundStyle(tint)
            .frame(height: 30)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }

    private func toggleMenu(_ menu: TaskDetailMenu) {
        activeMenu = activeMenu == menu ? nil : menu
    }

    private func closeDetail() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func toggleMoreMenu() {
        morePage = .actions
        toggleMenu(.more)
    }

    private func detailMenuOverlay(
        _ menu: TaskDetailMenu,
        anchorFrame: CGRect,
        containerSize: CGSize,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> some View {
        let size = detailMenuSize(menu)
        let panelFrame = detailMenuPanelFrame(
            menu,
            anchorFrame: anchorFrame,
            containerSize: containerSize
        )

        return ZStack(alignment: .topLeading) {
            detailMenuContent(menu, entry: entry)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipShape(WeekflowRoundedRectangle(cornerRadius: 6))
                .background {
                    WeekflowRoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WeekflowPalette.surface)
                }
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            WeekflowPalette.borderStrong.opacity(0.85),
                            lineWidth: 1,
                            antialiased: true
                        )
                }
                .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
                .position(
                    x: panelFrame.midX,
                    y: panelFrame.midY
                )
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
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
        .zIndex(1_000)
    }

    private func detailMenuPanelFrame(
        _ menu: TaskDetailMenu,
        anchorFrame: CGRect,
        containerSize: CGSize
    ) -> CGRect {
        let size = detailMenuSize(menu)
        let horizontalInset: CGFloat = 8
        let proposedX = anchorFrame.midX - size.width / 2
        let maximumX = max(containerSize.width - size.width - horizontalInset, horizontalInset)
        let panelX = min(max(proposedX, horizontalInset), maximumX)
        let panelTop = anchorFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        return CGRect(origin: CGPoint(x: panelX, y: panelTop), size: size)
    }

    private func detailMenuSize(_ menu: TaskDetailMenu) -> CGSize {
        switch menu {
        case .channel:
            CGSize(
                width: WeekflowLayout.taskDetailChannelMenuWidth,
                height: WeekflowLayout.taskChannelPopoverHeight(channelCount: store.activeChannels.count)
            )
        case .priority:
            CGSize(
                width: WeekflowLayout.taskDetailPriorityMenuWidth,
                height: WeekflowLayout.taskPriorityPopoverHeight
            )
        case .startDate:
            CGSize(
                width: WeekflowLayout.taskDetailDateMenuWidth,
                height: WeekflowLayout.taskDetailCalendarMenuHeight
            )
        case .dueDate:
            CGSize(
                width: WeekflowLayout.taskDetailDateMenuWidth,
                height: WeekflowLayout.taskDetailCalendarMenuHeight
            )
        case .more:
            switch morePage {
            case .actions:
                CGSize(width: 188, height: target.isWeeklyGoalDetail ? 100 : 164)
            case .recurrence:
                CGSize(width: 188, height: 190)
            case .goalLink:
                CGSize(
                    width: 188,
                    height: min(CGFloat(store.activeGoals.count) * 34 + 50, 244)
                )
            }
        case .startTime, .actualTime, .estimatedTime,
             .subtaskActualTime, .subtaskEstimatedTime:
            CGSize(width: 176, height: 244)
        }
    }

    @ViewBuilder
    private func detailMenuContent(
        _ menu: TaskDetailMenu,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> some View {
        switch menu {
        case .channel:
            TaskChannelPopover(
                channels: store.activeChannels,
                selectedChannelID: channelID,
                width: WeekflowLayout.taskDetailChannelMenuWidth,
                select: { selection in
                    channelID = selection
                    save(entry)
                },
                manage: {
                    activeMenu = nil
                    DispatchQueue.main.async {
                        WeekflowCommand.post(.weekflowOpenChannelSettings)
                    }
                }
            )
        case .priority:
            TaskPriorityPopover(
                selectedPriority: priority,
                width: WeekflowLayout.taskDetailPriorityMenuWidth
            ) { selection in
                priority = selection
                save(entry)
            }
        case .startDate:
            TaskDatePopover(
                selectedDate: plannedDate,
                exactWidth: WeekflowLayout.taskDetailDateMenuWidth,
                exactHeight: WeekflowLayout.taskDetailCalendarMenuHeight,
                showsQuickActions: false,
                highlightsToday: false,
                moveByDays: { moveStartDate(by: $0, entry: entry) },
                moveToDate: { setStartDate($0, entry: entry) }
            )
        case .dueDate:
            TaskDatePopover(
                selectedDate: dueDate,
                exactWidth: WeekflowLayout.taskDetailDateMenuWidth,
                exactHeight: WeekflowLayout.taskDetailCalendarMenuHeight,
                showsQuickActions: false,
                highlightsToday: false,
                minimumDate: plannedDate,
                highlightedRangeStart: hasDueDate ? plannedDate : nil,
                highlightedRangeEnd: hasDueDate ? dueDate : nil,
                moveByDays: { moveDueDate(by: $0, entry: entry) },
                moveToDate: { setDueDate($0, entry: entry) }
            )
        case .more:
            moreMenuContent(entry)
        case .startTime:
            ScrollClockTimePopover(
                selection: hasStartTime ? startTime : nil,
                anchorDate: plannedDate
            ) { selection in
                setStartTime(selection, entry: entry)
            }
        case .actualTime:
            ScrollDurationPopover(
                minutes: Binding(
                    get: {
                        TaskActualMinutesPolicy.resolved(
                            manual: actualMinutes,
                            live: store.liveTaskActualMinutes(goalID: entry.goal.id, taskID: entry.task.id),
                            timerIsRunning: isTimerRunning(entry)
                        )
                    },
                    set: { setActualMinutes($0, entry: entry) }
                ),
                range: 0...960,
                step: 15,
                title: "实际时间"
            )
        case .estimatedTime:
            ScrollDurationPopover(
                minutes: Binding(
                    get: { estimatedMinutes },
                    set: { setEstimatedMinutes($0, entry: entry) }
                ),
                range: 0...480,
                step: 15,
                title: "预计时间"
            )
        case let .subtaskActualTime(subtaskID):
            ScrollDurationPopover(
                minutes: Binding(
                    get: { subtask(entry, id: subtaskID)?.actualMinutes ?? 0 },
                    set: { setSubtaskActualMinutes($0, subtaskID: subtaskID, entry: entry) }
                ),
                range: 0...960,
                step: 15,
                title: "真实时间"
            )
        case let .subtaskEstimatedTime(subtaskID):
            ScrollDurationPopover(
                minutes: Binding(
                    get: { subtask(entry, id: subtaskID)?.plannedMinutes ?? 0 },
                    set: { setSubtaskPlannedMinutes($0, subtaskID: subtaskID, entry: entry) }
                ),
                range: 0...480,
                step: 15,
                title: "预计时间"
            )
        }
    }

    @ViewBuilder
    private func moreMenuContent(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        switch morePage {
        case .actions:
            VStack(spacing: 0) {
                HStack {
                    Text("其他操作")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textMuted)
                    Spacer()
                }
                .frame(height: 26)
                .padding(.horizontal, 8)
                if !target.isWeeklyGoalDetail {
                    detailMenuAction("重复功能", symbol: "arrow.triangle.2.circlepath") {
                        morePage = .recurrence
                    }
                    detailMenuAction("建立目标联系", symbol: "target") {
                        morePage = .goalLink
                    }
                }
                detailMenuAction("复制", symbol: "doc.on.doc") {
                    save(entry)
                    if target.isWeeklyGoalDetail {
                        _ = store.duplicateGoal(id: entry.goal.id)
                    } else {
                        _ = store.duplicateTask(
                            goalID: entry.goal.id,
                            taskID: entry.task.id,
                            persistImmediately: false
                        )
                    }
                }
                detailMenuAction("删除", symbol: "trash") {
                    guard !isClosing else { return }
                    autosaveTask?.cancel()
                    activeMenu = nil
                    isClosing = true
                    closeDetail()
                    DispatchQueue.main.async {
                        if target.isWeeklyGoalDetail {
                            store.deleteGoal(id: entry.goal.id)
                        } else {
                            store.deleteTask(goalID: entry.goal.id, taskID: entry.task.id)
                        }
                    }
                }
            }
            .padding(6)
            .background(WeekflowPalette.surface)
        case .recurrence:
            VStack(spacing: 0) {
                detailMenuBackHeader("重复功能")
                detailMenuSelectionRow(
                    "不重复",
                    symbol: "minus.circle",
                    selected: entry.task.recurringRule == nil
                ) {
                    setRecurrence(nil, entry: entry)
                }
                ForEach(RecurringFrequency.allCases) { frequency in
                    detailMenuSelectionRow(
                        frequency.label,
                        symbol: "arrow.triangle.2.circlepath",
                        selected: entry.task.recurringRule?.frequency == frequency
                    ) {
                        setRecurrence(RecurringRule(frequency: frequency), entry: entry)
                    }
                }
            }
            .padding(6)
            .background(WeekflowPalette.surface)
        case .goalLink:
            VStack(spacing: 0) {
                detailMenuBackHeader("建立目标联系")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.activeGoals) { goal in
                            detailMenuSelectionRow(
                                goal.title,
                                symbol: "target",
                                selected: goal.id == entry.goal.id
                            ) {
                                guard goal.id != entry.goal.id else { return }
                                moveTaskResponsively(entry, toGoalID: goal.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
            .padding(6)
            .background(WeekflowPalette.surface)
        }
    }

    private func detailMenuBackHeader(_ title: String) -> some View {
        Button {
            morePage = .actions
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(WeekflowPalette.textSecondary)
            .frame(height: 30)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }

    private func detailMenuSelectionRow(
        _ title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                Text(title).lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? WeekflowPalette.primaryText : WeekflowPalette.textSecondary)
            .frame(height: 30)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }

    private func detailContent(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleAndTiming(entry)
            subtaskList(entry)
                .padding(.top, 18)
            descriptionEditor(entry)
                .padding(.top, 24)
            historyTimeline(entry.task)
                .padding(.top, 30)
        }
        .detailPageContentLayout()
    }

    private func titleAndTiming(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(alignment: .center, spacing: 24) {
            titleEditor(entry)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            timingControls(entry)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func titleEditor(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                store.toggleTask(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    persistImmediately: false
                )
            } label: {
                Image(systemName: entry.task.status == .completed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(entry.task.status == .completed ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            TextField(target.isWeeklyGoalDetail ? "目标标题" : "任务标题", text: $title, axis: .vertical)
                .font(.system(size: 25, weight: .regular))
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .onChange(of: title) { _, _ in scheduleAutosave(entry) }
                .onSubmit { save(entry) }
        }
    }

    private func timingControls(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(spacing: WeekflowLayout.taskDetailTimeColumnSpacing) {
            if !target.isWeeklyGoalDetail {
                startTimeEditor
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                timeMetricEditor(
                    title: "真实时间",
                    value: detailActualTime(at: context.date),
                    menu: .actualTime
                )
                .task(id: detailTimerMinuteBucket(entry, at: context.date)) {
                    store.synchronizeActiveTaskTimer(at: context.date)
                }
            }
            timeMetricEditor(
                title: "预计时间",
                value: TaskTimeDisplay.estimated(minutes: estimatedMinutes),
                menu: .estimatedTime
            )
        }
        .font(.system(size: 12.5))
        .foregroundStyle(WeekflowPalette.secondaryText)
        .frame(width: WeekflowLayout.taskDetailTimingWidth)
    }

    private var startTimeEditor: some View {
        Button { toggleMenu(.startTime) } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .medium))
                Text(hasStartTime ? ScrollClockTimePopover.clockText(for: startTime) : "开始时间")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(WeekflowPalette.textMuted)
            .padding(.horizontal, 12)
            .frame(width: WeekflowLayout.taskDetailStartTimeControlWidth, height: 32)
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 5)
                    .strokeBorder(WeekflowPalette.border.opacity(0.9), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 5))
        .anchorPreference(key: TaskDetailMenuAnchorPreferenceKey.self, value: .bounds) {
            [.startTime: $0]
        }
    }

    private func timeMetricEditor(
        title: String,
        value: String,
        menu: TaskDetailMenu
    ) -> some View {
        Button { toggleMenu(menu) } label: {
            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeekflowPalette.primaryText)
                    .monospacedDigit()
            }
            .frame(width: WeekflowLayout.taskDetailTimeColumnWidth)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
        .anchorPreference(
            key: TaskDetailMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [menu: anchor]
        }
    }

    private func subtaskList(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.task.subtasks) { subtask in
                let isHovered = hoveredSubtaskID == subtask.id
                let isDragging = draggedSubtaskID == subtask.id
                let isDropTarget = dropTargetSubtaskID == subtask.id
                let isHighlighted = isHovered || isDragging || isDropTarget

                HStack(spacing: 12) {
                    Button {
                        store.toggleSubtask(
                            goalID: entry.goal.id,
                            taskID: entry.task.id,
                            subtaskID: subtask.id,
                            persistImmediately: false
                        )
                    } label: {
                        Image(systemName: subtask.completed ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(subtask.completed ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    TaskDetailSubtaskTextField(
                        text: subtaskTitleBinding(entry: entry, subtask: subtask),
                        placeholder: target.isWeeklyGoalDetail ? "子目标描述..." : "子任务描述...",
                        focusRequest: focusedSubtaskID == subtask.id ? subtaskRevealToken : nil,
                        onSubmit: { appendEmptySubtask(entry) },
                        onDeleteAtStart: {
                            deleteSubtaskAndRestoreFocus(entry, subtaskID: subtask.id)
                        }
                    )
                    .frame(height: 24)
                    .opacity(subtask.completed ? 0.58 : 1)
                    Spacer()
                    subtaskTimeValues(subtask)
                }
                .frame(minHeight: 32)
                .background(
                    isHighlighted ? WeekflowPalette.surfaceHover : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 6)
                )
                .opacity(isDragging ? 0.42 : 1)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    TaskDetailDragHandle(
                        isVisible: isHighlighted,
                        isDragging: isDragging
                    )
                    .contentShape(Rectangle())
                    .pointingHandCursor()
                    .gesture(subtaskDragGesture(entry, subtaskID: subtask.id))
                    .offset(x: taskDetailDragHandleLeadingOffset)
                    .help("拖动调整顺序")
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TaskDetailSubtaskRowFramePreferenceKey.self,
                            value: [
                                subtask.id: proxy.frame(
                                    in: .named(taskDetailSubtaskCoordinateSpace)
                                )
                            ]
                        )
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) {
                        if hovering {
                            hoveredSubtaskID = subtask.id
                        } else if hoveredSubtaskID == subtask.id {
                            hoveredSubtaskID = nil
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: isHighlighted)
                .animation(
                    .interactiveSpring(response: 0.22, dampingFraction: 0.84),
                    value: isDragging
                )
                .id(subtask.id)
            }

            Button(action: { appendEmptySubtask(entry) }) {
                HStack(spacing: 12) {
                    Image(systemName: isAddSubtaskHovered ? "plus.circle.fill" : "plus.circle")
                        .font(.system(size: 17, weight: isAddSubtaskHovered ? .semibold : .regular))
                        .frame(width: 22, height: 22)
                    Text(target.isWeeklyGoalDetail ? "添加子目标" : "添加子任务")
                        .font(.system(size: 12.5, weight: isAddSubtaskHovered ? .semibold : .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isAddSubtaskHovered
                    ? WeekflowPalette.objective
                    : WeekflowPalette.textMuted
            )
            .background(
                isAddSubtaskHovered ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .pointingHandCursor()
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isAddSubtaskHovered = hovering
                }
            }
        }
        .coordinateSpace(name: taskDetailSubtaskCoordinateSpace)
        .onPreferenceChange(TaskDetailSubtaskRowFramePreferenceKey.self) {
            subtaskRowFrames = $0
        }
        .overlay(alignment: .topLeading) {
            if let draggedSubtaskID,
               let previewLocation = draggedSubtaskPreviewLocation,
               let frame = subtaskRowFrames[draggedSubtaskID],
               let subtask = entry.task.subtasks.first(where: { $0.id == draggedSubtaskID }) {
                subtaskDragPreview(subtask)
                    .frame(width: frame.width, height: frame.height)
                    .position(previewLocation)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
        .animation(
            .interactiveSpring(response: 0.22, dampingFraction: 0.86),
            value: entry.task.subtasks.map(\.id)
        )
    }

    private func subtaskDragGesture(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(taskDetailSubtaskCoordinateSpace)
        )
        .onChanged { value in
            if draggedSubtaskID == nil {
                activeMenu = nil
                withAnimation(.easeInOut(duration: 0.12)) {
                    draggedSubtaskID = subtaskID
                    draggedSubtaskPreviewLocation = subtaskRowFrames[subtaskID].map { frame in
                        subtaskPreviewCenter(pointer: value.location, rowWidth: frame.width)
                    }
                }
            }
            guard draggedSubtaskID == subtaskID else { return }
            if let frame = subtaskRowFrames[subtaskID] {
                draggedSubtaskPreviewLocation = subtaskPreviewCenter(
                    pointer: value.location,
                    rowWidth: frame.width
                )
            }
            reorderSubtaskIfNeeded(
                entry,
                subtaskID: subtaskID,
                pointerY: value.location.y
            )
        }
        .onEnded { _ in
            withAnimation(.easeOut(duration: 0.14)) {
                draggedSubtaskID = nil
                draggedSubtaskPreviewLocation = nil
                dropTargetSubtaskID = nil
            }
        }
    }

    private func subtaskPreviewCenter(pointer: CGPoint, rowWidth: CGFloat) -> CGPoint {
        CGPoint(
            x: pointer.x + rowWidth / 2 - taskDetailDragHandleCenterFromRowLeading,
            y: pointer.y
        )
    }

    private func reorderSubtaskIfNeeded(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID,
        pointerY: CGFloat
    ) {
        let orderedIDs = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })?
            .subtasks.map(\.id) ?? []
        guard let sourceIndex = orderedIDs.firstIndex(of: subtaskID),
              !orderedIDs.isEmpty else { return }

        if let lastID = orderedIDs.last,
           lastID != subtaskID,
           let lastFrame = subtaskRowFrames[lastID],
           pointerY > lastFrame.maxY {
            dropTargetSubtaskID = lastID
            moveSubtaskWithAnimation(entry, subtaskID: subtaskID, to: nil)
            return
        }

        guard let targetID = orderedIDs.first(where: { id in
            guard let frame = subtaskRowFrames[id] else { return false }
            return frame.minY...frame.maxY ~= pointerY
        }),
        targetID != subtaskID,
        let targetIndex = orderedIDs.firstIndex(of: targetID),
        let targetFrame = subtaskRowFrames[targetID] else { return }

        let crossedTargetCenter = targetIndex > sourceIndex
            ? pointerY >= targetFrame.midY
            : pointerY <= targetFrame.midY
        guard crossedTargetCenter else { return }
        dropTargetSubtaskID = targetID
        moveSubtaskWithAnimation(entry, subtaskID: subtaskID, to: targetID)
    }

    private func moveSubtaskWithAnimation(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID,
        to targetSubtaskID: UUID?
    ) {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            store.moveSubtask(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                subtaskID: subtaskID,
                to: targetSubtaskID,
                persistImmediately: false
            )
        }
    }

    private func subtaskTimeValues(_ subtask: TaskSubtask) -> some View {
        HStack(spacing: WeekflowLayout.taskDetailTimeColumnSpacing) {
            Color.clear
                .frame(width: WeekflowLayout.taskDetailStartTimeControlWidth)
            subtaskTimeButton(
                value: TaskTimeDisplay.actual(
                    minutes: subtask.actualMinutes ?? 0,
                    estimatedMinutes: subtask.plannedMinutes ?? 0
                ),
                menu: .subtaskActualTime(subtask.id)
            )
            subtaskTimeButton(
                value: TaskTimeDisplay.estimated(minutes: subtask.plannedMinutes ?? 0),
                menu: .subtaskEstimatedTime(subtask.id)
            )
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(WeekflowPalette.textMuted)
        .monospacedDigit()
        .frame(width: WeekflowLayout.taskDetailTimingWidth, alignment: .trailing)
    }

    private func subtaskTimeButton(value: String, menu: TaskDetailMenu) -> some View {
        Button { toggleMenu(menu) } label: {
            Text(value)
                .frame(width: WeekflowLayout.taskDetailTimeColumnWidth, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskDetailTextWeightHover())
        .anchorPreference(
            key: TaskDetailMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [menu: anchor]
        }
        .accessibilityLabel("调整子任务时间")
    }

    private func subtaskDragPreview(_ subtask: TaskSubtask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: subtask.completed ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 17))
                .foregroundStyle(
                    subtask.completed ? WeekflowPalette.complete : WeekflowPalette.iconDefault
                )
                .frame(width: 22, height: 22)
            Text(
                subtask.title.isEmpty
                    ? (target.isWeeklyGoalDetail ? "子目标描述..." : "子任务描述...")
                    : subtask.title
            )
                .font(.system(size: 13))
                .foregroundStyle(
                    subtask.title.isEmpty ? WeekflowPalette.textMuted : WeekflowPalette.primaryText
                )
                .lineLimit(1)
            Spacer()
            HStack(spacing: WeekflowLayout.taskDetailTimeColumnSpacing) {
                Color.clear.frame(width: WeekflowLayout.taskDetailStartTimeControlWidth)
                Text(TaskTimeDisplay.actual(
                    minutes: subtask.actualMinutes ?? 0,
                    estimatedMinutes: subtask.plannedMinutes ?? 0
                ))
                    .frame(width: WeekflowLayout.taskDetailTimeColumnWidth)
                Text(TaskTimeDisplay.estimated(minutes: subtask.plannedMinutes ?? 0))
                    .frame(width: WeekflowLayout.taskDetailTimeColumnWidth)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(WeekflowPalette.textMuted)
            .monospacedDigit()
            .frame(width: WeekflowLayout.taskDetailTimingWidth, alignment: .trailing)
        }
        .overlay(alignment: .leading) {
            TaskDetailDragHandle(isVisible: true, isDragging: true)
                .offset(x: taskDetailDragHandleLeadingOffset)
        }
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 6))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 6)
                .stroke(WeekflowPalette.borderStrong.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 9, x: 0, y: 5)
    }

    private func descriptionEditor(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        TextField(target.isWeeklyGoalDetail ? "目标描述..." : "任务描述...", text: $description, axis: .vertical)
            .font(.system(size: 14))
            .foregroundStyle(WeekflowPalette.secondaryText)
            .textFieldStyle(.plain)
            .lineLimit(2...8)
            .frame(minHeight: 50, maxHeight: 142, alignment: .topLeading)
            .padding(.leading, 44)
            .onChange(of: description) { _, _ in scheduleAutosave(entry) }
            .onSubmit { save(entry) }
    }

    private func historyTimeline(_ task: WeekTask) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(WeekflowPalette.border.opacity(0.72))
                .frame(height: 1)
                .padding(.bottom, 18)
            ForEach(historyItems(for: task)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(WeekflowPalette.border)
                        .frame(width: 5, height: 5)
                    Text(item.title).foregroundStyle(WeekflowPalette.secondaryText)
                    Spacer(minLength: 16)
                    Text(item.date.formatted(.dateTime.month().day().hour().minute()))
                        .foregroundStyle(WeekflowPalette.textMuted)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .padding(.vertical, 5)
            }
        }
    }

    private func historyItems(for task: WeekTask) -> [TaskHistoryItem] {
        var items = task.changeRecords.map { record in
            TaskHistoryItem(
                id: "change-\(record.id.uuidString)",
                date: record.date,
                title: record.field == "任务详情"
                    ? "修改：\(record.newValue)"
                    : "\(historyFieldName(record.field))修改"
            )
        }
        items.append(TaskHistoryItem(id: "created", date: task.createdAt, title: "任务已创建"))
        return items.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id < $1.id
        }
    }

    private func historyFieldName(_ field: String) -> String {
        switch field {
        case "安排日期": "开始日期"
        case "说明": "任务描述"
        default: field
        }
    }

    private func scheduleAutosave(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            save(entry)
        }
    }

    private func save(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        guard let initialTask,
              let (updated, _) = editedTaskSnapshot(entry) else { return }
        let records = store.saveEditedTask(
            updated,
            original: initialTask,
            goalID: entry.goal.id,
            recordChanges: false,
            persistImmediately: false
        )
        guard !records.isEmpty else { return }
        self.initialTask = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })
    }

    private func editedTaskSnapshot(
        _ entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> (updated: WeekTask, current: WeekTask)? {
        guard let currentTask = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id }) else { return nil }
        var updated = currentTask
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = description
        updated.notes = notes
        updated.channelID = channelID
        updated.priority = priority
        let selectedPlannedDate = Calendar.current.startOfDay(for: plannedDate)
        let preservesUnassignedPrimaryGoal = entry.goal.primaryTaskID == currentTask.id
            && currentTask.plannedDate == nil
            && Calendar.current.isDate(selectedPlannedDate, inSameDayAs: entry.goal.startDate)
        updated.plannedDate = preservesUnassignedPrimaryGoal ? nil : selectedPlannedDate
        updated.dueDate = hasDueDate ? dueDate : nil
        updated.startTime = hasStartTime ? startTime : nil
        updated.estimatedMinutes = estimatedMinutes
        updated.actualMinutes = TaskActualMinutesPolicy.resolved(
            manual: actualMinutes,
            live: store.liveTaskActualMinutes(goalID: entry.goal.id, taskID: entry.task.id),
            timerIsRunning: isTimerRunning(entry)
        )
        return (updated, currentTask)
    }

    private func finishEditingSession(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        autosaveTask?.cancel()
        if discardEmptyWeeklyGoalDraftIfNeeded(entry) {
            sessionCommitted = true
            return
        }
        save(entry)
        guard !sessionCommitted, let sessionOpeningTask else { return }
        _ = store.recordTaskEditingSession(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            original: sessionOpeningTask
        )
        sessionCommitted = true
    }

    private func closeResponsively(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        guard !isClosing else { return }
        autosaveTask?.cancel()
        if discardEmptyWeeklyGoalDraftIfNeeded(entry) {
            isClosing = true
            sessionCommitted = true
            closeDetail()
            return
        }
        guard let sessionOpeningTask,
              let snapshot = editedTaskSnapshot(entry) else {
            isClosing = true
            closeDetail()
            return
        }

        isClosing = true
        sessionCommitted = true
        closeDetail()
        DispatchQueue.main.async {
            _ = store.saveEditedTask(
                snapshot.updated,
                original: snapshot.current,
                goalID: entry.goal.id,
                recordChanges: false,
                persistImmediately: false
            )
            _ = store.recordTaskEditingSession(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                original: sessionOpeningTask
            )
        }
    }

    @discardableResult
    private func discardEmptyWeeklyGoalDraftIfNeeded(
        _ entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> Bool {
        guard target.isNewWeeklyGoal,
              title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        store.discardGoalDraft(id: entry.goal.id)
        return true
    }

    private func moveTaskResponsively(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        toGoalID: UUID
    ) {
        guard !isClosing,
              let sessionOpeningTask,
              let snapshot = editedTaskSnapshot(entry) else { return }
        autosaveTask?.cancel()
        activeMenu = nil
        isClosing = true
        sessionCommitted = true
        closeDetail()

        DispatchQueue.main.async {
            _ = store.saveEditedTask(
                snapshot.updated,
                original: snapshot.current,
                goalID: entry.goal.id,
                recordChanges: false,
                persistImmediately: false
            )
            _ = store.recordTaskEditingSession(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                original: sessionOpeningTask,
                persistImmediately: false
            )
            _ = store.moveTask(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                toGoalID: toGoalID
            )
        }
    }

    private func setActualMinutes(_ value: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        actualMinutes = value
        save(entry)
    }

    private func setEstimatedMinutes(_ value: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        estimatedMinutes = value
        save(entry)
    }

    private func subtask(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        id subtaskID: UUID
    ) -> TaskSubtask? {
        store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })?
            .subtasks.first(where: { $0.id == subtaskID })
    }

    private func setSubtaskActualMinutes(
        _ value: Int,
        subtaskID: UUID,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) {
        store.updateSubtaskActualMinutes(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            subtaskID: subtaskID,
            minutes: value,
            persistImmediately: false
        )
    }

    private func setSubtaskPlannedMinutes(
        _ value: Int,
        subtaskID: UUID,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) {
        store.updateSubtaskPlannedMinutes(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            subtaskID: subtaskID,
            minutes: value,
            persistImmediately: false
        )
    }

    private func setStartTime(_ selection: Date?, entry: (goal: WeeklyGoal, task: WeekTask)) {
        hasStartTime = selection != nil
        if let selection { startTime = selection }
        save(entry)
    }

    private func moveStartDate(by offset: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: plannedDate) else { return }
        setStartDate(date, entry: entry)
    }

    private func setStartDate(_ date: Date, entry: (goal: WeeklyGoal, task: WeekTask)) {
        plannedDate = Calendar.current.startOfDay(for: date)
        if hasDueDate, dueDate < plannedDate {
            dueDate = plannedDate
        }
        save(entry)
    }

    private func moveDueDate(by offset: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        let baseDate = hasDueDate ? dueDate : plannedDate
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: baseDate) else { return }
        setDueDate(date, entry: entry)
    }

    private func setDueDate(_ date: Date, entry: (goal: WeeklyGoal, task: WeekTask)) {
        dueDate = Calendar.current.startOfDay(for: date)
        hasDueDate = true
        save(entry)
    }

    private func clearDueDate(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        hasDueDate = false
        save(entry)
    }

    private func setRecurrence(_ rule: RecurringRule?, entry: (goal: WeeklyGoal, task: WeekTask)) {
        store.setTaskRecurrence(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            rule: rule,
            recordChanges: false,
            persistImmediately: false
        )
        initialTask = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })
    }

    private func appendEmptySubtask(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        activeMenu = nil
        let subtaskID = store.addSubtask(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            title: "",
            persistImmediately: false
        )
        focusedSubtaskID = subtaskID
        subtaskRevealToken += 1
    }

    private func deleteSubtaskAndRestoreFocus(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID
    ) {
        guard let subtasks = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })?
            .subtasks,
            subtasks.contains(where: { $0.id == subtaskID }) else { return }

        let focusTarget = TaskDetailSubtaskFocusPolicy.targetAfterDeleting(
            subtaskID: subtaskID,
            from: subtasks
        )

        store.deleteSubtask(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            subtaskID: subtaskID,
            persistImmediately: false
        )
        focusedSubtaskID = focusTarget
        if focusTarget != nil {
            subtaskRevealToken += 1
        }
    }

    private func subtaskTitleBinding(
        entry: (goal: WeeklyGoal, task: WeekTask),
        subtask: TaskSubtask
    ) -> Binding<String> {
        Binding(
            get: {
                store.goals
                    .first(where: { $0.id == entry.goal.id })?
                    .tasks.first(where: { $0.id == entry.task.id })?
                    .subtasks.first(where: { $0.id == subtask.id })?
                    .title ?? subtask.title
            },
            set: {
                store.updateSubtaskTitle(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    subtaskID: subtask.id,
                    title: $0,
                    persistImmediately: false
                )
            }
        )
    }

    private func detailActualTime(at date: Date) -> String {
        TaskTimeDisplay.actual(
            minutes: max(
                actualMinutes,
                store.liveTaskActualMinutes(goalID: target.goalID, taskID: target.taskID, at: date)
            ),
            estimatedMinutes: estimatedMinutes
        )
    }

    private func isTimerRunning(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> Bool {
        store.isTaskTimerRunning(goalID: entry.goal.id, taskID: entry.task.id)
    }

    private func detailTimerMinuteBucket(_ entry: (goal: WeeklyGoal, task: WeekTask), at date: Date) -> Int {
        guard let startedAt = store.taskTimerStartedAt(goalID: entry.goal.id, taskID: entry.task.id) else { return -1 }
        return max(Int(date.timeIntervalSince(startedAt)) / 60, 0)
    }
}

struct ShortcutHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("?", "打开快捷键说明"),
        ("A", "新建任务"),
        ("Enter / ⌘ Enter", "打开高亮任务 / 保存后打开详情"),
        ("Space", "开始或暂停当前任务"),
        ("C", "切换完成状态"),
        ("F", "进入专注模式"),
        ("X", "自动安排到当天日历"),
        ("D", "推迟一天"),
        ("Z", "移入待办箱"),
        ("⌘ Delete", "删除高亮任务")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷键").font(.title2.weight(.bold))
            ForEach(shortcuts, id: \.0) { item in
                HStack {
                    Text(item.0).font(.system(.body)).padding(.horizontal, 7).padding(.vertical, 3).background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 5))
                    Text(item.1)
                    Spacer()
                }
            }
            Spacer()
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(24)
        .frame(width: 390, height: 420, alignment: .topLeading)
    }
}
