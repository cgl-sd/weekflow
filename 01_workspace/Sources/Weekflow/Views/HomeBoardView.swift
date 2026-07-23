import SwiftUI

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
    @Environment(\.businessCalendar) private var businessCalendar
    private var calendar: Calendar { businessCalendar.calendar }
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

struct HomeBoardScrollbar: View {
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
                WeekflowButton(action: selectDate) {
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

