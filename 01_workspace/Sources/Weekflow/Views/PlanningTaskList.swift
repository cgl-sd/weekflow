import SwiftUI

struct PlanningTaskList: View {
    let title: String
    let date: Date
    @Bindable var store: WeekflowStore
    @Binding var draggedTaskToken: TaskDragToken?
    @Binding var newlyAssignedTaskID: UUID?
    let addTask: () -> Void
    @State private var isDropTarget = false
    @State private var taskRowFrames: [UUID: CGRect] = [:]
    @State private var poolDropPreview: PlanningPoolDropPreview?
    @State private var timerScrollRequest: VerticalScrollRequest?
    @State private var taskExpansionHeights: [UUID: CGFloat] = [:]
    @State private var expandedDurationTaskIDs: Set<UUID> = []
    @State private var reservedDurationMenuTaskID: UUID?
    @State private var pendingDurationMenuScrollTaskID: UUID?
    @State private var presentedStartTimeTaskIDs: Set<UUID> = []
    @State private var pendingStartTimeMenuAdjustmentTaskID: UUID?
    @State private var presentedChannelTaskIDs: Set<UUID> = []
    @State private var pendingChannelMenuAdjustmentTaskID: UUID?
    @State private var presentedPriorityTaskIDs: Set<UUID> = []
    @State private var pendingPriorityMenuAdjustmentTaskID: UUID?
    @State private var pendingTimerPanelAdjustmentTaskID: UUID?
    @State private var taskRowFrameCache = HomeTaskRowFrameCache()
    @State private var showsSortMenu = false
    @State private var isSortButtonHovering = false
    @State private var verticalScrollerTrackWidth = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: .legacy
    )

    private var dragCoordinateSpace: String {
        "daily-planning-drop-\(SystemBusinessCalendar.current.day(containing: date).persistenceKey)"
    }

    private var taskScrollCoordinateSpace: String {
        "daily-planning-scroll-\(SystemBusinessCalendar.current.day(containing: date).persistenceKey)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
            DailyWorkspaceColumnHeader(
                title: title,
                detail: date.dayLabel,
                badge: nil
            ) {
                WeekflowButton {
                    toggleSortMenu()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(
                            showsSortMenu || isSortButtonHovering
                                ? WeekflowPalette.surfaceHover
                                : .clear,
                            in: WeekflowRoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .foregroundStyle(WeekflowPalette.iconDefault)
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 6))
                .anchorPreference(
                    key: PlanningSortMenuAnchorPreferenceKey.self,
                    value: .bounds,
                    transform: { $0 }
                )
                .onHover { isSortButtonHovering = $0 }
                .help("任务排序")
            }
            GeometryReader { proxy in
                let cardContentWidth = WeekflowLayout.homeCardContentWidth(for: proxy.size.width)
                let taskScrollViewportWidth = WeekflowLayout.homeTaskScrollViewportWidth(
                    for: proxy.size.width
                )
                let displayedEntries = planningDisplayedEntries(
                    store: store,
                    date: date,
                    preview: poolDropPreview
                )
                VStack(alignment: .leading, spacing: 10) {
                    HomeAddTaskButton(action: addTask)
                        .frame(width: cardContentWidth, alignment: .leading)
                    GeometryReader { taskArea in
                        let expandedAdditionalHeight = taskExpansionHeights.values.reduce(0, +)
                            + durationMenuOverflowHeight(in: displayedEntries)
                            + startTimeMenuOverflowHeight(in: displayedEntries)
                            + channelMenuOverflowHeight(in: displayedEntries)
                            + priorityMenuOverflowHeight(in: displayedEntries)
                            + timerPanelBottomReserve
                        let showsVerticalScroller = WeekflowLayout.homeShowsVerticalScroller(
                            taskCount: displayedEntries.count,
                            expandedAdditionalHeight: expandedAdditionalHeight,
                            viewportHeight: taskArea.size.height
                        )
                        let taskCardWidth = WeekflowLayout.homeTaskCardWidth(
                            for: proxy.size.width,
                            showsVerticalScroller: showsVerticalScroller
                        )

                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical) {
                                LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                                    ForEach(displayedEntries, id: \.task.id) { entry in
                                        SunsamaTaskCard(
                                            entry: entry,
                                            store: store,
                                            dragSourceDate: date,
                                            compactHeight: WeekflowLayout.homeTaskCardHeight,
                                            showsDateControl: false,
                                            showsEstimatedDurationMenu: Binding(
                                                get: { expandedDurationTaskIDs.contains(entry.task.id) },
                                                set: {
                                                    setDurationMenuPresented(
                                                        $0,
                                                        taskID: entry.task.id,
                                                        viewportHeight: taskArea.size.height
                                                    )
                                                }
                                            ),
                                            showsStartTimeMenu: Binding(
                                                get: { presentedStartTimeTaskIDs.contains(entry.task.id) },
                                                set: { setStartTimeMenuPresented($0, taskID: entry.task.id) }
                                            ),
                                            showsChannelMenu: Binding(
                                                get: { presentedChannelTaskIDs.contains(entry.task.id) },
                                                set: { setChannelMenuPresented($0, taskID: entry.task.id) }
                                            ),
                                            showsPriorityMenu: Binding(
                                                get: { presentedPriorityTaskIDs.contains(entry.task.id) },
                                                set: { setPriorityMenuPresented($0, taskID: entry.task.id) }
                                            ),
                                            deleteAction: {
                                                store.removeTaskFromDailyPlanning(
                                                    goalID: entry.goal.id,
                                                    taskID: entry.task.id,
                                                    date: date
                                                )
                                            },
                                            timerExpansionRequested: {
                                                if let scrollDistance = timerPanelPresentationScrollDistance(
                                                    taskID: entry.task.id,
                                                    viewportHeight: taskArea.size.height
                                                ) {
                                                    pendingTimerPanelAdjustmentTaskID = nil
                                                    if scrollDistance > 0 {
                                                        requestVerticalScroll(by: scrollDistance)
                                                    }
                                                } else {
                                                    pendingTimerPanelAdjustmentTaskID = entry.task.id
                                                }
                                            },
                                            expansionHeightChanged: { height in
                                                if height > 0 {
                                                    let currentHeight = taskExpansionHeights[entry.task.id]
                                                    if currentHeight.map({ abs($0 - height) >= 0.5 }) ?? true {
                                                        taskExpansionHeights[entry.task.id] = height
                                                    }
                                                } else if taskExpansionHeights[entry.task.id] != nil {
                                                    taskExpansionHeights.removeValue(forKey: entry.task.id)
                                                }
                                            },
                                            dragStarted: { draggedTaskToken = $0 },
                                            openTask: {}
                                        )
                                        .id(entry.task.id)
                                        .background {
                                            GeometryReader { row in
                                                Color.clear
                                                    .preference(
                                                        key: PlanningDropRowFramePreferenceKey.self,
                                                        value: [
                                                            entry.task.id: row.frame(in: .named(dragCoordinateSpace))
                                                        ]
                                                    )
                                                    .preference(
                                                        key: HomeTaskRowFramePreferenceKey.self,
                                                        value: [
                                                            entry.task.id: row.frame(in: .named(taskScrollCoordinateSpace))
                                                        ]
                                                    )
                                            }
                                        }
                                        .transformAnchorPreference(
                                            key: TaskDurationMenuAnchorPreferenceKey.self,
                                            value: .bounds
                                        ) { anchors, anchor in
                                            anchors[.card(entry.task.id)] = anchor
                                        }
                                    }
                                }
                                .padding(
                                    .bottom,
                                    WeekflowLayout.homeTaskListBottomPadding
                                        + durationMenuOverflowHeight(in: displayedEntries)
                                        + startTimeMenuOverflowHeight(in: displayedEntries)
                                        + channelMenuOverflowHeight(in: displayedEntries)
                                        + priorityMenuOverflowHeight(in: displayedEntries)
                                        + timerPanelBottomReserve
                                )
                                .frame(width: taskCardWidth, alignment: .topLeading)
                                .frame(minHeight: 70, alignment: .topLeading)
                                .background(
                                    ZeroInsetVerticalScroller(
                                        isVisible: showsVerticalScroller,
                                        columnWidth: taskScrollViewportWidth,
                                        scrollRequest: timerScrollRequest,
                                        onTrackWidthChange: { measuredWidth in
                                            guard abs(verticalScrollerTrackWidth - measuredWidth) >= 0.5 else {
                                                return
                                            }
                                            verticalScrollerTrackWidth = measuredWidth
                                        }
                                    )
                                )
                                .contentShape(Rectangle())
                                .overlayPreferenceValue(TaskDurationMenuAnchorPreferenceKey.self) { anchors in
                                    GeometryReader { overlay in
                                        let contentFrame = overlay.frame(in: .named(taskScrollCoordinateSpace))
                                        let viewportBottom = -contentFrame.minY + taskArea.size.height
                                        ZStack(alignment: .topLeading) {
                                            if let taskID = expandedDurationTaskIDs.first,
                                               let cardAnchor = anchors[.card(taskID)],
                                               let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                                let displayedSubtaskCount = entry.task.subtasks.lazy.filter {
                                                    !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                }.count
                                                TaskCardDurationMenuOverlay(
                                                    entry: entry,
                                                    store: store,
                                                    cardFrame: overlay[cardAnchor],
                                                    durationButtonFrame: anchors[.durationButton(taskID)].map { overlay[$0] },
                                                    estimatedDurationButtonFrame: anchors[.estimatedDurationButton(taskID)].map { overlay[$0] },
                                                    cardWidth: taskCardWidth,
                                                    viewportBottom: viewportBottom,
                                                    minimumPresentationCardBottom: overlay[cardAnchor].minY
                                                        + WeekflowLayout.homeTaskCardHeight(
                                                            subtaskCount: displayedSubtaskCount,
                                                            timerExpanded: true
                                                        ),
                                                    dismiss: {
                                                        setDurationMenuPresented(
                                                            false,
                                                            taskID: taskID,
                                                            viewportHeight: taskArea.size.height
                                                        )
                                                    }
                                                )
                                            }

                                            if let taskID = pendingTimerPanelAdjustmentTaskID,
                                               let cardAnchor = anchors[.card(taskID)],
                                               expandedDurationTaskIDs.isEmpty,
                                               presentedStartTimeTaskIDs.isEmpty,
                                               presentedChannelTaskIDs.isEmpty,
                                               presentedPriorityTaskIDs.isEmpty {
                                                let cardBottom = overlay[cardAnchor].maxY
                                                    + WeekflowLayout.taskTimerExpandedAdditionalHeight
                                                Color.clear.preference(
                                                    key: TaskDurationMenuOverflowPreferenceKey.self,
                                                    value: WeekflowLayout.taskTimerPresentationScrollDistance(
                                                        cardBottom: cardBottom,
                                                        viewportBottom: viewportBottom
                                                    )
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(
                                width: taskScrollViewportWidth,
                                height: taskArea.size.height,
                                alignment: .topLeading
                            )
                            .coordinateSpace(name: taskScrollCoordinateSpace)
                            .scrollIndicators(.visible)
                            .contentShape(Rectangle())
                            .onChange(of: newlyAssignedTaskID) { _, taskID in
                                guard let taskID else { return }
                                DispatchQueue.main.async {
                                    withAnimation(.easeOut(duration: 0.22)) {
                                        scrollProxy.scrollTo(taskID, anchor: .bottom)
                                    }
                                    if newlyAssignedTaskID == taskID {
                                        newlyAssignedTaskID = nil
                                    }
                                }
                            }
                            .overlayPreferenceValue(TaskDurationMenuAnchorPreferenceKey.self) { anchors in
                                GeometryReader { overlay in
                                    if let taskID = presentedStartTimeTaskIDs.first,
                                       let cardAnchor = anchors[.card(taskID)],
                                       let controlAnchor = anchors[.startTimeButton(taskID)],
                                       let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                        TaskCardStartTimeMenuOverlay(
                                            entry: entry,
                                            store: store,
                                            anchorDate: date,
                                            cardFrame: overlay[cardAnchor],
                                            controlFrame: overlay[controlAnchor],
                                            viewportWidth: taskScrollViewportWidth,
                                            scrollerTrackWidth: verticalScrollerTrackWidth,
                                            viewportBottom: overlay.size.height,
                                            allowsUnset: false,
                                            dismiss: { setStartTimeMenuPresented(false, taskID: taskID) }
                                        )
                                    }

                                    if let taskID = presentedChannelTaskIDs.first,
                                       let cardAnchor = anchors[.card(taskID)],
                                       let controlAnchor = anchors[.channelButton(taskID)],
                                       let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                        TaskCardChannelMenuOverlay(
                                            entry: entry,
                                            store: store,
                                            cardFrame: overlay[cardAnchor],
                                            controlFrame: overlay[controlAnchor],
                                            viewportWidth: taskScrollViewportWidth,
                                            scrollerTrackWidth: verticalScrollerTrackWidth,
                                            viewportBottom: overlay.size.height,
                                            dismiss: { setChannelMenuPresented(false, taskID: taskID) }
                                        )
                                    }

                                    if let taskID = presentedPriorityTaskIDs.first,
                                       let cardAnchor = anchors[.card(taskID)],
                                       let controlAnchor = anchors[.priorityButton(taskID)],
                                       let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                        TaskCardPriorityMenuOverlay(
                                            entry: entry,
                                            store: store,
                                            anchorDate: date,
                                            cardFrame: overlay[cardAnchor],
                                            controlFrame: overlay[controlAnchor],
                                            viewportWidth: taskScrollViewportWidth,
                                            scrollerTrackWidth: verticalScrollerTrackWidth,
                                            viewportBottom: overlay.size.height,
                                            dismiss: { setPriorityMenuPresented(false, taskID: taskID) }
                                        )
                                    }
                                }
                            }
                            .onPreferenceChange(HomeTaskRowFramePreferenceKey.self) {
                                taskRowFrameCache.frames = $0
                            }
                            .onPreferenceChange(TaskDurationMenuOverflowPreferenceKey.self) { overflow in
                                guard let overflow else { return }
                                if let taskID = pendingDurationMenuScrollTaskID,
                                   expandedDurationTaskIDs.contains(taskID) {
                                    pendingDurationMenuScrollTaskID = nil
                                    guard overflow > 0 else { return }
                                    requestVerticalScroll(by: overflow)
                                    return
                                } else if let taskID = pendingStartTimeMenuAdjustmentTaskID,
                                          presentedStartTimeTaskIDs.contains(taskID) {
                                    pendingStartTimeMenuAdjustmentTaskID = nil
                                } else if let taskID = pendingChannelMenuAdjustmentTaskID,
                                          presentedChannelTaskIDs.contains(taskID) {
                                    pendingChannelMenuAdjustmentTaskID = nil
                                } else if let taskID = pendingPriorityMenuAdjustmentTaskID,
                                          presentedPriorityTaskIDs.contains(taskID) {
                                    pendingPriorityMenuAdjustmentTaskID = nil
                                } else if pendingTimerPanelAdjustmentTaskID != nil {
                                    pendingTimerPanelAdjustmentTaskID = nil
                                } else {
                                    return
                                }
                                guard overflow > 0 else { return }
                                requestVerticalScroll(by: overflow)
                            }
                        }
                        .zIndex(hasActivePrimaryMenu ? 1 : 0)
                    }
                }
            }
        }
        .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            isDropTarget ? WeekflowPalette.surfaceSelected.opacity(0.48) : .clear,
            in: WeekflowRoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .coordinateSpace(name: dragCoordinateSpace)
        .onPreferenceChange(PlanningDropRowFramePreferenceKey.self) {
            taskRowFrames = $0
        }
        .onDrop(
            of: [.utf8PlainText],
            delegate: PlanningColumnTaskDropDelegate(
                draggedTaskToken: $draggedTaskToken,
                date: date,
                rowFrames: taskRowFrames,
                store: store,
                isDropTarget: $isDropTarget,
                poolDropPreview: $poolDropPreview,
                taskAssigned: { newlyAssignedTaskID = $0 }
            )
        )
        .overlayPreferenceValue(PlanningSortMenuAnchorPreferenceKey.self) { anchor in
            GeometryReader { geometry in
                if showsSortMenu, let anchor {
                    PlanningSortMenuOverlay(
                        controlFrame: geometry[anchor],
                        containerWidth: geometry.size.width,
                        sortByPriority: {
                            store.sortTasksByPriority(on: date)
                        },
                        sortByStartTime: {
                            store.sortTasksByStartTime(on: date)
                        },
                        dismiss: dismissSortMenu
                    )
                }
            }
        }
        .zIndex(showsSortMenu ? 6 : 0)
        .animation(.easeOut(duration: 0.12), value: showsSortMenu)
    }

    private var hasActivePrimaryMenu: Bool {
        !expandedDurationTaskIDs.isEmpty
            || !presentedStartTimeTaskIDs.isEmpty
            || !presentedChannelTaskIDs.isEmpty
            || !presentedPriorityTaskIDs.isEmpty
    }

    private func toggleSortMenu() {
        let shouldPresent = !showsSortMenu
        dismissDurationMenu()
        dismissStartTimeMenu()
        dismissChannelMenu()
        dismissPriorityMenu()
        withAnimation(.easeOut(duration: 0.12)) {
            showsSortMenu = shouldPresent
        }
    }

    private func dismissSortMenu() {
        withAnimation(.easeOut(duration: 0.12)) {
            showsSortMenu = false
        }
    }

    private var timerPanelBottomReserve: CGFloat {
        guard expandedDurationTaskIDs.isEmpty,
              reservedDurationMenuTaskID == nil,
              presentedStartTimeTaskIDs.isEmpty,
              presentedChannelTaskIDs.isEmpty,
              presentedPriorityTaskIDs.isEmpty,
              !taskExpansionHeights.isEmpty else { return 0 }
        return WeekflowLayout.taskDurationMenuViewportBottomClearance
    }

    private func durationMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = reservedDurationMenuTaskID,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskDurationMenuOverflow(
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func startTimeMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = presentedStartTimeTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskStartTimeMenuHeight,
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func channelMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = presentedChannelTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskChannelPopoverHeight(channelCount: store.activeChannels.count),
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func priorityMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = presentedPriorityTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskPriorityPopoverHeight,
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func setDurationMenuPresented(
        _ isPresented: Bool,
        taskID: UUID,
        viewportHeight: CGFloat
    ) {
        if isPresented {
            dismissSortMenu()
            dismissStartTimeMenu()
            dismissChannelMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            let scrollDistance = durationMenuPresentationScrollDistance(
                taskID: taskID,
                viewportHeight: viewportHeight
            )
            pendingDurationMenuScrollTaskID = scrollDistance == nil ? taskID : nil
            reserveDurationMenu(taskID: taskID, scrollDistance: scrollDistance)
            withAnimation(
                .easeOut(duration: WeekflowLayout.taskDurationPresentationAnimationDuration)
            ) {
                expandedDurationTaskIDs = [taskID]
            }
        } else {
            if pendingDurationMenuScrollTaskID == taskID {
                pendingDurationMenuScrollTaskID = nil
            }
            withAnimation(
                .easeOut(duration: WeekflowLayout.taskDurationPresentationAnimationDuration)
            ) {
                _ = expandedDurationTaskIDs.remove(taskID)
            }
            if reservedDurationMenuTaskID == taskID {
                clearDurationMenuReserve()
            }
        }
    }

    private func setStartTimeMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissSortMenu()
            dismissDurationMenu()
            dismissChannelMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedStartTimeTaskIDs = [taskID]
            pendingStartTimeMenuAdjustmentTaskID = taskID
        } else {
            dismissStartTimeMenu(ifPresentedTaskID: taskID)
        }
    }

    private func setChannelMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissSortMenu()
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedChannelTaskIDs = [taskID]
            pendingChannelMenuAdjustmentTaskID = taskID
        } else {
            dismissChannelMenu(ifPresentedTaskID: taskID)
        }
    }

    private func setPriorityMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissSortMenu()
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissChannelMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedPriorityTaskIDs = [taskID]
            pendingPriorityMenuAdjustmentTaskID = taskID
        } else {
            dismissPriorityMenu(ifPresentedTaskID: taskID)
        }
    }

    private func dismissStartTimeMenu(ifPresentedTaskID taskID: UUID? = nil) {
        if let taskID {
            presentedStartTimeTaskIDs.remove(taskID)
            if pendingStartTimeMenuAdjustmentTaskID == taskID {
                pendingStartTimeMenuAdjustmentTaskID = nil
            }
        } else {
            presentedStartTimeTaskIDs.removeAll()
            pendingStartTimeMenuAdjustmentTaskID = nil
        }
    }

    private func dismissDurationMenu(ifPresentedTaskID taskID: UUID? = nil) {
        if let taskID {
            if pendingDurationMenuScrollTaskID == taskID {
                pendingDurationMenuScrollTaskID = nil
            }
            expandedDurationTaskIDs.remove(taskID)
            if reservedDurationMenuTaskID == taskID {
                clearDurationMenuReserve()
            }
        } else {
            pendingDurationMenuScrollTaskID = nil
            expandedDurationTaskIDs.removeAll()
            clearDurationMenuReserve()
        }
    }

    private func dismissChannelMenu(ifPresentedTaskID taskID: UUID? = nil) {
        if let taskID {
            presentedChannelTaskIDs.remove(taskID)
            if pendingChannelMenuAdjustmentTaskID == taskID {
                pendingChannelMenuAdjustmentTaskID = nil
            }
        } else {
            presentedChannelTaskIDs.removeAll()
            pendingChannelMenuAdjustmentTaskID = nil
        }
    }

    private func dismissPriorityMenu(ifPresentedTaskID taskID: UUID? = nil) {
        if let taskID {
            presentedPriorityTaskIDs.remove(taskID)
            if pendingPriorityMenuAdjustmentTaskID == taskID {
                pendingPriorityMenuAdjustmentTaskID = nil
            }
        } else {
            presentedPriorityTaskIDs.removeAll()
            pendingPriorityMenuAdjustmentTaskID = nil
        }
    }

    private func remainingCardHeights(
        after taskID: UUID,
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> [CGFloat] {
        guard let taskIndex = entries.firstIndex(where: { $0.task.id == taskID }) else { return [] }
        return entries.dropFirst(taskIndex + 1).map { entry in
            WeekflowLayout.homeTaskCardHeight + (taskExpansionHeights[entry.task.id] ?? 0)
        }
    }

    private func requestVerticalScroll(by delta: CGFloat) {
        let request = VerticalScrollRequest(id: UUID(), delta: delta)
        timerScrollRequest = request
        clearVerticalScrollRequestLater(request)
    }

    private func reserveDurationMenu(taskID: UUID, scrollDistance: CGFloat?) {
        let request = scrollDistance.flatMap { distance in
            distance > 0 ? VerticalScrollRequest(id: UUID(), delta: distance) : nil
        }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reservedDurationMenuTaskID = taskID
            if let request {
                timerScrollRequest = request
            }
        }
        if let request {
            clearVerticalScrollRequestLater(request)
        }
    }

    private func clearVerticalScrollRequestLater(_ request: VerticalScrollRequest) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard timerScrollRequest?.id == request.id else { return }
            timerScrollRequest = nil
        }
    }

    private func durationMenuPresentationScrollDistance(
        taskID: UUID,
        viewportHeight: CGFloat
    ) -> CGFloat? {
        guard let cardFrame = taskRowFrameCache.frames[taskID],
              let entry = planningDisplayedEntries(
                store: store,
                date: date,
                preview: poolDropPreview
              ).first(where: { $0.task.id == taskID }) else { return nil }
        let displayedSubtaskCount = entry.task.subtasks.lazy.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let minimumCardBottom = cardFrame.minY
            + WeekflowLayout.homeTaskCardHeight(
                subtaskCount: displayedSubtaskCount,
                timerExpanded: true
            )
        let menuBottom = WeekflowLayout.taskDurationProjectedMenuBottom(
            cardBottom: cardFrame.maxY,
            minimumPresentationCardBottom: minimumCardBottom
        )
        return WeekflowLayout.taskDurationPresentationScrollDistance(
            menuBottom: menuBottom,
            viewportBottom: viewportHeight
        )
    }

    private func timerPanelPresentationScrollDistance(
        taskID: UUID,
        viewportHeight: CGFloat
    ) -> CGFloat? {
        guard let cardFrame = taskRowFrameCache.frames[taskID] else { return nil }
        return WeekflowLayout.taskTimerPresentationScrollDistance(
            cardBottom: cardFrame.maxY + WeekflowLayout.taskTimerExpandedAdditionalHeight,
            viewportBottom: viewportHeight
        )
    }

    private func clearDurationMenuReserve() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            reservedDurationMenuTaskID = nil
        }
    }
}

struct PlanningSortMenuOverlay: View {
    let controlFrame: CGRect
    let containerWidth: CGFloat
    let sortByPriority: () -> Void
    let sortByStartTime: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let menuWidth = min(WeekflowLayout.taskPriorityPopoverWidth, containerWidth)
        let menuHeight = WeekflowLayout.taskPriorityPopoverRowHeight * 2 + 12
        let menuLeading = min(
            max(controlFrame.midX - menuWidth + 20, 0),
            max(containerWidth - menuWidth, 0)
        )
        let menuTop = controlFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        let menuFrame = CGRect(
            x: menuLeading,
            y: menuTop,
            width: menuWidth,
            height: menuHeight
        )
        let pointerX = min(
            max(controlFrame.midX, menuFrame.minX + 14),
            menuFrame.maxX - 14
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [controlFrame, menuFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                PlanningSortMenuRow(
                    icon: "flag",
                    title: "按优先级排序",
                    action: sortByPriority
                )
                PlanningSortMenuRow(
                    icon: "clock",
                    title: "按开始时间排序",
                    action: sortByStartTime
                )
            }
            .padding(6)
            .frame(width: menuWidth, height: menuHeight)
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .fill(WeekflowPalette.surface)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
            .position(x: menuFrame.midX, y: menuFrame.midY)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))

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
                    x: pointerX,
                    y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
    }
}

struct PlanningSortMenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 8)
            .frame(height: WeekflowLayout.taskPriorityPopoverRowHeight)
            .background(
                isHovering ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}
