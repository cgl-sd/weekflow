import AppKit
import SwiftUI

struct HomeBoardView: View {
    @Bindable var store: WeekflowStore
    @Binding var visibleDayIndex: Double
    let selectedChannelID: String
    var additionalVisibleWidth: CGFloat = 0
    let addTaskOnDate: (Date) -> Void
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void
    let showCalendar: () -> Void
    var planDay: (Date) -> Void = { _ in }
    var referenceDate: Date = .now
    private let calendar = Calendar.current
    private let columnSpacing = WeekflowLayout.homeDayColumnSpacing
    private let visibleColumnCount = WeekflowLayout.boardVisibleDayCount
    private let boardLeadingPadding = WeekflowLayout.homeBoardLeadingPadding
    private let boardTrailingPadding = WeekflowLayout.homeBoardTrailingPadding
    private let scrollbarThumbFraction: CGFloat = 0.18
    @State private var draggedTaskToken: TaskDragToken?

    private var boardDates: [Date] {
        let today = calendar.startOfDay(for: referenceDate)
        return (-7..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = max(proxy.size.width - boardLeadingPadding - boardTrailingPadding, 1)
            let threeColumnReferenceWidth = max(viewportWidth - additionalVisibleWidth, 1)
            let dynamicColumnWidth = WeekflowLayout.homeDayColumnWidth(
                for: threeColumnReferenceWidth,
                columnSpacing: columnSpacing
            )
            let columnStep = dynamicColumnWidth + columnSpacing
            let contentWidth = CGFloat(boardDates.count) * dynamicColumnWidth + CGFloat(max(boardDates.count - 1, 0)) * columnSpacing
            let maxOffset = max(contentWidth - viewportWidth, 0)
            let maxScrollableDayIndex = Double(maxOffset / columnStep)
            let clampedDayIndex = min(max(visibleDayIndex, 0), maxScrollableDayIndex)
            let contentOffset = CGFloat(clampedDayIndex) * columnStep
            let renderedDayRange = WeekflowLayout.homeRenderedDayRange(
                totalDayCount: boardDates.count,
                visibleDayIndex: clampedDayIndex
            )
            let scrollbarHeight: CGFloat = 22
            let boardHeight = max(proxy.size.height - scrollbarHeight, 1)

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    HStack(alignment: .top, spacing: columnSpacing) {
                        ForEach(renderedDayRange, id: \.self) { index in
                            let date = boardDates[index]
                            HomeDayColumn(
                                date: date,
                                entries: store.tasks(on: date, channelID: selectedChannelID),
                                addTask: { addTaskOnDate(date) },
                                selectDate: { store.activeDay = date; showCalendar() },
                                planDate: { planDay(date) },
                                openTask: openTask,
                                store: store,
                                draggedTaskToken: $draggedTaskToken,
                                width: dynamicColumnWidth
                            )
                        }
                    }
                    .padding(.top, 18)
                    .offset(
                        x: CGFloat(renderedDayRange.lowerBound) * columnStep - contentOffset
                    )
                }
                .frame(width: viewportWidth, height: boardHeight, alignment: .topLeading)
                .clipped()
                .padding(.leading, boardLeadingPadding)
                .padding(.trailing, boardTrailingPadding)

                HomeBoardScrollbar(
                    dayIndex: $visibleDayIndex,
                    maxDayIndex: maxScrollableDayIndex,
                    thumbFraction: scrollbarThumbFraction
                )
                .padding(.bottom, 2)
            }
        }
    }
}

private struct HomeBoardScrollbar: View {
    @Binding var dayIndex: Double
    let maxDayIndex: Double
    let thumbFraction: CGFloat
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let fullWidth = max(proxy.size.width, 1)
            let trackWidth = fullWidth
            let maxIndex = max(maxDayIndex, 1)
            let thumbWidth = max(trackWidth * thumbFraction, 64)
            let travelWidth = max(trackWidth - thumbWidth, 1)
            let progress = min(max(dayIndex / maxIndex, 0), 1)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(WeekflowPalette.border.opacity(0.65))
                    .frame(height: 1)
                ZStack(alignment: .leading) {
                    Color.clear
                        .frame(height: 16)
                    WeekflowRoundedRectangle(cornerRadius: 3)
                        .fill(WeekflowPalette.secondaryText.opacity(isHovering ? 0.68 : 0.46))
                        .frame(width: thumbWidth, height: isHovering ? 9 : 8)
                        .offset(x: travelWidth * progress)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let proposed = value.location.x - thumbWidth / 2
                        let nextProgress = min(max(proposed / travelWidth, 0), 1)
                        dayIndex = nextProgress * maxIndex
                    }
            )
            .pointingHandCursor()
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .frame(height: 20)
        }
        .frame(height: 20)
        .accessibilityLabel("首页日期拖动条")
    }
}

struct HomeDayColumn: View {
    let date: Date
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    let addTask: () -> Void
    let selectDate: () -> Void
    let planDate: () -> Void
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void
    @Bindable var store: WeekflowStore
    @Binding var draggedTaskToken: TaskDragToken?
    let width: CGFloat
    var highlightsDateHeader = false
    var dateSelectionHelp: String? = nil
    @State private var isHeaderHovering = false
    @State private var isDateHovering = false
    @State private var timerScrollRequest: VerticalScrollRequest?
    @State private var taskExpansionHeights: [UUID: CGFloat] = [:]
    @State private var expandedDurationTaskIDs: Set<UUID> = []
    @State private var reservedDurationMenuTaskID: UUID?
    @State private var pendingDurationMenuScrollTaskID: UUID?
    @State private var presentedStartTimeTaskIDs: Set<UUID> = []
    @State private var pendingStartTimeMenuAdjustmentTaskID: UUID?
    @State private var presentedDateTaskIDs: Set<UUID> = []
    @State private var pendingDateMenuAdjustmentTaskID: UUID?
    @State private var presentedChannelTaskIDs: Set<UUID> = []
    @State private var pendingChannelMenuAdjustmentTaskID: UUID?
    @State private var presentedPriorityTaskIDs: Set<UUID> = []
    @State private var pendingPriorityMenuAdjustmentTaskID: UUID?
    @State private var pendingTimerPanelAdjustmentTaskID: UUID?
    @State private var taskRowFrameCache = HomeTaskRowFrameCache()
    @State private var verticalScrollerTrackWidth = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: .legacy
    )

    private var cardContentWidth: CGFloat {
        WeekflowLayout.homeCardContentWidth(for: width)
    }

    private var inferredStartTimes: [UUID: Date] {
        TaskCardSchedule.inferredStartTimes(for: entries.map(\.task))
    }

    private var dailyProgress: DailyTaskProgress {
        DailyTaskProgress(tasks: entries.map(\.task))
    }

    private var durationMenuOverflowHeight: CGFloat {
        guard let durationLayoutTaskID,
              entries.contains(where: { $0.task.id == durationLayoutTaskID }) else { return 0 }
        return WeekflowLayout.taskDurationMenuOverflow(
            remainingCardHeights: remainingCardHeights(after: durationLayoutTaskID)
        )
    }

    private var durationLayoutTaskID: UUID? {
        reservedDurationMenuTaskID
    }

    private var dateMenuOverflowHeight: CGFloat {
        guard let taskID = presentedDateTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskDateMenuOverflow(
            remainingCardHeights: remainingCardHeights(after: taskID)
        )
    }

    private var startTimeMenuOverflowHeight: CGFloat {
        guard let taskID = presentedStartTimeTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskStartTimeMenuHeight,
            remainingCardHeights: remainingCardHeights(after: taskID)
        )
    }

    private var channelMenuOverflowHeight: CGFloat {
        guard let taskID = presentedChannelTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskChannelPopoverHeight(
                channelCount: store.activeChannels.count
            ),
            remainingCardHeights: remainingCardHeights(after: taskID)
        )
    }

    private var priorityMenuOverflowHeight: CGFloat {
        guard let taskID = presentedPriorityTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskPriorityPopoverHeight,
            remainingCardHeights: remainingCardHeights(after: taskID)
        )
    }

    private var timerPanelBottomReserve: CGFloat {
        guard expandedDurationTaskIDs.isEmpty,
              reservedDurationMenuTaskID == nil,
              presentedStartTimeTaskIDs.isEmpty,
              presentedDateTaskIDs.isEmpty,
              presentedChannelTaskIDs.isEmpty,
              presentedPriorityTaskIDs.isEmpty,
              !taskExpansionHeights.isEmpty else { return 0 }
        return WeekflowLayout.taskDurationMenuViewportBottomClearance
    }

    var body: some View {
        let cardCount = entries.count
        let taskScrollViewportWidth = WeekflowLayout.homeTaskScrollViewportWidth(for: width)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Button(action: selectDate) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(date.formatted(.dateTime.weekday(.wide)))
                            .font(.system(size: WeekflowLayout.homeDayWeekdayFontSize, weight: .bold))
                        Text(date.formatted(.dateTime.month().day()))
                            .font(.system(size: WeekflowLayout.homeDayDateFontSize))
                            .foregroundStyle(WeekflowPalette.secondaryText)
                    }
                    .padding(.horizontal, highlightsDateHeader ? 7 : 0)
                    .padding(.vertical, highlightsDateHeader ? 5 : 0)
                    .background(
                        highlightsDateHeader && isDateHovering
                            ? WeekflowPalette.surfaceSelected
                            : .clear,
                        in: WeekflowRoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isDateHovering = hovering
                    }
                }
                .help(dateSelectionHelp ?? "在右侧日历中查看\(date.dayLabel)")
                Spacer()
                DailyPlanButton(isVisible: isHeaderHovering, action: planDate)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.14)) {
                    isHeaderHovering = hovering
                }
            }
            HomeDayProgressBar(progress: dailyProgress)
                .frame(
                    width: cardContentWidth * WeekflowLayout.homeDailyProgressWidthFraction,
                    height: WeekflowLayout.homeDailyProgressHeight
                )
                .padding(.vertical, WeekflowLayout.homeDailyProgressVerticalPadding)
                .frame(width: cardContentWidth, alignment: .center)
            HomeAddTaskButton(action: addTask)
                .frame(width: cardContentWidth, alignment: .leading)
            GeometryReader { taskArea in
                let expandedAdditionalHeight = taskExpansionHeights.values.reduce(0, +)
                    + durationMenuOverflowHeight
                    + startTimeMenuOverflowHeight
                    + dateMenuOverflowHeight
                    + channelMenuOverflowHeight
                    + priorityMenuOverflowHeight
                    + timerPanelBottomReserve
                let showsVerticalScroller = WeekflowLayout.homeShowsVerticalScroller(
                    taskCount: cardCount,
                    expandedAdditionalHeight: expandedAdditionalHeight,
                    viewportHeight: taskArea.size.height
                )
                let taskCardWidth = WeekflowLayout.homeTaskCardWidth(
                    for: width,
                    showsVerticalScroller: showsVerticalScroller
                )

                ScrollView(.vertical) {
                    LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                        ForEach(entries, id: \.task.id) { entry in
                            SunsamaTaskCard(
                                entry: entry,
                                store: store,
                                dragSourceDate: date,
                                inferredStartTime: inferredStartTimes[entry.task.id],
                                compactHeight: WeekflowLayout.homeTaskCardHeight,
                                showsEstimatedDurationMenu: Binding(
                                    get: { expandedDurationTaskIDs.contains(entry.task.id) },
                                    set: { isPresented in
                                        setDurationMenuPresented(
                                            isPresented,
                                            taskID: entry.task.id,
                                            viewportHeight: taskArea.size.height
                                        )
                                    }
                                ),
                                showsStartTimeMenu: Binding(
                                    get: { presentedStartTimeTaskIDs.contains(entry.task.id) },
                                    set: { isPresented in
                                        setStartTimeMenuPresented(
                                            isPresented,
                                            taskID: entry.task.id
                                        )
                                    }
                                ),
                                showsDateMenu: Binding(
                                    get: { presentedDateTaskIDs.contains(entry.task.id) },
                                    set: { isPresented in
                                        setDateMenuPresented(isPresented, taskID: entry.task.id)
                                    }
                                ),
                                showsChannelMenu: Binding(
                                    get: { presentedChannelTaskIDs.contains(entry.task.id) },
                                    set: { isPresented in
                                        setChannelMenuPresented(
                                            isPresented,
                                            taskID: entry.task.id
                                        )
                                    }
                                ),
                                showsPriorityMenu: Binding(
                                    get: { presentedPriorityTaskIDs.contains(entry.task.id) },
                                    set: { isPresented in
                                        setPriorityMenuPresented(
                                            isPresented,
                                            taskID: entry.task.id
                                        )
                                    }
                                ),
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
                                openTask: { openTask(entry) }
                            )
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: HomeTaskRowFramePreferenceKey.self,
                                        value: [
                                            entry.task.id: proxy.frame(
                                                in: .named("homeTaskScrollViewport")
                                            )
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
                            + durationMenuOverflowHeight
                            + startTimeMenuOverflowHeight
                            + dateMenuOverflowHeight
                            + channelMenuOverflowHeight
                            + priorityMenuOverflowHeight
                            + timerPanelBottomReserve
                    )
                    .frame(width: taskCardWidth, alignment: .topLeading)
                    .frame(minHeight: 120, alignment: .topLeading)
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
                            let contentFrame = overlay.frame(in: .named("homeTaskScrollViewport"))
                            let viewportBottom = -contentFrame.minY + taskArea.size.height
                            ZStack(alignment: .topLeading) {
                                if let taskID = expandedDurationTaskIDs.first,
                                   let anchor = anchors[.card(taskID)],
                                   let entry = entries.first(where: { $0.task.id == taskID }) {
                                    durationMenuOverlay(
                                        entry: entry,
                                        cardFrame: overlay[anchor],
                                        durationButtonFrame: anchors[.durationButton(taskID)].map { overlay[$0] },
                                        estimatedDurationButtonFrame: anchors[.estimatedDurationButton(taskID)].map { overlay[$0] },
                                        cardWidth: taskCardWidth,
                                        viewportBottom: viewportBottom
                                    )
                                }

                                if let taskID = pendingTimerPanelAdjustmentTaskID,
                                   let anchor = anchors[.card(taskID)],
                                   expandedDurationTaskIDs.isEmpty,
                                   presentedStartTimeTaskIDs.isEmpty,
                                   presentedDateTaskIDs.isEmpty,
                                   presentedChannelTaskIDs.isEmpty,
                                   presentedPriorityTaskIDs.isEmpty {
                                    let cardBottom = overlay[anchor].maxY
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
                .coordinateSpace(name: "homeTaskScrollViewport")
                .overlayPreferenceValue(TaskDurationMenuAnchorPreferenceKey.self) { anchors in
                    GeometryReader { overlay in
                        if let taskID = presentedStartTimeTaskIDs.first,
                           let cardAnchor = anchors[.card(taskID)],
                           let controlAnchor = anchors[.startTimeButton(taskID)],
                           let entry = entries.first(where: { $0.task.id == taskID }) {
                            startTimeMenuOverlay(
                                entry: entry,
                                cardFrame: overlay[cardAnchor],
                                controlFrame: overlay[controlAnchor],
                                viewportWidth: taskScrollViewportWidth,
                                scrollerTrackWidth: verticalScrollerTrackWidth,
                                viewportBottom: taskArea.size.height
                            )
                        }

                        if let taskID = presentedDateTaskIDs.first,
                           let anchor = anchors[.card(taskID)],
                           let entry = entries.first(where: { $0.task.id == taskID }) {
                            dateMenuOverlay(
                                entry: entry,
                                cardFrame: overlay[anchor],
                                dateButtonFrame: anchors[.dateButton(taskID)].map { overlay[$0] },
                                viewportWidth: taskScrollViewportWidth,
                                scrollerTrackWidth: verticalScrollerTrackWidth,
                                showsVerticalScroller: showsVerticalScroller,
                                viewportBottom: taskArea.size.height
                            )
                        }

                        if let taskID = presentedChannelTaskIDs.first,
                           let cardAnchor = anchors[.card(taskID)],
                           let controlAnchor = anchors[.channelButton(taskID)],
                           let entry = entries.first(where: { $0.task.id == taskID }) {
                            channelMenuOverlay(
                                entry: entry,
                                cardFrame: overlay[cardAnchor],
                                controlFrame: overlay[controlAnchor],
                                viewportWidth: taskScrollViewportWidth,
                                scrollerTrackWidth: verticalScrollerTrackWidth,
                                viewportBottom: taskArea.size.height
                            )
                        }

                        if let taskID = presentedPriorityTaskIDs.first,
                           let cardAnchor = anchors[.card(taskID)],
                           let controlAnchor = anchors[.priorityButton(taskID)],
                           let entry = entries.first(where: { $0.task.id == taskID }) {
                            priorityMenuOverlay(
                                entry: entry,
                                cardFrame: overlay[cardAnchor],
                                controlFrame: overlay[controlAnchor],
                                viewportWidth: taskScrollViewportWidth,
                                scrollerTrackWidth: verticalScrollerTrackWidth,
                                viewportBottom: taskArea.size.height
                            )
                        }
                    }
                }
                .scrollIndicators(.visible)
                .contentShape(Rectangle())
                .onPreferenceChange(HomeTaskRowFramePreferenceKey.self) {
                    taskRowFrameCache.frames = $0
                }
                .onDrop(
                    of: [.utf8PlainText],
                    delegate: HomeColumnTaskDropDelegate(
                        draggedTaskToken: $draggedTaskToken,
                        date: date,
                        rowFrames: { taskRowFrameCache.frames },
                        store: store
                    )
                )
                .onPreferenceChange(TaskDurationMenuOverflowPreferenceKey.self) { overflow in
                    guard let overflow else { return }
                    if let taskID = pendingDurationMenuScrollTaskID,
                       expandedDurationTaskIDs.contains(taskID) {
                        pendingDurationMenuScrollTaskID = nil
                        guard overflow > 0 else { return }
                        requestVerticalScroll(by: overflow)
                        return
                    } else if let taskID = pendingDateMenuAdjustmentTaskID,
                              presentedDateTaskIDs.contains(taskID) {
                        pendingDateMenuAdjustmentTaskID = nil
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
                .zIndex(
                    expandedDurationTaskIDs.isEmpty
                        && presentedStartTimeTaskIDs.isEmpty
                        && presentedDateTaskIDs.isEmpty
                        && presentedChannelTaskIDs.isEmpty
                        && presentedPriorityTaskIDs.isEmpty ? 0 : 1
                )
            }
            .frame(width: taskScrollViewportWidth, alignment: .topLeading)
            .frame(minHeight: 120, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: width, maxWidth: width, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func durationMenuOverlay(
        entry: (goal: WeeklyGoal, task: WeekTask),
        cardFrame: CGRect,
        durationButtonFrame: CGRect?,
        estimatedDurationButtonFrame: CGRect?,
        cardWidth: CGFloat,
        viewportBottom: CGFloat
    ) -> some View {
        let displayedSubtaskCount = entry.task.subtasks.lazy.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        TaskCardDurationMenuOverlay(
            entry: entry,
            store: store,
            cardFrame: cardFrame,
            durationButtonFrame: durationButtonFrame,
            estimatedDurationButtonFrame: estimatedDurationButtonFrame,
            cardWidth: cardWidth,
            viewportBottom: viewportBottom,
            minimumPresentationCardBottom: cardFrame.minY
                + WeekflowLayout.homeTaskCardHeight(
                    subtaskCount: displayedSubtaskCount,
                    timerExpanded: true
                ),
            dismiss: { dismissDurationMenu(ifPresentedTaskID: entry.task.id) }
        )
    }

    @ViewBuilder
    private func startTimeMenuOverlay(
        entry: (goal: WeeklyGoal, task: WeekTask),
        cardFrame: CGRect,
        controlFrame: CGRect,
        viewportWidth: CGFloat,
        scrollerTrackWidth: CGFloat,
        viewportBottom: CGFloat
    ) -> some View {
        TaskCardStartTimeMenuOverlay(
            entry: entry,
            store: store,
            anchorDate: date,
            cardFrame: cardFrame,
            controlFrame: controlFrame,
            viewportWidth: viewportWidth,
            scrollerTrackWidth: scrollerTrackWidth,
            viewportBottom: viewportBottom,
            dismiss: { dismissStartTimeMenu(ifPresentedTaskID: entry.task.id) }
        )
    }

    @ViewBuilder
    private func dateMenuOverlay(
        entry: (goal: WeeklyGoal, task: WeekTask),
        cardFrame: CGRect,
        dateButtonFrame: CGRect?,
        viewportWidth: CGFloat,
        scrollerTrackWidth: CGFloat,
        showsVerticalScroller: Bool,
        viewportBottom: CGFloat
    ) -> some View {
        TaskCardDateMenuOverlay(
            entry: entry,
            anchorDate: date,
            cardFrame: cardFrame,
            dateButtonFrame: dateButtonFrame,
            viewportWidth: viewportWidth,
            scrollerTrackWidth: scrollerTrackWidth,
            showsVerticalScroller: showsVerticalScroller,
            viewportBottom: viewportBottom,
            moveToDate: { moveTask(entry, to: $0) },
            dismiss: { dismissDateMenu(ifPresentedTaskID: entry.task.id) }
        )
    }

    @ViewBuilder
    private func channelMenuOverlay(
        entry: (goal: WeeklyGoal, task: WeekTask),
        cardFrame: CGRect,
        controlFrame: CGRect,
        viewportWidth: CGFloat,
        scrollerTrackWidth: CGFloat,
        viewportBottom: CGFloat
    ) -> some View {
        TaskCardChannelMenuOverlay(
            entry: entry,
            store: store,
            cardFrame: cardFrame,
            controlFrame: controlFrame,
            viewportWidth: viewportWidth,
            scrollerTrackWidth: scrollerTrackWidth,
            viewportBottom: viewportBottom,
            dismiss: { dismissChannelMenu(ifPresentedTaskID: entry.task.id) }
        )
    }

    @ViewBuilder
    private func priorityMenuOverlay(
        entry: (goal: WeeklyGoal, task: WeekTask),
        cardFrame: CGRect,
        controlFrame: CGRect,
        viewportWidth: CGFloat,
        scrollerTrackWidth: CGFloat,
        viewportBottom: CGFloat
    ) -> some View {
        TaskCardPriorityMenuOverlay(
            entry: entry,
            store: store,
            anchorDate: date,
            cardFrame: cardFrame,
            controlFrame: controlFrame,
            viewportWidth: viewportWidth,
            scrollerTrackWidth: scrollerTrackWidth,
            viewportBottom: viewportBottom,
            dismiss: { dismissPriorityMenu(ifPresentedTaskID: entry.task.id) }
        )
    }

    private func setDurationMenuPresented(
        _ isPresented: Bool,
        taskID: UUID,
        viewportHeight: CGFloat
    ) {
        if isPresented {
            dismissStartTimeMenu()
            presentedDateTaskIDs.removeAll()
            pendingDateMenuAdjustmentTaskID = nil
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
            dismissDurationMenu()
            dismissDateMenu()
            dismissChannelMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedStartTimeTaskIDs = [taskID]
            pendingStartTimeMenuAdjustmentTaskID = taskID
        } else {
            dismissStartTimeMenu(ifPresentedTaskID: taskID)
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

    private func setDateMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissChannelMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedDateTaskIDs = [taskID]
            pendingDateMenuAdjustmentTaskID = taskID
        } else {
            presentedDateTaskIDs.remove(taskID)
            if pendingDateMenuAdjustmentTaskID == taskID {
                pendingDateMenuAdjustmentTaskID = nil
            }
        }
    }

    private func dismissDateMenu(ifPresentedTaskID taskID: UUID? = nil) {
        if let taskID {
            presentedDateTaskIDs.remove(taskID)
            if pendingDateMenuAdjustmentTaskID == taskID {
                pendingDateMenuAdjustmentTaskID = nil
            }
        } else {
            presentedDateTaskIDs.removeAll()
            pendingDateMenuAdjustmentTaskID = nil
        }
    }

    private func setChannelMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissDateMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedChannelTaskIDs = [taskID]
            pendingChannelMenuAdjustmentTaskID = taskID
        } else {
            dismissChannelMenu(ifPresentedTaskID: taskID)
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

    private func setPriorityMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissDateMenu()
            dismissChannelMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedPriorityTaskIDs = [taskID]
            pendingPriorityMenuAdjustmentTaskID = taskID
        } else {
            dismissPriorityMenu(ifPresentedTaskID: taskID)
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

    private func moveTask(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        to targetDate: Date
    ) {
        store.relocateTask(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            from: date,
            to: targetDate
        )
        dismissDateMenu()
    }

    private func remainingCardHeights(after taskID: UUID) -> [CGFloat] {
        guard let taskIndex = entries.firstIndex(where: { $0.task.id == taskID }) else { return [] }
        let taskHeights = entries.dropFirst(taskIndex + 1).map { entry in
            WeekflowLayout.homeTaskCardHeight + (taskExpansionHeights[entry.task.id] ?? 0)
        }
        return taskHeights
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
              let entry = entries.first(where: { $0.task.id == taskID }) else { return nil }
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

struct TaskDurationMenuOverflowPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        guard let next = nextValue() else { return }
        value = max(value ?? 0, next)
    }
}

private struct TaskTimerDividerPointerOverlay: View {
    let taskID: UUID
    let anchors: [TaskCardPresentationAnchor: Anchor<CGRect>]

    var body: some View {
        GeometryReader { proxy in
            if let timerAnchor = anchors[.timerButton(taskID)],
               let dividerAnchor = anchors[.timerDivider(taskID)] {
                pointer(
                    timerFrame: proxy[timerAnchor],
                    dividerFrame: proxy[dividerAnchor]
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func pointer(timerFrame: CGRect, dividerFrame: CGRect) -> some View {
        TaskDurationMenuPointer()
            .fill(WeekflowPalette.surface)
            .overlay {
                TaskDurationMenuPointerOutline()
                    .stroke(WeekflowPalette.borderStrong.opacity(0.9), lineWidth: 1)
            }
            .frame(
                width: WeekflowLayout.taskTimerDividerPointerWidth,
                height: WeekflowLayout.taskTimerDividerPointerHeight
            )
            .position(
                x: timerFrame.midX,
                y: dividerFrame.midY
                    - WeekflowLayout.taskTimerDividerPointerHeight / 2
                    + 0.5
            )
    }
}

/// The date bubble normally has a complete outline. When its trailing edge is
/// exactly shared with the visible native scroller, only that vertical segment
/// is omitted so the scroller line can act as the menu boundary.
struct TaskDateMenuBorder: Shape {
    let cornerRadius: CGFloat
    let hidesTrailingEdge: Bool

    func path(in rect: CGRect) -> Path {
        guard hidesTrailingEdge else {
            return Path(roundedRect: rect, cornerRadius: cornerRadius)
        }

        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + radius),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct HomeDayProgressBar: View {
    let progress: DailyTaskProgress

    var body: some View {
        WeekflowDailyProgressTrack(
            fraction: progress.fraction,
            hasProgress: progress.isVisible,
            accessibilityLabel: "当天完成进度",
            accessibilityValue: "已完成 \(progress.completedTaskCount) 项，共 \(progress.totalTaskCount) 项"
        )
    }
}

private struct DailyPlanButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("计划", systemImage: "calendar.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(WeekflowPalette.objective, in: WeekflowRoundedRectangle(cornerRadius: 7))
                .shadow(color: WeekflowPalette.objective.opacity(0.25), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .pointingHandCursor(coversDescendants: true)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .help("计划这一天")
        .accessibilityHidden(!isVisible)
    }
}

struct HomeAddTaskButton: View {
    let action: () -> Void
    @State private var isHovering = false
    @AppStorage(TaskCardTypographyPreferences.taskTextSizeKey)
    private var storedTaskTextSize = TaskCardTypographyPreferences.defaultTaskTextSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("添加任务")
                    .font(.system(size: taskTextSize, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: WeekflowLayout.homeAddTaskHeight, alignment: .leading)
            .padding(.horizontal, 14)
            .boxHoverChrome(isHovering: isHovering, cornerRadius: 8)
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help("给这一天添加任务")
    }

    private var taskTextSize: CGFloat {
        TaskCardTypographyPreferences.taskTextSize(from: storedTaskTextSize)
    }
}

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
                    Button {
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
                                        WeekflowCommand.post(.weekflowOpenChannelSettings)
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
            Button {
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
        Button {
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
        let day = Calendar.current.startOfDay(for: entry.task.plannedDate ?? dragSourceDate ?? .now)
        let start = Calendar.current.date(byAdding: .minute, value: minute, to: day) ?? day
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
        let targetDate = Calendar.current.date(byAdding: .day, value: dayOffset, to: baseDate)
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

private struct TaskCardWidthPreferenceKey: PreferenceKey {
    static let defaultValue = WeekflowLayout.taskDatePopoverWidth

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct TaskCardPriorityButton: View {
    let priority: TaskPriority
    let showsBadge: Bool
    let help: String
    @Binding var isPopoverPresented: Bool
    let presentationAnchor: TaskCardPresentationAnchor?
    let selectPriority: (TaskPriority) -> Void
    let action: () -> Void
    @State private var hovering = false
    @AppStorage(TaskCardTypographyPreferences.metadataSizeKey)
    private var storedMetadataSize = TaskCardTypographyPreferences.defaultMetadataSize
    @AppStorage(TaskCardTypographyPreferences.iconSizeKey)
    private var storedIconSize = TaskCardTypographyPreferences.defaultIconSize

    var body: some View {
        Button(action: action) {
            priorityLabel
            .foregroundStyle(
                showsBadge
                    ? priority.flagColor
                    : (hovering ? WeekflowPalette.iconHover : WeekflowPalette.textMuted)
            )
            .background(priorityBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering = $0 }
        .help(help)
    }

    @ViewBuilder
    private var priorityLabel: some View {
        if !showsBadge {
            Image(systemName: "flag")
                .font(.system(
                    size: iconSize,
                    weight: hovering ? .semibold : .regular
                ))
                .anchorPreference(
                    key: TaskDurationMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    presentationAnchor.map { [$0: anchor] } ?? [:]
                }
                .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                    priorityPopover
                }
                .frame(
                    width: WeekflowLayout.taskCardIconHitTarget,
                    height: WeekflowLayout.taskCardIconHitTarget,
                    alignment: .leading
                )
        } else {
            Text(priorityBadgeText)
                .font(.system(size: metadataSize, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: WeekflowLayout.taskCardIconHitTarget)
                .frame(height: WeekflowLayout.taskCardPriorityBadgeHeight)
                .anchorPreference(
                    key: TaskDurationMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    presentationAnchor.map { [$0: anchor] } ?? [:]
                }
                .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                    priorityPopover
                }
        }
    }

    private var priorityPopover: some View {
        TaskPriorityPopover(selectedPriority: priority, select: selectPriority)
    }

    @ViewBuilder
    private var priorityBackground: some View {
        if showsBadge {
            Capsule()
                .fill(priority.flagColor.opacity(hovering ? 0.18 : 0.10))
                .overlay(Capsule().stroke(priority.flagColor.opacity(0.62), lineWidth: 1))
        } else {
            Color.clear
        }
    }

    private var priorityBadgeText: String {
        switch priority {
        case .must: "紧急"
        case .should: "优先"
        case .later: "低"
        case .none: ""
        }
    }

    private var metadataSize: CGFloat {
        TaskCardTypographyPreferences.metadataSize(from: storedMetadataSize)
    }

    private var iconSize: CGFloat {
        TaskCardTypographyPreferences.iconSize(from: storedIconSize)
    }
}

/// Main tasks and subtasks intentionally share this exact completion control so
/// their symbol size, hit target and user typography adjustment cannot diverge.
private struct TaskCardCompletionButton: View {
    let isCompleted: Bool
    let inactiveTint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        TaskCardIconButton(
            symbol: isCompleted ? "checkmark.circle.fill" : "checkmark.circle",
            tint: isCompleted ? WeekflowPalette.complete : inactiveTint,
            hoverSymbol: "checkmark.circle.fill",
            hoverTint: WeekflowPalette.complete,
            sizeAdjustment: TaskCardTypographyPreferences.completionIconSizeAdjustment,
            help: help,
            action: action
        )
    }
}

private struct TaskCardIconButton: View {
    let symbol: String
    let tint: Color
    let hoverSymbol: String?
    let hoverTint: Color
    let sizeAdjustment: CGFloat
    let help: String
    let presentationAnchor: TaskCardPresentationAnchor?
    let action: () -> Void
    @State private var isHovering = false
    @AppStorage(TaskCardTypographyPreferences.iconSizeKey)
    private var storedIconSize = TaskCardTypographyPreferences.defaultIconSize

    init(
        symbol: String,
        tint: Color,
        hoverSymbol: String? = nil,
        hoverTint: Color = WeekflowPalette.iconHover,
        sizeAdjustment: CGFloat = 0,
        help: String,
        presentationAnchor: TaskCardPresentationAnchor? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.tint = tint
        self.hoverSymbol = hoverSymbol
        self.hoverTint = hoverTint
        self.sizeAdjustment = sizeAdjustment
        self.help = help
        self.presentationAnchor = presentationAnchor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: isHovering ? (hoverSymbol ?? symbol) : symbol)
                .font(.system(
                    size: iconSize + sizeAdjustment,
                    weight: isHovering ? .semibold : .regular
                ))
                .foregroundStyle(isHovering ? hoverTint : tint)
                .anchorPreference(
                    key: TaskDurationMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) { anchor in
                    presentationAnchor.map { [$0: anchor] } ?? [:]
                }
                .frame(
                    width: WeekflowLayout.taskCardIconHitTarget,
                    height: WeekflowLayout.taskCardIconHitTarget,
                    alignment: .leading
                )
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .help(help)
        .accessibilityLabel(help)
    }

    private var iconSize: CGFloat {
        TaskCardTypographyPreferences.iconSize(from: storedIconSize)
    }
}
