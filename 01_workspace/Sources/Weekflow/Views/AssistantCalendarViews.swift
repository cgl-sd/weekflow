import SwiftUI

struct AssistantCalendarOptionsMenu: View {
    let showsDailyCutoff: Bool
    let toggleDailyCutoff: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: toggleDailyCutoff) {
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

struct AssistantTaskFilterButton: View {
    let isPresented: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
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
    @Environment(\.businessCalendar) private var businessCalendar
    private var calendar: Calendar { businessCalendar.calendar }
    private let hourHeight: CGFloat = 44
    @State private var resizePreviewMinutes: [UUID: Int] = [:]
    @State private var isDateHovering = false
    @AppStorage("weekflow.calendar.showsDailyCutoff")
    private var showsDailyCutoff = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WeekflowButton { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .pointingHandCursor()
                Spacer()
                if let openDayTasks {
                    WeekflowButton {
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
                WeekflowButton { shiftDay(1) } label: { Image(systemName: "chevron.right") }
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
        CommandRouter.shared.send(.openHighlightedTask)
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

struct AssistantDayTaskListView: View {
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
        CommandRouter.shared.send(.openHighlightedTask)
    }
}

struct AssistantScheduleItem: Identifiable {
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

struct AssistantTimeBlock: View {
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

struct DottedAssistantCalendarFill: View {
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

struct AssistantCalendarStartFence: Shape {
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

