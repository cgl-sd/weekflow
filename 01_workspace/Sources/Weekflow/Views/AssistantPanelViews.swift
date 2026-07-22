import SwiftUI

extension View {
    func assistantPanelLeadingDivider() -> some View {
        overlay(alignment: .leading) {
            Rectangle()
                .fill(WeekflowPalette.border)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
    }
}

struct SunsamaAssistantRail: View {
    @Bindable var store: WeekflowStore
    @Binding var activePanel: AssistantPanel?
    @Binding var showingTaskForm: Bool

    var body: some View {
        VStack(spacing: 4) {
            AssistantRailCollapseButton(isExpanded: activePanel != nil) {
                activePanel = activePanel == nil ? .calendar : nil
            }
            ForEach(AssistantPanel.railCases) { item in
                AssistantRailButton(
                    item: item,
                    isSelected: activePanel == item
                ) {
                    activePanel = AssistantPanel.toggled(item, current: activePanel)
                }
            }
            Spacer()
        }
        .padding(.top, 9)
        .padding(.bottom, 16)
        .padding(.horizontal, 4)
        .background(WeekflowPalette.canvas)
    }
}

private struct AssistantRailCollapseButton: View {
    let isExpanded: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.right.2" : "chevron.left.2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .frame(width: 40, height: 40)
                .background(isHovering ? WeekflowPalette.surfaceSelected : .clear, in: WeekflowRoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { isHovering = $0 }
        .help(isExpanded ? "收起右侧栏" : "展开右侧栏")
    }
}

private struct AssistantRailButton: View {
    let item: AssistantPanel
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var isHighlighted: Bool {
        SidebarRowVisualState.resolve(
            isSelected: isSelected,
            isHovering: isHovering
        ) == .highlighted
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isHighlighted ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    isHighlighted ? WeekflowPalette.surfaceSelected : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(item.title)
    }
}

struct SunsamaAssistantPanel: View {
    @Bindable var store: WeekflowStore
    let panel: AssistantPanel
    @Binding var activeDate: Date
    @Binding var calendarPresentation: AssistantCalendarPresentation
    @Binding var selectedChannelID: String
    let openCalendarDate: (Date) -> Void
    let returnToDashboard: (Date) -> Void
    let addTaskOnDate: (Date) -> Void
    let planDay: (Date) -> Void
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void
    @State private var showsTaskFilter = false
    @State private var showsCalendarOptions = false
    @State private var isPanelTitleHovering = false
    @AppStorage("weekflow.calendar.showsDailyCutoff")
    private var showsDailyCutoff = true

    init(
        store: WeekflowStore,
        panel: AssistantPanel,
        activeDate: Binding<Date>,
        calendarPresentation: Binding<AssistantCalendarPresentation> = .constant(.timeline),
        selectedChannelID: Binding<String> = .constant("all"),
        openCalendarDate: @escaping (Date) -> Void = { _ in },
        returnToDashboard: @escaping (Date) -> Void = { _ in },
        addTaskOnDate: @escaping (Date) -> Void = { _ in },
        planDay: @escaping (Date) -> Void = { _ in },
        openTask: @escaping ((goal: WeeklyGoal, task: WeekTask)) -> Void = { _ in }
    ) {
        self.store = store
        self.panel = panel
        _activeDate = activeDate
        _calendarPresentation = calendarPresentation
        _selectedChannelID = selectedChannelID
        self.openCalendarDate = openCalendarDate
        self.returnToDashboard = returnToDashboard
        self.addTaskOnDate = addTaskOnDate
        self.planDay = planDay
        self.openTask = openTask
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack {
                    if panel == .calendar && calendarPresentation == .dayTasks {
                        AssistantTaskFilterButton(isPresented: showsTaskFilter) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                showsTaskFilter.toggle()
                            }
                        }
                    } else if panel == .calendar {
                        Button {
                            withAnimation(.easeOut(duration: 0.12)) {
                                showsCalendarOptions.toggle()
                            }
                        } label: {
                            Label(panel.title, systemImage: panel.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 7)
                                .frame(minHeight: 24)
                                .background(
                                    isPanelTitleHovering || showsCalendarOptions
                                        ? WeekflowPalette.surfaceSelected
                                        : .clear,
                                    in: WeekflowRoundedRectangle(cornerRadius: 5)
                                )
                                .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .stablePointingHandHover { isPanelTitleHovering = $0 }
                        .help("日历显示设置")
                    } else {
                        Label(panel.title, systemImage: panel.symbol)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                }
                .frame(height: 24)
                .padding(.horizontal, 14)
                .padding(.top, 17)
                .padding(.bottom, 4)
                Divider()

                Group {
                    switch panel {
                    case .calendar:
                        if calendarPresentation == .timeline {
                            AssistantCalendarView(
                                store: store,
                                activeDate: $activeDate,
                                openDayTasks: openCalendarDate
                            )
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        } else {
                            AssistantDayTaskListView(
                                store: store,
                                activeDate: $activeDate,
                                selectedChannelID: selectedChannelID,
                                addTask: { addTaskOnDate(activeDate) },
                                returnToDashboard: {
                                    showsTaskFilter = false
                                    returnToDashboard(activeDate)
                                },
                                planDay: { planDay(activeDate) }
                            )
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    case .goals: AssistantGoalsView(store: store)
                    case .backlog: AssistantBacklogView(store: store, openTask: openTask)
                    case .shutdown: AssistantShutdownView(store: store)
                    case .search: AssistantSearchView(store: store, openTask: openTask)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showsTaskFilter && panel == .calendar && calendarPresentation == .dayTasks {
                assistantTaskFilterOverlay
                    .zIndex(5)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
            }

            if showsCalendarOptions && panel == .calendar && calendarPresentation == .timeline {
                assistantCalendarOptionsOverlay
                    .zIndex(5)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
            }
        }
        .background(WeekflowPalette.canvas)
        .overlay {
            SecondaryClickOcclusionRegion()
                .allowsHitTesting(false)
        }
    }

    private var assistantCalendarOptionsOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissCalendarOptions() }

            AssistantCalendarOptionsMenu(
                showsDailyCutoff: showsDailyCutoff,
                toggleDailyCutoff: {
                    showsDailyCutoff.toggle()
                    dismissCalendarOptions()
                }
            )
            .frame(width: 196, height: 44, alignment: .topLeading)
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .fill(WeekflowPalette.surface)
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .offset(x: 14, y: 52)

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
                .offset(x: 35, y: 45)
        }
    }

    private func dismissCalendarOptions() {
        withAnimation(.easeOut(duration: 0.1)) {
            showsCalendarOptions = false
        }
    }

    private var assistantTaskFilterOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showsTaskFilter = false
                    }
                }

            TaskFilterPopover(
                store: store,
                selection: $selectedChannelID,
                dismiss: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showsTaskFilter = false
                    }
                }
            )
            .frame(
                width: WeekflowLayout.taskFilterPopoverWidth,
                height: WeekflowLayout.taskFilterPopoverMaximumHeight,
                alignment: .topLeading
            )
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .fill(WeekflowPalette.surface)
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .offset(x: 14, y: 52)

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
                .offset(x: 35, y: 45)
        }
    }
}

struct AssistantCalendarOptionsMenu: View {
    let showsDailyCutoff: Bool
    let toggleDailyCutoff: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: toggleDailyCutoff) {
            HStack(spacing: 9) {
                Image(systemName: showsDailyCutoff ? "flag.checkered" : "flag")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 17)
                Text("显示任务截止时间")
                    .font(.system(size: 12.5, weight: .regular))
                Spacer(minLength: 8)
                if showsDailyCutoff {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                }
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                isHovering ? WeekflowPalette.surfaceSelected : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .padding(4)
    }
}

private struct AssistantTaskFilterButton: View {
    let isPresented: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("筛选", systemImage: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    isHovering || isPresented
                        ? WeekflowPalette.primaryText
                        : WeekflowPalette.secondaryText
                )
                .padding(.horizontal, 7)
                .frame(minHeight: 24)
                .background(
                    isHovering || isPresented ? WeekflowPalette.surfaceSelected : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 5)
                )
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { isHovering = $0 }
        .help("筛选当天任务")
    }
}

struct AssistantCalendarView: View {
    @Bindable var store: WeekflowStore
    @Binding var activeDate: Date
    var openDayTasks: ((Date) -> Void)? = nil
    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 44
    @State private var resizePreviewMinutes: [UUID: Int] = [:]
    @State private var isDateHovering = false
    @AppStorage("weekflow.calendar.showsDailyCutoff")
    private var showsDailyCutoff = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .pointingHandCursor()
                Spacer()
                if let openDayTasks {
                    Button {
                        openDayTasks(activeDate)
                    } label: {
                        calendarDateLabel
                            .background(
                                isDateHovering ? WeekflowPalette.surfaceSelected : .clear,
                                in: WeekflowRoundedRectangle(cornerRadius: 5)
                            )
                            .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isDateHovering = hovering
                        }
                    }
                    .help("在月历中查看当天任务")
                } else {
                    calendarDateLabel
                }
                Spacer()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                    .pointingHandCursor()
            }
            .buttonStyle(.plain)

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        ForEach(CalendarTimelineLayout.hourRange, id: \.self) { hour in
                            let y = CGFloat(hour - CalendarTimelineLayout.firstHour) * hourHeight
                            Text(String(format: "%02d:00", hour))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(WeekflowPalette.secondaryText.opacity(0.68))
                                .frame(width: 38, alignment: .trailing)
                                .offset(y: y + 3)
                            Rectangle()
                                .fill(WeekflowPalette.border.opacity(0.42))
                                .frame(
                                    width: max(proxy.size.width - 44 - WeekflowLayout.scrollbarGutterWidth, 1),
                                    height: 0.5
                                )
                                .offset(x: 44, y: y)
                        }

                        ForEach(Array(scheduledItems.enumerated()), id: \.element.id) { index, item in
                            let lane = laneInfo(for: index)
                            let availableWidth = max(
                                proxy.size.width - 50 - WeekflowLayout.scrollbarGutterWidth,
                                1
                            )
                            let laneWidth = max(availableWidth / CGFloat(lane.count) - 2, 42)
                            let displayedMinutes = resizePreviewMinutes[item.id] ?? item.minutes
                            AssistantTimeBlock(
                                item: item,
                                displayedMinutes: displayedMinutes,
                                openTask: { openTask(item.taskReference, on: item.start) },
                                pinTask: {
                                    togglePin(item.taskReference)
                                },
                                resizePreview: { previewResize(itemID: item.id, minutes: $0) },
                                resizeCommit: { minutes in
                                    if let reference = item.taskReference {
                                        store.updateTaskEstimatedMinutes(
                                            goalID: reference.goalID,
                                            taskID: reference.taskID,
                                            minutes: minutes
                                        )
                                    }
                                    resizePreviewMinutes.removeValue(forKey: item.id)
                                }
                            )
                                .frame(width: laneWidth, height: blockHeight(minutes: displayedMinutes))
                                .offset(
                                    x: 46 + CGFloat(lane.index) * (availableWidth / CGFloat(lane.count)),
                                    y: blockOffset(item)
                                )
                                .transaction { transaction in
                                    transaction.animation = nil
                                }
                        }

                        if showsDailyCutoff, let cutoffDate = displayedCutoffDate {
                            CalendarCutoffFence()
                                .frame(
                                    width: max(
                                        proxy.size.width - 50 - WeekflowLayout.scrollbarGutterWidth,
                                        1
                                    )
                                )
                                .offset(
                                    x: 46,
                                    y: CalendarTimelineLayout.offset(
                                        for: cutoffDate,
                                        hourHeight: hourHeight,
                                        calendar: calendar
                                    ) - 4
                                )
                                .zIndex(2)
                        }
                    }
                    .frame(
                        width: max(proxy.size.width - WeekflowLayout.scrollbarGutterWidth, 1),
                        height: CalendarTimelineLayout.contentHeight(hourHeight: hourHeight),
                        alignment: .topLeading
                    )
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onDrop(of: [.utf8PlainText], isTargeted: nil) { providers in
            schedule(providers)
        }
    }

    private var calendarDateLabel: some View {
        Text(activeDate.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday(.short)
        ))
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WeekflowPalette.secondaryText)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
    }

    private var scheduledItems: [AssistantScheduleItem] {
        let tasks = store.tasks(on: activeDate).compactMap { entry -> AssistantScheduleItem? in
            guard let start = entry.task.startTime else { return nil }
            guard CalendarTimelineLayout.contains(start, calendar: calendar) else { return nil }
            return AssistantScheduleItem(
                id: entry.task.id,
                title: entry.task.title,
                detail: taskDetail(entry.task),
                start: start,
                minutes: max(entry.task.estimatedMinutes, 15),
                color: store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault,
                priority: entry.task.priority,
                placement: entry.task.calendarPlacement,
                taskReference: TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
            )
        }
        let cutoffID = store.dailyPlanningCutoffEvent(on: activeDate)?.id
        let events = store.events(on: activeDate).compactMap { event -> AssistantScheduleItem? in
            guard event.id != cutoffID else { return nil }
            guard CalendarTimelineLayout.contains(event.startDate, calendar: calendar) else { return nil }
            return AssistantScheduleItem(
                id: event.id,
                title: event.title,
                detail: "日历事件",
                start: event.startDate,
                minutes: max(event.durationMinutes, 15),
                color: eventColor(event.colorName),
                priority: nil,
                placement: nil,
                taskReference: nil
            )
        }
        return (tasks + events).sorted { $0.start < $1.start }
    }

    private var displayedCutoffDate: Date? {
        let configured = store.dailyPlanningCutoffEvent(on: activeDate)?.startDate
            ?? defaultCutoffDate
        let finalTaskEnd = scheduledItems.compactMap { item -> Date? in
            guard item.taskReference != nil else { return nil }
            return calendar.date(byAdding: .minute, value: item.minutes, to: item.start)
        }.max()
        return max(configured, finalTaskEnd ?? configured)
    }

    private var defaultCutoffDate: Date {
        let minutes = store.dailyPlanningCutoffMinutes(on: activeDate)
        var components = calendar.dateComponents([.year, .month, .day], from: activeDate)
        components.hour = minutes / 60
        components.minute = minutes % 60
        components.second = 0
        return calendar.date(from: components) ?? activeDate
    }

    private func blockOffset(_ item: AssistantScheduleItem) -> CGFloat {
        CalendarTimelineLayout.offset(for: item.start, hourHeight: hourHeight, calendar: calendar)
    }

    private func blockHeight(minutes: Int) -> CGFloat {
        max(18, CGFloat(minutes) / 60 * hourHeight - 2)
    }

    private func previewResize(itemID: UUID, minutes: Int) {
        guard resizePreviewMinutes[itemID] != minutes else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            resizePreviewMinutes[itemID] = minutes
        }
    }

    private func openTask(_ reference: TaskReference?, on date: Date) {
        guard let reference else { return }
        store.highlightedTask = reference
        store.activeDay = date
        WeekflowCommand.post(.weekflowOpenHighlightedTask)
    }

    private func togglePin(_ reference: TaskReference?) {
        guard let reference else { return }
        store.toggleTaskCalendarCommitment(
            goalID: reference.goalID,
            taskID: reference.taskID
        )
    }

    private func laneInfo(for index: Int) -> (index: Int, count: Int) {
        let item = scheduledItems[index]
        let itemEnd = calendar.date(byAdding: .minute, value: item.minutes, to: item.start) ?? item.start
        let overlappingIndices = scheduledItems.indices.filter { candidateIndex in
            let candidate = scheduledItems[candidateIndex]
            let candidateEnd = calendar.date(byAdding: .minute, value: candidate.minutes, to: candidate.start) ?? candidate.start
            return candidate.start < itemEnd && item.start < candidateEnd
        }
        let laneIndex = overlappingIndices.firstIndex(of: index) ?? 0
        return (laneIndex, max(overlappingIndices.count, 1))
    }

    private func shiftDay(_ value: Int) {
        activeDate = calendar.date(byAdding: .day, value: value, to: activeDate) ?? activeDate
    }

    private func schedule(_ providers: [NSItemProvider]) -> Bool {
        TaskDropCoordinator.handle(providers: providers) { ids in
            store.relocateTask(
                goalID: ids.goalID,
                taskID: ids.taskID,
                from: ids.sourceDate,
                to: activeDate
            )
            store.highlightedTask = TaskReference(goalID: ids.goalID, taskID: ids.taskID)
            store.activeDay = activeDate
            store.autoScheduleHighlightedTask()
        }
    }

    private func eventColor(_ name: String) -> Color {
        switch name {
        case "orange": .orange
        case "purple": .purple
        case "blue": .blue
        case "red": .red
        default: .gray
        }
    }

    private func taskDetail(_ task: WeekTask) -> String {
        let source = task.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            : task.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "计划任务" }
        return String(source.prefix(28))
    }
}

private struct AssistantDayTaskListView: View {
    @Bindable var store: WeekflowStore
    @Binding var activeDate: Date
    let selectedChannelID: String
    let addTask: () -> Void
    let returnToDashboard: () -> Void
    let planDay: () -> Void
    @State private var draggedTaskToken: TaskDragToken?

    var body: some View {
        GeometryReader { proxy in
            HomeDayColumn(
                date: activeDate,
                entries: store.tasks(on: activeDate, channelID: selectedChannelID),
                addTask: addTask,
                selectDate: returnToDashboard,
                planDate: planDay,
                openTask: openTask,
                store: store,
                draggedTaskToken: $draggedTaskToken,
                width: proxy.size.width,
                highlightsDateHeader: true,
                dateSelectionHelp: "返回首页仪表盘"
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func openTask(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        store.highlightedTask = TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
        store.activeDay = activeDate
        WeekflowCommand.post(.weekflowOpenHighlightedTask)
    }
}

private struct AssistantScheduleItem: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let start: Date
    let minutes: Int
    let color: Color
    let priority: TaskPriority?
    let placement: TaskCalendarPlacement?
    let taskReference: TaskReference?
}

private struct AssistantTimeBlock: View {
    let item: AssistantScheduleItem
    let displayedMinutes: Int
    let openTask: () -> Void
    let pinTask: () -> Void
    let resizePreview: (Int) -> Void
    let resizeCommit: (Int) -> Void
    @State private var isHovering = false
    @State private var resizeBaseMinutes: Int?
    @State private var isResizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.system(size: 10, weight: .semibold)).lineLimit(2)
            if displayedMinutes >= 30 {
                Text(timeRangeText)
                    .font(.system(size: 8))
                    .opacity(0.72)
            }
        }
        .foregroundStyle(item.placement == .committed ? Color.white : WeekflowPalette.primaryText)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if item.placement == .committed {
                WeekflowRoundedRectangle(cornerRadius: 4)
                    .fill(item.color.opacity(isHovering || isResizing ? 0.94 : 0.84))
            } else if item.placement == .suggested {
                WeekflowRoundedRectangle(cornerRadius: 4)
                    .fill(item.color.opacity(isHovering ? 0.14 : 0.08))
                    .overlay {
                        DottedAssistantCalendarFill(color: item.color.opacity(isHovering ? 0.50 : 0.38))
                    }
                    .overlay {
                        WeekflowRoundedRectangle(cornerRadius: 4)
                            .stroke(item.color.opacity(0.34), lineWidth: 1)
                    }
            } else {
                WeekflowRoundedRectangle(cornerRadius: 4)
                    .fill(item.color.opacity(isHovering ? 0.30 : 0.20))
            }
        }
        .overlay(alignment: .top) {
            if item.placement == .committed {
                AssistantCalendarStartFence()
                    .stroke(.white.opacity(0.72), lineWidth: 1.3)
                    .frame(height: 5)
                    .offset(y: -1)
            }
        }
        .overlay(alignment: .bottom) {
            if item.placement == .committed {
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(height: 22)
                        .gesture(resizeGesture)
                        .pointingHandCursor()
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.90))
                        .padding(.bottom, 3)
                        .opacity(isHovering || isResizing ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
        }
        .background {
            CalendarHoverCardAnchor(
                isPresented: isHovering && !isResizing,
                model: CalendarHoverCardModel(
                    title: item.title,
                    timeRange: timeRangeText,
                    calendarName: "Weekflow 日历",
                    channelName: item.detail,
                    color: item.color,
                    priority: item.priority,
                    isCommitted: item.placement == .committed,
                    isTask: item.taskReference != nil
                ),
                openTask: openTask,
                pinTask: pinTask
            )
        }
        .shadow(color: item.color.opacity(isHovering || isResizing ? 0.18 : 0), radius: 4, y: 1)
        .onHover { hovering in
            isHovering = hovering
        }
        .pointingHandCursor(coversDescendants: true)
        .clipped()
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if resizeBaseMinutes == nil { resizeBaseMinutes = item.minutes }
                isResizing = true
                let delta = Int((value.translation.height / 44 * 60 / 15).rounded()) * 15
                resizePreview(max((resizeBaseMinutes ?? item.minutes) + delta, 15))
            }
            .onEnded { value in
                let delta = Int((value.translation.height / 44 * 60 / 15).rounded()) * 15
                let finalMinutes = max((resizeBaseMinutes ?? item.minutes) + delta, 15)
                resizeBaseMinutes = nil
                isResizing = false
                resizeCommit(finalMinutes)
            }
    }

    private var timeRangeText: String {
        let end = item.start.addingTimeInterval(TimeInterval(displayedMinutes * 60))
        return "\(item.start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct DottedAssistantCalendarFill: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 3.0, through: size.height, by: 6.0) {
                for x in stride(from: 3.0, through: size.width, by: 6.0) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

private struct AssistantCalendarStartFence: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: min(x + 5, rect.maxX), y: rect.minY))
            path.addLine(to: CGPoint(x: min(x + 10, rect.maxX), y: rect.maxY))
            x += 10
        }
        return path
    }
}

private struct AssistantGoalsView: View {
    @Bindable var store: WeekflowStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Date.weekRangeLabel).foregroundStyle(WeekflowPalette.secondaryText)
            ForEach(store.activeGoals) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.title).lineLimit(2)
                    WeekflowDailyProgressTrack(
                        fraction: goal.progress,
                        hasProgress: goal.progress > 0,
                        alwaysVisible: true,
                        accessibilityLabel: "周目标完成进度",
                        accessibilityValue: "已完成 \(Int(goal.progress * 100))%"
                    )
                    .frame(height: WeekflowLayout.homeDailyProgressHeight)
                }
            }
            Spacer()
        }
    }
}

private struct AssistantBacklogView: View {
    @Bindable var store: WeekflowStore
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void

    var body: some View {
        AssistantTaskCardList(
            entries: store.taskPool,
            store: store,
            emptyTitle: "待办箱为空",
            openTask: openTask
        )
    }
}

private struct AssistantShutdownView: View {
    @Bindable var store: WeekflowStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                archiveMetricStrip
                Divider()
                Text("今日成果")
                    .font(.system(size: 12, weight: .semibold))
                if completedToday.isEmpty {
                    Text("今天还没有完成任务")
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                } else {
                    ForEach(completedToday, id: \.task.id) { entry in
                        Label(entry.task.title, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textPrimary)
                            .lineLimit(2)
                    }
                }
                Divider()
                Text("今日重点")
                    .font(.system(size: 12, weight: .semibold))
                Text(store.dailySummary(on: .now)?.content.nonEmpty ?? "每日回顾完成后，重点内容会整理在这里。")
                    .font(.system(size: 11))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var completedToday: [(goal: WeeklyGoal, task: WeekTask)] {
        store.todayTasks.filter { $0.task.status == .completed }
    }

    private var focusSessionsToday: Int {
        store.focusRecords
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.sessionCount }
    }

    private var timedTasksToday: Int {
        store.todayTasks.filter { $0.task.actualMinutes > 0 }.count
    }

    private var archiveMetricStrip: some View {
        HStack(spacing: 6) {
            archiveMetric(value: "\(completedToday.count)", label: "完成")
            archiveMetric(value: "\(focusSessionsToday)", label: "专注")
            archiveMetric(value: "\(timedTasksToday)", label: "计时")
        }
    }

    private func archiveMetric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 9.5)).foregroundStyle(WeekflowPalette.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 7))
    }
}

struct AssistantTaskCardList: View {
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    @Bindable var store: WeekflowStore
    let emptyTitle: String
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void

    var body: some View {
        if entries.isEmpty {
            Text(emptyTitle)
                .font(.system(size: 11.5))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            ScrollView {
                LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                    ForEach(entries, id: \.task.id) { entry in
                        SunsamaTaskCard(
                            entry: entry,
                            store: store,
                            dragSourceDate: entry.task.plannedDate,
                            inferredStartTime: nil,
                            compactHeight: WeekflowLayout.homeTaskCardHeight,
                            openTask: { openTask(entry) }
                        )
                    }
                }
            }
            .scrollIndicators(.visible)
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
