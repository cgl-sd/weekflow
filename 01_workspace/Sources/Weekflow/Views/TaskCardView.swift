import SwiftUI

struct SunsamaTaskCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    @Bindable var store: WeekflowStore
    let dragSourceDate: Date?
    let inferredStartTime: Date?
    let compactHeight: CGFloat?
    let showsDateControl: Bool
    let timerExpansionRequested: () -> Void
    let expansionHeightChanged: (CGFloat) -> Void
    let dragStarted: (TaskDragToken) -> Void
    let openTask: () -> Void
    let auxiliaryActionSymbol: String?
    let auxiliaryActionHelp: String
    let auxiliaryAction: (() -> Void)?
    @State private var showsChannelPopover = false
    private let externalChannelMenu: Binding<Bool>?
    @State private var showsDatePopover = false
    private let externalDateMenu: Binding<Bool>?
    @State private var showsStartTimePopover = false
    private let externalStartTimeMenu: Binding<Bool>?
    @State private var isTimerExpanded = false
    @State private var isTimerPanelContentVisible = false
    @State private var timerPanelTransitionGeneration = 0
    @Binding private var showsEstimatedDurationPopover: Bool
    @State private var showsPriorityPopover = false
    private let externalPriorityMenu: Binding<Bool>?
    @State private var locksPersistentPriorityBadge = false
    @State private var isHovering = false
    @State private var isStartTimeHovering = false
    @State private var isChannelHovering = false
    @State private var showsContextPopover = false
    @State private var cardWidth = WeekflowLayout.taskDatePopoverWidth
    @AppStorage(TaskCardTypographyPreferences.taskTextSizeKey)
    private var storedTaskTextSize = TaskCardTypographyPreferences.defaultTaskTextSize
    @AppStorage(TaskCardTypographyPreferences.metadataSizeKey)
    private var storedMetadataSize = TaskCardTypographyPreferences.defaultMetadataSize

    init(
        entry: (goal: WeeklyGoal, task: WeekTask),
        store: WeekflowStore,
        dragSourceDate: Date? = nil,
        inferredStartTime: Date? = nil,
        compactHeight: CGFloat? = nil,
        showsDateControl: Bool = true,
        showsEstimatedDurationMenu: Binding<Bool> = .constant(false),
        showsStartTimeMenu: Binding<Bool>? = nil,
        showsDateMenu: Binding<Bool>? = nil,
        showsChannelMenu: Binding<Bool>? = nil,
        showsPriorityMenu: Binding<Bool>? = nil,
        initiallyExpandedTimer: Bool = false,
        initiallyHovering: Bool = false,
        auxiliaryActionSymbol: String? = nil,
        auxiliaryActionHelp: String = "",
        auxiliaryAction: (() -> Void)? = nil,
        timerExpansionRequested: @escaping () -> Void = {},
        expansionHeightChanged: @escaping (CGFloat) -> Void = { _ in },
        dragStarted: @escaping (TaskDragToken) -> Void = { _ in },
        openTask: @escaping () -> Void = {}
    ) {
        self.entry = entry
        self.store = store
        self.dragSourceDate = dragSourceDate
        self.inferredStartTime = inferredStartTime
        self.compactHeight = compactHeight
        self.showsDateControl = showsDateControl
        _showsEstimatedDurationPopover = showsEstimatedDurationMenu
        externalStartTimeMenu = showsStartTimeMenu
        externalDateMenu = showsDateMenu
        externalChannelMenu = showsChannelMenu
        externalPriorityMenu = showsPriorityMenu
        _isTimerExpanded = State(initialValue: initiallyExpandedTimer)
        _isTimerPanelContentVisible = State(initialValue: initiallyExpandedTimer)
        _isHovering = State(initialValue: initiallyHovering)
        self.auxiliaryActionSymbol = auxiliaryActionSymbol
        self.auxiliaryActionHelp = auxiliaryActionHelp
        self.auxiliaryAction = auxiliaryAction
        self.timerExpansionRequested = timerExpansionRequested
        self.expansionHeightChanged = expansionHeightChanged
        self.dragStarted = dragStarted
        self.openTask = openTask
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    startTimeButton
                    Spacer(minLength: 4)
                    durationButton
                }

                taskTitle
                    .padding(.top, WeekflowLayout.taskCardTitleTopPadding)

                if !displayedSubtasks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(displayedSubtasks) { subtask in
                            HStack(spacing: 6) {
                                TaskCardCompletionButton(
                                    isCompleted: subtask.completed,
                                    inactiveTint: WeekflowPalette.iconDefault,
                                    help: subtask.completed ? "标记子任务为未完成" : "标记子任务为已完成"
                                ) {
                                    store.toggleSubtask(
                                        goalID: entry.goal.id,
                                        taskID: entry.task.id,
                                        subtaskID: subtask.id
                                    )
                                }

                                Text(subtask.title)
                                    .font(.system(
                                        size: WeekflowLayout.taskCardSubtaskFontSize,
                                        weight: .regular
                                    ))
                                    .foregroundStyle(
                                        subtask.completed
                                            ? WeekflowPalette.textMuted
                                            : WeekflowPalette.textSecondary
                                    )
                                    .strikethrough(subtask.completed, color: WeekflowPalette.textMuted)
                                    .lineLimit(1)

                                Spacer(minLength: 0)
                            }
                            .frame(height: WeekflowLayout.taskCardSubtaskRowHeight)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.top, WeekflowLayout.taskCardTitleTopPadding)
                }

                HStack(spacing: WeekflowLayout.taskCardIconSpacing) {
                    TaskCardCompletionButton(
                        isCompleted: entry.task.status == .completed,
                        inactiveTint: showsExpandedCardControls
                            ? WeekflowPalette.textMuted
                            : WeekflowPalette.iconDefault,
                        help: entry.task.status == .completed ? "标记为未完成" : "标记为已完成"
                    ) {
                        store.toggleTask(goalID: entry.goal.id, taskID: entry.task.id)
                    }
                    if showsExpandedCardControls {
                        if showsDateControl {
                            calendarMenu
                        }
                        TaskCardIconButton(
                            symbol: "timer",
                            tint: WeekflowPalette.textMuted,
                            help: "打开计时",
                            presentationAnchor: .timerButton(entry.task.id)
                        ) {
                            toggleTimerPanel()
                        }
                    }
                    if showsPersistentPriority || showsExpandedCardControls {
                        priorityMenu
                    }
                    if showsExpandedCardControls,
                       let auxiliaryActionSymbol,
                       let auxiliaryAction {
                        TaskCardIconButton(
                            symbol: auxiliaryActionSymbol,
                            tint: WeekflowPalette.textMuted,
                            help: auxiliaryActionHelp,
                            action: auxiliaryAction
                        )
                    }
                    Spacer(minLength: 4)
                    WeekflowButton {
                        presentPopover(.channel)
                    } label: {
                        Group {
                            if let channel = store.channel(for: entry.task.channelID) {
                                HStack(spacing: 3) {
                                    Image(systemName: channel.resolvedIconName)
                                    Text(channel.title)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                        .allowsTightening(true)
                                }
                                .foregroundStyle(channel.color.opacity(isChannelHovering ? 1 : 0.82))
                            } else {
                                Text(entry.goal.title)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                    .allowsTightening(true)
                                    .foregroundStyle(isChannelHovering ? WeekflowPalette.textPrimary : WeekflowPalette.textMuted)
                            }
                        }
                        .font(.system(
                            size: metadataSize,
                            weight: isChannelHovering ? .medium : .regular
                        ))
                        .anchorPreference(
                            key: TaskDurationMenuAnchorPreferenceKey.self,
                            value: .bounds
                        ) { anchor in
                            [.channelButton(entry.task.id): anchor]
                        }
                        .popover(isPresented: $showsChannelPopover, arrowEdge: .bottom) {
                            TaskChannelPopover(
                                channels: store.activeChannels,
                                selectedChannelID: entry.task.channelID,
                                select: { channelID in
                                    setChannel(channelID)
                                },
                                manage: {
                                    showsChannelPopover = false
                                    DispatchQueue.main.async {
                                        CommandRouter.shared.send(.openChannelSettings)
                                    }
                                }
                            )
                        }
                        .frame(maxWidth: WeekflowLayout.taskCardChannelMaximumWidth, alignment: .trailing)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 4)
                        .frame(minHeight: WeekflowLayout.taskCardIconHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .layoutPriority(1)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isChannelHovering = hovering
                        }
                    }
                    .pointingHandCursor()
                }
                .padding(.top, WeekflowLayout.taskCardFooterTopPadding)
                .padding(.leading, WeekflowLayout.taskCardFooterLeadingInset)
            }
            .padding(.horizontal, WeekflowLayout.taskCardHorizontalPadding)
            .padding(.vertical, WeekflowLayout.taskCardVerticalPadding)

            if isTimerExpanded {
                Divider()
                    .padding(.horizontal, WeekflowLayout.taskCardHorizontalPadding)
                    .anchorPreference(
                        key: TaskDurationMenuAnchorPreferenceKey.self,
                        value: .bounds
                    ) { anchor in
                        [.timerDivider(entry.task.id): anchor]
                    }
                    .opacity(isTimerPanelContentVisible ? 1 : 0)
                TaskTimerInlinePanel(
                    store: store,
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    estimatedMinutes: entry.task.estimatedMinutes,
                    showsEstimatedDurationPopover: $showsEstimatedDurationPopover,
                    toggleEstimatedDurationPopover: toggleEstimatedDurationPopover
                )
                .padding(.horizontal, WeekflowLayout.taskTimerPanelHorizontalPadding)
                .padding(.vertical, WeekflowLayout.taskTimerPanelVerticalPadding)
                .opacity(isTimerPanelContentVisible ? 1 : 0)
                .offset(y: isTimerPanelContentVisible ? 0 : -4)
            }
        }
        .overlayPreferenceValue(TaskDurationMenuAnchorPreferenceKey.self) { anchors in
            if isTimerExpanded && isTimerPanelContentVisible {
                TaskTimerDividerPointerOverlay(
                    taskID: entry.task.id,
                    anchors: anchors
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            maxWidth: .infinity,
            minHeight: WeekflowLayout.taskCardMinimumHeight,
            alignment: .leading
        )
        .frame(height: resolvedCardHeight, alignment: .leading)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: TaskCardWidthPreferenceKey.self, value: geometry.size.width)
            }
        }
        .boxHoverChrome(
            isHovering: isHovering
                || isTimerExpanded
                || showsEstimatedDurationPopover
                || isDateMenuPresented
                || isChannelMenuPresented
                || isPriorityMenuPresented,
            cornerRadius: 9
        )
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 9))
        .pointingHandCursor(coversDescendants: true)
        .overlay {
            if isTimerExpanded && !showsEstimatedDurationPopover {
                GeometryReader { geometry in
                    WindowOutsideClickMonitor(
                        protectedRect: CGRect(origin: .zero, size: geometry.size),
                        action: dismissTimerPanel
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .onDrag {
            let token = TaskDragToken(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                sourceDate: dragSourceDate
            )
            dragStarted(token)
            return NSItemProvider(
                object: token.value as NSString
            )
        } preview: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(startTimeText)
                        .font(.system(size: metadataSize).monospacedDigit())
                    Spacer()
                    Text(estimatedTimeText)
                        .font(.system(size: metadataSize).monospacedDigit())
                }
                .foregroundStyle(WeekflowPalette.secondaryText)
                Text(entry.task.title)
                    .font(.system(size: taskTextSize, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack {
                    Image(systemName: entry.task.status == .completed ? "checkmark.circle.fill" : "checkmark.circle")
                    Spacer()
                    Text(store.channel(for: entry.task.channelID)?.title ?? entry.goal.title)
                        .lineLimit(1)
                }
                .font(.system(size: metadataSize))
                .foregroundStyle(WeekflowPalette.textMuted)
            }
            .padding(.horizontal, WeekflowLayout.taskCardHorizontalPadding)
            .padding(.vertical, WeekflowLayout.taskCardVerticalPadding)
            .frame(width: cardWidth, height: resolvedCardHeight, alignment: .topLeading)
            .background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong, lineWidth: 1)
            }
        }
        .onTapGesture {
            store.highlightedTask = TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
            openTask()
        }
        .background {
            TaskCardContextMenuAnchor(
                isPresented: $showsContextPopover,
                menuHeight: 278,
                onOpen: {
                selectForCommand()
                }
            ) {
                TaskCardContextPopover(
                    hasStartTime: entry.task.startTime != nil,
                    addToCalendar: {
                        store.commitTaskToCalendar(goalID: entry.goal.id, taskID: entry.task.id)
                    },
                    addToCalendarAt: commitToCalendar,
                    clearFromCalendar: {
                        store.setTaskCalendarPlacement(
                            goalID: entry.goal.id,
                            taskID: entry.task.id,
                            placement: .suggested
                        )
                    },
                    moveToBacklog: {
                        store.moveTaskToBacklog(goalID: entry.goal.id, taskID: entry.task.id, atTop: false)
                    },
                    moveToTopOfBacklog: {
                        store.moveTaskToBacklog(goalID: entry.goal.id, taskID: entry.task.id, atTop: true)
                    },
                    copy: {
                        selectForCommand()
                        store.copyHighlightedTask()
                        showsContextPopover = false
                    },
                    cut: {
                        selectForCommand()
                        store.copyHighlightedTask(cutsSource: true)
                        showsContextPopover = false
                    },
                    paste: {
                        _ = store.pasteTaskClipboard(
                            on: entry.task.plannedDate ?? dragSourceDate ?? store.activeDay,
                            after: TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
                        )
                        showsContextPopover = false
                    },
                    canPaste: store.hasTaskClipboard,
                    delete: {
                        store.deleteTask(goalID: entry.goal.id, taskID: entry.task.id)
                        showsContextPopover = false
                    }
                )
            }
        }
        .background {
            TaskCardKeyboardShortcutAnchor(
                isActive: isHovering || showsContextPopover,
                copy: {
                    selectForCommand()
                    store.copyHighlightedTask()
                    showsContextPopover = false
                },
                cut: {
                    selectForCommand()
                    store.copyHighlightedTask(cutsSource: true)
                    showsContextPopover = false
                },
                paste: {
                    selectForCommand()
                    _ = store.pasteTaskClipboard(
                        on: entry.task.plannedDate ?? dragSourceDate ?? store.activeDay,
                        after: TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
                    )
                    showsContextPopover = false
                },
                delete: {
                    selectForCommand()
                    store.deleteTask(goalID: entry.goal.id, taskID: entry.task.id)
                    showsContextPopover = false
                }
            )
        }
        .onHover { hovering in
            if hovering {
                selectForCommand()
            }
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onPreferenceChange(TaskCardWidthPreferenceKey.self) { width in
            guard width > 0 else { return }
            cardWidth = width
        }
        .onChange(of: isTimerExpanded) { _, _ in
            reportExpansionHeight()
        }
        .onChange(of: displayedSubtasks.count) { _, _ in
            reportExpansionHeight()
        }
        .onAppear {
            reportExpansionHeight()
        }
        .onChange(of: isPriorityMenuPresented) { _, isPresented in
            if !isPresented {
                locksPersistentPriorityBadge = false
            }
        }
        .onDisappear {
            expansionHeightChanged(0)
        }
        .opacity(entry.task.status == .completed ? 0.55 : 1)
        .popover(
            isPresented: $showsDatePopover,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            TaskDatePopover(
                selectedDate: dragSourceDate ?? entry.task.plannedDate ?? .now,
                availableWidth: cardWidth,
                moveByDays: { offset in
                    moveTask(by: offset)
                },
                moveToDate: { date in
                    moveTask(to: date)
                }
            )
        }
    }

    private var taskTitle: some View {
        Text(entry.task.title)
            .font(.system(size: taskTextSize, weight: .regular))
            .foregroundStyle(WeekflowPalette.textPrimary)
            .lineLimit(2)
            .truncationMode(.tail)
            .strikethrough(entry.task.status == .completed)
    }

    private var durationButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            WeekflowButton {
                toggleTimerPanel()
            } label: {
                Text(timerText(at: context.date))
                    .font(.system(size: metadataSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .boxHoverChrome(
                        isHovering: false,
                        cornerRadius: 5,
                        fill: WeekflowPalette.surfaceSelected.opacity(0.72)
                    )
                    .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .anchorPreference(
                key: TaskDurationMenuAnchorPreferenceKey.self,
                value: .bounds
            ) { anchor in
                [.durationButton(entry.task.id): anchor]
            }
            .help("打开计时")
                .task(id: timerMinuteBucket(at: context.date)) {
                    store.synchronizeActiveTaskTimer(at: context.date)
                }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(width: WeekflowLayout.taskCardTimerControlWidth, alignment: .trailing)
        .layoutPriority(1)
    }

    private var startTimeButton: some View {
        WeekflowButton {
            toggleStartTimePopover()
        } label: {
            Text(startTimeText)
                .font(.system(size: metadataSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(
                    entry.task.calendarPlacement == .committed
                        ? Color.white
                        : (isStartTimeHovering
                            ? WeekflowPalette.textPrimary
                            : WeekflowPalette.textSecondary.opacity(isStartTimeInferred ? 0.88 : 1))
                )
                .padding(.horizontal, entry.task.calendarPlacement == .committed ? 6 : 2)
                .frame(height: 22)
                .background {
                    if entry.task.calendarPlacement == .committed {
                        WeekflowRoundedRectangle(cornerRadius: 4)
                            .fill(store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault)
                    }
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isStartTimeHovering = hovering
            }
        }
        .help(isStartTimeInferred ? "根据上一项预计时长推算，点击设置" : "设置开始时间")
        .anchorPreference(
            key: TaskDurationMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [.startTimeButton(entry.task.id): anchor]
        }
        .popover(isPresented: fallbackStartTimePopoverBinding) {
            ScrollClockTimePopover(
                selection: entry.task.startTime,
                anchorDate: entry.task.plannedDate ?? dragSourceDate ?? .now
            ) { date in
                setStartTime(date)
            }
        }
    }

    private var startTimeText: String {
        guard let startTime = displayedStartTime else { return TaskTimeDisplay.unsetStart }
        return startTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private var estimatedTimeText: String {
        TaskTimeDisplay.estimated(minutes: entry.task.estimatedMinutes)
    }

    private func commitToCalendar(at minute: Int) {
        let day = SystemBusinessCalendar.current.calendar.startOfDay(for: entry.task.plannedDate ?? dragSourceDate ?? .now)
        let start = SystemBusinessCalendar.current.calendar.date(byAdding: .minute, value: minute, to: day) ?? day
        store.commitTaskToCalendar(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            startTime: start
        )
    }

    private func selectForCommand() {
        store.highlightedTask = TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
        store.activeDay = entry.task.plannedDate ?? dragSourceDate ?? .now
    }

    private var taskTextSize: CGFloat {
        TaskCardTypographyPreferences.taskTextSize(from: storedTaskTextSize)
    }

    private var metadataSize: CGFloat {
        TaskCardTypographyPreferences.metadataSize(from: storedMetadataSize)
    }

    private var displayedStartTime: Date? {
        entry.task.startTime ?? inferredStartTime
    }

    private var isStartTimeInferred: Bool {
        entry.task.startTime == nil && inferredStartTime != nil
    }

    private var showsPersistentPriority: Bool {
        entry.task.priority.showsOnTaskCard
    }

    private var showsExpandedCardControls: Bool {
        showsCardControls && !locksPersistentPriorityBadge
    }

    private var displayedSubtasks: [TaskSubtask] {
        entry.task.subtasks.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var calendarMenu: some View {
        TaskCardIconButton(
            symbol: "calendar",
            tint: WeekflowPalette.textMuted,
            help: "调整任务日期",
            presentationAnchor: .dateButton(entry.task.id)
        ) {
            presentPopover(.date)
        }
    }

    private var priorityMenu: some View {
        TaskCardPriorityButton(
            priority: entry.task.priority,
            showsBadge: showsPersistentPriority
                && (!showsCardControls || locksPersistentPriorityBadge),
            help: "设置优先级",
            isPopoverPresented: $showsPriorityPopover,
            presentationAnchor: .priorityButton(entry.task.id),
            selectPriority: { priority in
                setPriority(priority)
            }
        ) {
            let shouldLockBadge = TaskCardPresentationRules.shouldLockPersistentPriorityBadge(
                menuIsCurrentlyPresented: isPriorityMenuPresented,
                priorityShowsPersistently: showsPersistentPriority,
                expandedControlsAreVisible: showsCardControls
            )
            presentPopover(.priority)
            locksPersistentPriorityBadge = isPriorityMenuPresented && shouldLockBadge
        }
    }

    private var isTimerRunning: Bool {
        store.isTaskTimerRunning(goalID: entry.goal.id, taskID: entry.task.id)
    }

    private func timerText(at date: Date) -> String {
        let actual = store.liveTaskActualMinutes(goalID: entry.goal.id, taskID: entry.task.id, at: date)
        guard actual > 0 else { return estimatedTimeText }
        return "\(actual.hourMinuteClockText) / \(estimatedTimeText)"
    }

    private func timerMinuteBucket(at date: Date) -> Int {
        guard let startedAt = store.taskTimerStartedAt(goalID: entry.goal.id, taskID: entry.task.id) else { return -1 }
        return max(Int(date.timeIntervalSince(startedAt)) / 60, 0)
    }

    private var hasActivePopover: Bool {
        isChannelMenuPresented
            || isDateMenuPresented
            || isStartTimeMenuPresented
            || isPriorityMenuPresented
            || isTimerExpanded
    }

    /// Keep the footer controls and their popover anchors stable while the
    /// pointer moves from a card into an open menu.
    private var showsCardControls: Bool {
        isHovering || hasActivePopover
    }

    private enum CardPopover {
        case channel, date, priority
    }

    private func presentPopover(_ popover: CardPopover) {
        let shouldPresent: Bool
        switch popover {
        case .channel:
            shouldPresent = TaskCardPresentationRules.shouldPresentAfterToggle(
                isCurrentlyPresented: isChannelMenuPresented
            )
        case .date:
            shouldPresent = TaskCardPresentationRules.shouldPresentAfterToggle(
                isCurrentlyPresented: isDateMenuPresented
            )
        case .priority:
            shouldPresent = TaskCardPresentationRules.shouldPresentAfterToggle(
                isCurrentlyPresented: isPriorityMenuPresented
            )
        }

        dismissCardPresentations()
        guard shouldPresent else { return }
        switch popover {
        case .channel:
            setChannelMenuPresented(true)
        case .date:
            setDateMenuPresented(true)
        case .priority:
            setPriorityMenuPresented(true)
        }
    }

    private func toggleTimerPanel() {
        let shouldPresent = TaskCardPresentationRules.shouldPresentDurationAfterToggle(
            isTimerExpanded: isTimerExpanded,
            isMenuPresented: showsEstimatedDurationPopover
        )
        if !shouldPresent {
            dismissTimerPanel()
            return
        }

        dismissCardPopovers()
        timerPanelTransitionGeneration += 1
        let transitionGeneration = timerPanelTransitionGeneration
        // The scroll thumb is derived from the document extent. Commit the
        // fixed timer-panel height in one non-animated layout pass so bottom
        // cards cannot make the thumb resize while it is also scrolling.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isTimerPanelContentVisible = false
            isTimerExpanded = true
        }
        timerExpansionRequested()
        DispatchQueue.main.async {
            guard transitionGeneration == timerPanelTransitionGeneration,
                  isTimerExpanded else { return }
            withAnimation(
                .easeOut(duration: WeekflowLayout.taskDurationPresentationAnimationDuration)
            ) {
                isTimerPanelContentVisible = true
            }
        }
    }

    private func toggleEstimatedDurationPopover() {
        withAnimation(
            .easeOut(duration: WeekflowLayout.taskDurationPresentationAnimationDuration)
        ) {
            showsEstimatedDurationPopover.toggle()
        }
    }

    private var isDateMenuPresented: Bool {
        externalDateMenu?.wrappedValue ?? showsDatePopover
    }

    private var isChannelMenuPresented: Bool {
        externalChannelMenu?.wrappedValue ?? showsChannelPopover
    }

    private func setChannelMenuPresented(_ isPresented: Bool) {
        if let externalChannelMenu {
            externalChannelMenu.wrappedValue = isPresented
        } else {
            showsChannelPopover = isPresented
        }
    }

    private var isPriorityMenuPresented: Bool {
        externalPriorityMenu?.wrappedValue ?? showsPriorityPopover
    }

    private func setPriorityMenuPresented(_ isPresented: Bool) {
        if let externalPriorityMenu {
            externalPriorityMenu.wrappedValue = isPresented
        } else {
            showsPriorityPopover = isPresented
        }
    }

    private func setDateMenuPresented(_ isPresented: Bool) {
        if let externalDateMenu {
            externalDateMenu.wrappedValue = isPresented
        } else {
            showsDatePopover = isPresented
        }
    }

    private func toggleStartTimePopover() {
        let shouldPresent = TaskCardPresentationRules.shouldPresentAfterToggle(
            isCurrentlyPresented: isStartTimeMenuPresented
        )
        dismissCardPresentations()
        if shouldPresent {
            setStartTimeMenuPresented(true)
        }
    }

    private var isStartTimeMenuPresented: Bool {
        externalStartTimeMenu?.wrappedValue ?? showsStartTimePopover
    }

    private func setStartTimeMenuPresented(_ isPresented: Bool) {
        if let externalStartTimeMenu {
            externalStartTimeMenu.wrappedValue = isPresented
        } else {
            showsStartTimePopover = isPresented
        }
    }

    private var fallbackStartTimePopoverBinding: Binding<Bool> {
        Binding(
            get: { externalStartTimeMenu == nil && showsStartTimePopover },
            set: { showsStartTimePopover = $0 }
        )
    }

    private func dismissCardPresentations() {
        locksPersistentPriorityBadge = false
        dismissCardPopovers()
        dismissTimerPanel()
    }

    private func dismissCardPopovers() {
        setChannelMenuPresented(false)
        setDateMenuPresented(false)
        setStartTimeMenuPresented(false)
        setPriorityMenuPresented(false)
    }

    private func dismissTimerPanel() {
        timerPanelTransitionGeneration += 1
        let transitionGeneration = timerPanelTransitionGeneration
        withAnimation(
            .easeOut(duration: WeekflowLayout.taskDurationPresentationAnimationDuration)
        ) {
            showsEstimatedDurationPopover = false
            isTimerPanelContentVisible = false
        }
        guard isTimerExpanded else { return }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + WeekflowLayout.taskDurationPresentationAnimationDuration
        ) {
            guard transitionGeneration == timerPanelTransitionGeneration,
                  !isTimerPanelContentVisible else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isTimerExpanded = false
            }
        }
    }

    private var resolvedCardHeight: CGFloat? {
        guard let compactHeight else { return nil }
        return compactHeight
            + subtaskAdditionalHeight
            + (isTimerExpanded ? WeekflowLayout.taskTimerExpandedAdditionalHeight : 0)
    }

    private func moveTask(by dayOffset: Int) {
        let baseDate = dragSourceDate ?? entry.task.plannedDate ?? .now
        let targetDate = SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: dayOffset, to: baseDate)
        guard let targetDate else { return }
        moveTask(to: targetDate)
    }

    private func moveTask(to date: Date) {
        store.relocateTask(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            from: dragSourceDate,
            to: date
        )
    }

    private func setChannel(_ channelID: String?) {
        var task = entry.task
        task.channelID = channelID
        store.updateTask(task, goalID: entry.goal.id)
    }

    private func setPriority(_ priority: TaskPriority) {
        store.setTaskPriority(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            priority: priority,
            on: dragSourceDate ?? entry.task.plannedDate ?? .now
        )
    }

    private func setStartTime(_ startTime: Date?) {
        var task = entry.task
        task.startTime = startTime
        store.updateTask(task, goalID: entry.goal.id)
    }

    private func reportExpansionHeight() {
        expansionHeightChanged(
            subtaskAdditionalHeight
                + (isTimerExpanded ? WeekflowLayout.taskTimerExpandedAdditionalHeight : 0)
        )
    }

    private var subtaskAdditionalHeight: CGFloat {
        CGFloat(displayedSubtasks.count) * WeekflowLayout.taskCardSubtaskRowHeight
    }
}

