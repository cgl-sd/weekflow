import SwiftUI

struct WorkspaceCalendarView: View {
    @Bindable var store: WeekflowStore
    let mode: WorkspaceView
    let selectedDate: Date
    let selectedChannelID: String
    private let calendar = Calendar.current

    var body: some View {
        Group {
            if mode == .monthCalendar {
                MonthWorkspaceCalendar(
                    store: store,
                    month: selectedDate,
                    selectedChannelID: selectedChannelID
                )
            } else {
                TimeWorkspaceCalendar(
                    store: store,
                    dates: visibleDates,
                    selectedChannelID: selectedChannelID
                )
            }
        }
        .background(WeekflowPalette.canvas)
    }

    private var visibleDates: [Date] {
        switch mode {
        case .board, .monthCalendar:
            return []
        case .dayCalendar, .threeDayCalendar:
            return (0..<mode.visibleDayCount).compactMap {
                calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: selectedDate))
            }
        case .weekdaysCalendar, .weekCalendar:
            let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate)
            let start = interval?.start ?? calendar.startOfDay(for: selectedDate)
            return (0..<mode.visibleDayCount).compactMap {
                calendar.date(byAdding: .day, value: $0, to: start)
            }
        }
    }
}

private struct TimeWorkspaceCalendar: View {
    @Bindable var store: WeekflowStore
    let dates: [Date]
    let selectedChannelID: String
    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 48
    private let timeGutterWidth: CGFloat = 48
    @State private var resizePreviewMinutes: [UUID: Int] = [:]

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - WeekflowLayout.scrollbarGutterWidth, 1)
            let gridWidth = max(contentWidth - timeGutterWidth, 1)
            let columnWidth = gridWidth / CGFloat(max(dates.count, 1))

            VStack(spacing: 0) {
                dateHeader(columnWidth: columnWidth)
                    .frame(height: 80)
                Divider()
                ScrollView(.vertical) {
                    ZStack(alignment: .topLeading) {
                        timeGrid(gridWidth: gridWidth, columnWidth: columnWidth)
                        scheduleBlocks(columnWidth: columnWidth)
                    }
                    .frame(width: contentWidth, height: CalendarTimelineLayout.contentHeight(hourHeight: hourHeight))
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func dateHeader(columnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                Image(systemName: "plus").font(.system(size: 11))
                Text("1×").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(WeekflowPalette.secondaryText.opacity(0.65))
            .frame(width: timeGutterWidth)

            ForEach(dates, id: \.self) { date in
                VStack(alignment: .leading, spacing: 3) {
                    Text(date.formatted(.dateTime.locale(Locale(identifier: "en_US")).weekday(.abbreviated)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(calendar.component(.day, from: date))")
                        .font(.system(size: 20, weight: .medium))
                }
                .foregroundStyle(calendar.isDateInToday(date) ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .padding(.leading, 12)
                .frame(width: columnWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Divider() }
            }
        }
    }

    private func timeGrid(gridWidth: CGFloat, columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(CalendarTimelineLayout.hourRange, id: \.self) { hour in
                let y = CGFloat(hour - CalendarTimelineLayout.firstHour) * hourHeight
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.secondaryText.opacity(0.62))
                    .frame(width: timeGutterWidth - 7, alignment: .trailing)
                    .offset(y: y + 6)

                Rectangle()
                    .fill(WeekflowPalette.border.opacity(0.34))
                    .frame(width: gridWidth, height: 0.5)
                    .offset(x: timeGutterWidth, y: y)
            }

            ForEach(0...dates.count, id: \.self) { index in
                Rectangle()
                    .fill(WeekflowPalette.border.opacity(0.34))
                    .frame(width: 0.5, height: CalendarTimelineLayout.contentHeight(hourHeight: hourHeight))
                    .offset(x: timeGutterWidth + CGFloat(index) * columnWidth)
            }
        }
    }

    private func scheduleBlocks(columnWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                ForEach(blocks(on: date)) { block in
                    let displayedMinutes = resizePreviewMinutes[block.id] ?? block.minutes
                    CalendarTimeBlock(
                        block: block,
                        displayedMinutes: displayedMinutes,
                        openTask: { openTask(block.taskReference, on: block.start) },
                        pinTask: {
                            togglePin(block.taskReference)
                        },
                        resizePreview: { previewResize(blockID: block.id, minutes: $0) },
                        resizeCommit: { minutes in
                            if let reference = block.taskReference {
                                store.updateTaskEstimatedMinutes(
                                    goalID: reference.goalID,
                                    taskID: reference.taskID,
                                    minutes: minutes
                                )
                            }
                            resizePreviewMinutes.removeValue(forKey: block.id)
                        }
                    )
                        .frame(
                            width: max(columnWidth - 4, 24),
                            height: blockHeight(minutes: displayedMinutes)
                        )
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                        .offset(
                            x: timeGutterWidth + CGFloat(index) * columnWidth + 2,
                            y: blockOffset(block)
                        )
                }
                if let cutoff = store.dailyPlanningCutoffEvent(on: date) {
                    CalendarCutoffFence()
                        .frame(width: max(columnWidth - 4, 24))
                        .offset(
                            x: timeGutterWidth + CGFloat(index) * columnWidth + 2,
                            y: CalendarTimelineLayout.offset(
                                for: cutoff.startDate,
                                hourHeight: hourHeight,
                                calendar: calendar
                            ) - 4
                        )
                        .zIndex(2)
                }
            }
        }
    }

    private func blocks(on date: Date) -> [WorkspaceScheduleBlock] {
        let taskBlocks = filteredTasks(on: date).compactMap { entry -> WorkspaceScheduleBlock? in
            guard let start = entry.task.startTime else { return nil }
            guard CalendarTimelineLayout.contains(start, calendar: calendar) else { return nil }
            return WorkspaceScheduleBlock(
                id: entry.task.id,
                title: entry.task.title,
                start: start,
                minutes: max(entry.task.estimatedMinutes, 15),
                color: store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault,
                priority: entry.task.priority,
                placement: entry.task.calendarPlacement,
                taskReference: TaskReference(goalID: entry.goal.id, taskID: entry.task.id),
                detail: store.channel(for: entry.task.channelID)?.title ?? entry.goal.title
            )
        }
        let cutoffID = store.dailyPlanningCutoffEvent(on: date)?.id
        let eventBlocks = store.events(on: date).compactMap { event -> WorkspaceScheduleBlock? in
            guard event.id != cutoffID else { return nil }
            guard CalendarTimelineLayout.contains(event.startDate, calendar: calendar) else { return nil }
            return WorkspaceScheduleBlock(
                id: event.id,
                title: event.title,
                start: event.startDate,
                minutes: max(event.durationMinutes, 15),
                color: color(named: event.colorName),
                priority: nil,
                placement: nil,
                taskReference: nil,
                detail: "日历事件"
            )
        }
        return (taskBlocks + eventBlocks).sorted { $0.start < $1.start }
    }

    private func filteredTasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        store.tasks(on: date, channelID: selectedChannelID)
    }

    private func blockOffset(_ block: WorkspaceScheduleBlock) -> CGFloat {
        CalendarTimelineLayout.offset(for: block.start, hourHeight: hourHeight, calendar: calendar)
    }

    private func blockHeight(minutes: Int) -> CGFloat {
        max(18, CGFloat(minutes) / 60 * hourHeight - 2)
    }

    private func previewResize(blockID: UUID, minutes: Int) {
        guard resizePreviewMinutes[blockID] != minutes else { return }
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            resizePreviewMinutes[blockID] = minutes
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

    private func color(named name: String) -> Color {
        switch name {
        case "orange": .orange
        case "purple": .purple
        case "blue": .blue
        case "red": .red
        default: .gray
        }
    }
}

private struct WorkspaceScheduleBlock: Identifiable {
    let id: UUID
    let title: String
    let start: Date
    let minutes: Int
    let color: Color
    let priority: TaskPriority?
    let placement: TaskCalendarPlacement?
    let taskReference: TaskReference?
    let detail: String
}

private struct CalendarTimeBlock: View {
    let block: WorkspaceScheduleBlock
    let displayedMinutes: Int
    let openTask: () -> Void
    let pinTask: () -> Void
    let resizePreview: (Int) -> Void
    let resizeCommit: (Int) -> Void
    @State private var isHovering = false
    @State private var resizeBaseMinutes: Int?
    @State private var isResizing = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            calendarBackground
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
                if displayedMinutes >= 30 {
                    Text(timeRangeText)
                        .font(.system(size: 9))
                        .opacity(0.78)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)

            if block.placement == .committed {
                CalendarStartFence()
                    .stroke(.white.opacity(0.72), lineWidth: 1.5)
                    .frame(height: 5)
                    .offset(y: -1)

                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(height: 22)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .gesture(resizeGesture)
                    .pointingHandCursor()

                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 3)
                    .opacity(isHovering || isResizing ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .foregroundStyle(block.placement == .committed ? Color.white : block.color)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(WeekflowRoundedRectangle(cornerRadius: 4))
        .background {
            CalendarHoverCardAnchor(
                isPresented: isHovering && !isResizing,
                model: CalendarHoverCardModel(
                    title: block.title,
                    timeRange: timeRangeText,
                    calendarName: "Weekflow 日历",
                    channelName: block.detail,
                    color: block.color,
                    priority: block.priority,
                    isCommitted: block.placement == .committed,
                    isTask: block.taskReference != nil
                ),
                openTask: openTask,
                pinTask: pinTask
            )
        }
        .onHover { isHovering = $0 }
        .pointingHandCursor(coversDescendants: true)
        .clipped()
    }

    @ViewBuilder
    private var calendarBackground: some View {
        if block.placement == .committed {
            block.color.opacity(isHovering || isResizing ? 0.92 : 0.82)
        } else if block.placement == .suggested {
            ZStack {
                block.color.opacity(isHovering ? 0.13 : 0.07)
                DottedCalendarFill(color: block.color.opacity(isHovering ? 0.48 : 0.34))
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 4)
                    .stroke(block.color.opacity(0.32), lineWidth: 1)
            }
        } else {
            block.color.opacity(isHovering ? 0.18 : 0.10)
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if resizeBaseMinutes == nil { resizeBaseMinutes = block.minutes }
                isResizing = true
                let deltaMinutes = Int((value.translation.height / 48 * 60 / 15).rounded()) * 15
                resizePreview(max((resizeBaseMinutes ?? block.minutes) + deltaMinutes, 15))
            }
            .onEnded { value in
                let deltaMinutes = Int((value.translation.height / 48 * 60 / 15).rounded()) * 15
                let finalMinutes = max((resizeBaseMinutes ?? block.minutes) + deltaMinutes, 15)
                resizeBaseMinutes = nil
                isResizing = false
                resizeCommit(finalMinutes)
            }
    }

    private var timeRangeText: String {
        let end = block.start.addingTimeInterval(TimeInterval(displayedMinutes * 60))
        return "\(block.start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct DottedCalendarFill: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            for y in stride(from: 3.0, through: size.height, by: 6.0) {
                for x in stride(from: 3.0, through: size.width, by: 6.0) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}

private struct CalendarStartFence: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let toothWidth: CGFloat = 10
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x < rect.maxX {
            path.addLine(to: CGPoint(x: min(x + toothWidth / 2, rect.maxX), y: rect.minY))
            path.addLine(to: CGPoint(x: min(x + toothWidth, rect.maxX), y: rect.maxY))
            x += toothWidth
        }
        return path
    }
}

private struct MonthWorkspaceCalendar: View {
    @Bindable var store: WeekflowStore
    let month: Date
    let selectedChannelID: String
    private let calendar = Calendar.current
    private let weekTitles = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        GeometryReader { proxy in
            let cellWidth = proxy.size.width / 7
            let headerHeight: CGFloat = 24
            let cellHeight = max((proxy.size.height - headerHeight) / CGFloat(rowCount), 72)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(weekTitles, id: \.self) { title in
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WeekflowPalette.secondaryText)
                            .frame(width: cellWidth, height: headerHeight)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: 7), spacing: 0) {
                    ForEach(monthDates, id: \.self) { date in
                        monthCell(date)
                            .frame(width: cellWidth, height: cellHeight, alignment: .topLeading)
                    }
                }
            }
        }
    }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private var monthDates: [Date] {
        guard let days = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let leading = (calendar.component(.weekday, from: monthStart) + 5) % 7
        let total = leading + days.count
        let cells = Int(ceil(Double(total) / 7)) * 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else { return [] }
        return (0..<cells).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var rowCount: Int { max(monthDates.count / 7, 1) }

    private func monthCell(_ date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
        let entries = store.tasks(on: date, channelID: selectedChannelID)
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(calendar.isDateInToday(date) ? Color.white : WeekflowPalette.primaryText.opacity(isCurrentMonth ? 1 : 0.42))
                .frame(width: 22, height: 22)
                .background(calendar.isDateInToday(date) ? Color.blue : Color.clear, in: Circle())

            ForEach(entries.prefix(3), id: \.task.id) { entry in
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.channel(for: entry.task.channelID)?.color ?? WeekflowPalette.iconDefault)
                        .frame(width: 6, height: 6)
                    Text(entry.task.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
            Rectangle()
                .stroke(WeekflowPalette.border.opacity(0.42), lineWidth: 0.5)
        }
    }
}
