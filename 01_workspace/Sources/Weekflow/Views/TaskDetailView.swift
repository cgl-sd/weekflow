import SwiftUI

struct TaskDetailView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var store: WeekflowStore
    let target: TaskDetailTarget
    let menuDismissToken: Int
    let usesScrollContainer: Bool
    let onClose: (() -> Void)?

    @State var title: String
    @State var description: String
    @State var notes: String
    @State var channelID: String?
    @State var priority: TaskPriority
    @State var plannedDate: Date
    @State var dueDate: Date
    @State var hasDueDate: Bool
    @State var startTime: Date
    @State var hasStartTime: Bool
    @State var estimatedMinutes: Int
    @State var actualMinutes: Int
    @State var initialTask: WeekTask?
    @State var sessionOpeningTask: WeekTask?
    @State var sessionCommitted = false
    @State var subtaskRevealToken = 0
    @State var focusedSubtaskID: UUID?
    @State var hoveredSubtaskID: UUID?
    @State var isAddSubtaskHovered = false
    @State var draggedSubtaskID: UUID?
    @State var draggedSubtaskPreviewLocation: CGPoint?
    @State var dropTargetSubtaskID: UUID?
    @State var subtaskRowFrames: [UUID: CGRect] = [:]
    @State var activeMenu: TaskDetailMenu?
    @State var morePage: TaskDetailMorePage = .actions
    @State var autosaveTask: Task<Void, Never>?
    @State var isClosing = false

    var entry: (goal: WeeklyGoal, task: WeekTask)? {
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
        WeekflowButton {
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

    var dueDatePropertyValue: String {
        let calendar = SystemBusinessCalendar.current.calendar
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
                WeekflowButton { toggleMoreMenu() } label: {
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
            WeekflowButton {
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
        WeekflowButton { toggleMenu(.channel) } label: {
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

    var priorityPopoverButton: some View {
        WeekflowButton { toggleMenu(.priority) } label: {
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
        WeekflowButton { toggleMenu(menu) } label: {
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

}
