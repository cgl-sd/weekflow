import SwiftUI

struct TaskChannelPopover: View {
    let channels: [TaskChannel]
    let selectedChannelID: String?
    let width: CGFloat
    let select: (String?) -> Void
    let manage: () -> Void
    @State private var searchText = ""

    init(
        channels: [TaskChannel],
        selectedChannelID: String?,
        width: CGFloat = WeekflowLayout.taskChannelPopoverWidth,
        select: @escaping (String?) -> Void,
        manage: @escaping () -> Void
    ) {
        self.channels = channels
        self.selectedChannelID = selectedChannelID
        self.width = width
        self.select = select
        self.manage = manage
    }

    private var filteredChannels: [TaskChannel] {
        guard !searchText.isEmpty else { return channels }
        return channels.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(WeekflowPalette.iconDefault)
                TextField("搜索分类", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .frame(height: 30)
            .padding(.horizontal, 8)
            .background(WeekflowPalette.appBackground, in: WeekflowRoundedRectangle(cornerRadius: 7))
            .padding(6)

            Divider()

            channelList

            Divider()

            WeekflowButton(action: manage) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                    Text("管理分类")
                    Spacer()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WeekflowPalette.objective)
                .frame(height: 32)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
            .padding(4)
        }
        .frame(width: width)
        .frame(maxHeight: WeekflowLayout.taskChannelPopoverMaximumHeight, alignment: .topLeading)
        .background(WeekflowPalette.surface)
    }

    @ViewBuilder
    private var channelList: some View {
        let rows = VStack(spacing: 0) {
            TaskPopoverRow(
                symbol: nil,
                title: "未分类",
                tint: WeekflowPalette.iconDefault,
                selected: selectedChannelID == nil,
                rowHeight: WeekflowLayout.taskChannelPopoverRowHeight
            ) { select(nil) }

            ForEach(filteredChannels) { channel in
                TaskPopoverRow(
                    symbol: channel.resolvedIconName,
                    title: channel.title,
                    tint: channel.color,
                    selected: selectedChannelID == channel.id,
                    rowHeight: WeekflowLayout.taskChannelPopoverRowHeight
                ) { select(channel.id) }
            }
        }
        .padding(.vertical, 4)

        ScrollView { rows }
            .scrollIndicators(.visible)
            .frame(
                height: min(
                    CGFloat(filteredChannels.count + 1) * WeekflowLayout.taskChannelPopoverRowHeight + 8,
                    WeekflowLayout.taskChannelPopoverListHeight
                )
            )
    }
}

struct TaskDatePopover: View {
    let selectedDate: Date
    let selectedDates: [Date]
    let availableWidth: CGFloat
    let exactWidth: CGFloat?
    let exactHeight: CGFloat?
    let showsQuickActions: Bool
    let highlightsToday: Bool
    let highlightsSelectedDate: Bool
    let minimumDate: Date?
    let highlightedRangeStart: Date?
    let highlightedRangeEnd: Date?
    let moveByDays: (Int) -> Void
    let moveToDate: (Date) -> Void
    @State private var displayedMonth: Date

    init(
        selectedDate: Date,
        selectedDates: [Date] = [],
        availableWidth: CGFloat = WeekflowLayout.taskDatePopoverWidth,
        exactWidth: CGFloat? = nil,
        exactHeight: CGFloat? = nil,
        showsQuickActions: Bool = true,
        highlightsToday: Bool = true,
        highlightsSelectedDate: Bool = true,
        minimumDate: Date? = nil,
        highlightedRangeStart: Date? = nil,
        highlightedRangeEnd: Date? = nil,
        moveByDays: @escaping (Int) -> Void,
        moveToDate: @escaping (Date) -> Void
    ) {
        self.selectedDate = selectedDate
        self.selectedDates = selectedDates
        self.availableWidth = availableWidth
        self.exactWidth = exactWidth
        self.exactHeight = exactHeight
        self.showsQuickActions = showsQuickActions
        self.highlightsToday = highlightsToday
        self.highlightsSelectedDate = highlightsSelectedDate
        self.minimumDate = minimumDate
        self.highlightedRangeStart = highlightedRangeStart
        self.highlightedRangeEnd = highlightedRangeEnd
        self.moveByDays = moveByDays
        self.moveToDate = moveToDate
        _displayedMonth = State(initialValue: Self.startOfMonth(containing: selectedDate))
    }

    var body: some View {
        VStack(spacing: 6) {
            if showsQuickActions {
                CompactDateAction(symbol: "sun.max", title: "移动到明天") { moveByDays(1) }
                CompactDateAction(symbol: "calendar.badge.plus", title: "移动到下周") { moveByDays(7) }
                Divider()
            }

            CompactTaskMonthCalendar(
                displayedMonth: $displayedMonth,
                selectedDate: selectedDate,
                selectedDates: selectedDates,
                highlightsToday: highlightsToday,
                highlightsSelectedDate: highlightsSelectedDate,
                minimumDate: minimumDate,
                highlightedRangeStart: highlightedRangeStart,
                highlightedRangeEnd: highlightedRangeEnd,
                select: moveToDate
            )
        }
        .padding(8)
        .frame(
            width: popoverWidth,
            height: exactHeight ?? WeekflowLayout.taskDatePopoverMaximumHeight
        )
        .background(WeekflowPalette.surface)
    }

    private var popoverWidth: CGFloat {
        exactWidth ?? WeekflowLayout.taskDatePopoverWidth(for: availableWidth)
    }

    private static func startOfMonth(containing date: Date) -> Date {
        SystemBusinessCalendar.current.calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

struct CompactDateAction: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
            .foregroundStyle(WeekflowPalette.textSecondary)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 29)
            .background(hovering ? WeekflowPalette.surfaceHover : .clear, in: WeekflowRoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering = $0 }
    }
}

enum CompactCalendarHighlightMetrics {
    static let rangeHeight: CGFloat = 25
    static let singleDayDiameter: CGFloat = 21
    static let rangeOpacity = 0.16
    static let rangeStartOpacity = 0.28
    static let hoverOpacity = 0.20
    static let selectedDayOpacity = 0.52
    static let todayOpacity = 1.0

    static func singleDayOpacity(
        isToday: Bool,
        isSelected: Bool,
        isRangeStart: Bool
    ) -> Double? {
        if isToday { return todayOpacity }
        if isSelected { return selectedDayOpacity }
        if isRangeStart { return rangeStartOpacity }
        return nil
    }
}

enum CompactCalendarHighlightPolicy {
    static func isMultiDayRange(
        start: Date?,
        end: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard let start, let end else { return false }
        return !calendar.isDate(start, inSameDayAs: end)
    }
}

struct CompactTaskMonthCalendar: View {
    @Binding var displayedMonth: Date
    let selectedDate: Date
    let selectedDates: [Date]
    let highlightsToday: Bool
    let highlightsSelectedDate: Bool
    let minimumDate: Date?
    let highlightedRangeStart: Date?
    let highlightedRangeEnd: Date?
    let select: (Date) -> Void
    private let calendar = SystemBusinessCalendar.current.calendar
    private let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]

    init(
        displayedMonth: Binding<Date>,
        selectedDate: Date,
        selectedDates: [Date] = [],
        highlightsToday: Bool,
        highlightsSelectedDate: Bool = true,
        minimumDate: Date?,
        highlightedRangeStart: Date?,
        highlightedRangeEnd: Date?,
        select: @escaping (Date) -> Void
    ) {
        _displayedMonth = displayedMonth
        self.selectedDate = selectedDate
        self.selectedDates = selectedDates
        self.highlightsToday = highlightsToday
        self.highlightsSelectedDate = highlightsSelectedDate
        self.minimumDate = minimumDate
        self.highlightedRangeStart = highlightedRangeStart
        self.highlightedRangeEnd = highlightedRangeEnd
        self.select = select
    }

    private var gridDates: [Date] {
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let mondayOffset = (weekday + 5) % 7
        let gridStart = calendar.date(byAdding: .day, value: -mondayOffset, to: displayedMonth) ?? displayedMonth
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private var calendarRows: [[Date]] {
        stride(from: 0, to: gridDates.count, by: 7).map { startIndex in
            Array(gridDates[startIndex..<min(startIndex + 7, gridDates.count)])
        }
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                monthStepButton(symbol: "chevron.left", offset: -1)
                Spacer()
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                Spacer()
                monthStepButton(symbol: "chevron.right", offset: 1)
            }

            VStack(spacing: 3) {
                HStack(spacing: 2) {
                    ForEach(weekdayTitles, id: \.self) { title in
                        Text(title)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textMuted)
                            .frame(maxWidth: .infinity, minHeight: 16)
                    }
                }

                ForEach(Array(calendarRows.enumerated()), id: \.offset) { _, rowDates in
                    ZStack {
                        weekRangeBackground(for: rowDates)

                        HStack(spacing: 2) {
                            ForEach(rowDates, id: \.self) { date in
                                let isSelectable = isSelectable(date)
                                WeekflowButton {
                                    select(date)
                                } label: {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.system(
                                            size: 11,
                                            weight: isSelected(date) ? .semibold : .regular
                                        ))
                                        .foregroundStyle(dayForeground(for: date))
                                        .frame(maxWidth: .infinity, minHeight: 25)
                                        .background(dayBackground(for: date))
                                }
                                .buttonStyle(.plain)
                                .modifier(CompactCalendarDayHighlight(isEnabled: isSelectable))
                                .disabled(!isSelectable)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isSelected(_ date: Date) -> Bool {
        selectedDates.contains { calendar.isDate($0, inSameDayAs: date) }
            || (highlightsSelectedDate && calendar.isDate(date, inSameDayAs: selectedDate))
    }

    private func isInDisplayedMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    private func isSelectable(_ date: Date) -> Bool {
        guard let minimumDate else { return true }
        return calendar.startOfDay(for: date) >= calendar.startOfDay(for: minimumDate)
    }

    private func isInHighlightedRange(_ date: Date) -> Bool {
        guard let highlightedRangeStart, let highlightedRangeEnd else { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: highlightedRangeStart)
        let end = calendar.startOfDay(for: highlightedRangeEnd)
        return day >= min(start, end) && day <= max(start, end)
    }

    private func isRangeStart(_ date: Date) -> Bool {
        guard let highlightedRangeStart else { return false }
        return calendar.isDate(date, inSameDayAs: highlightedRangeStart)
    }

    private func dayForeground(for date: Date) -> Color {
        if !isSelectable(date) { return WeekflowPalette.textMuted.opacity(0.30) }
        if isSelected(date) || (highlightsToday && calendar.isDateInToday(date)) {
            return .white
        }
        return isInDisplayedMonth(date) ? WeekflowPalette.textSecondary : WeekflowPalette.textMuted.opacity(0.55)
    }

    @ViewBuilder
    private func dayBackground(for date: Date) -> some View {
        if let opacity = CompactCalendarHighlightMetrics.singleDayOpacity(
            isToday: highlightsToday && calendar.isDateInToday(date),
            isSelected: isSelected(date),
            isRangeStart: isRangeStart(date)
        ) {
            singleDayHighlight(opacity: opacity)
        }
    }

    private func singleDayHighlight(opacity: Double) -> some View {
        Circle()
            .fill(WeekflowPalette.objective.opacity(opacity))
            .frame(
                width: CompactCalendarHighlightMetrics.singleDayDiameter,
                height: CompactCalendarHighlightMetrics.singleDayDiameter
            )
    }

    @ViewBuilder
    private func weekRangeBackground(for rowDates: [Date]) -> some View {
        if CompactCalendarHighlightPolicy.isMultiDayRange(
            start: highlightedRangeStart,
            end: highlightedRangeEnd,
            calendar: calendar
        ) {
            GeometryReader { proxy in
                let highlightedIndices = rowDates.indices.filter {
                    isInHighlightedRange(rowDates[$0])
                }
                if let firstIndex = highlightedIndices.first,
                   let lastIndex = highlightedIndices.last {
                    let columnSpacing: CGFloat = 2
                    let columnWidth = (proxy.size.width - columnSpacing * 6) / 7
                    let columnStep = columnWidth + columnSpacing
                    let firstCenter = columnWidth / 2 + CGFloat(firstIndex) * columnStep
                    let lastCenter = columnWidth / 2 + CGFloat(lastIndex) * columnStep

                    Capsule()
                        .fill(WeekflowPalette.objective.opacity(
                            CompactCalendarHighlightMetrics.rangeOpacity
                        ))
                        .frame(
                            width: lastCenter - firstCenter
                                + CompactCalendarHighlightMetrics.rangeHeight,
                            height: CompactCalendarHighlightMetrics.rangeHeight
                        )
                        .position(x: (firstCenter + lastCenter) / 2, y: proxy.size.height / 2)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func monthStepButton(symbol: String, offset: Int) -> some View {
        WeekflowButton {
            displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WeekflowPalette.textMuted)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 5))
    }
}

struct CompactCalendarDayHighlight: ViewModifier {
    let isEnabled: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                if isEnabled && hovering {
                    Circle()
                        .fill(WeekflowPalette.objective.opacity(
                            CompactCalendarHighlightMetrics.hoverOpacity
                        ))
                        .frame(
                            width: CompactCalendarHighlightMetrics.singleDayDiameter,
                            height: CompactCalendarHighlightMetrics.singleDayDiameter
                        )
                }
            }
            .pointingHandCursor()
            .onHover { hovering = isEnabled && $0 }
    }
}

struct TaskPriorityPopover: View {
    let selectedPriority: TaskPriority
    let width: CGFloat
    let select: (TaskPriority) -> Void

    init(
        selectedPriority: TaskPriority,
        width: CGFloat = WeekflowLayout.taskPriorityPopoverWidth,
        select: @escaping (TaskPriority) -> Void
    ) {
        self.selectedPriority = selectedPriority
        self.width = width
        self.select = select
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("今日优先级")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                Spacer()
            }
            .frame(height: WeekflowLayout.taskPriorityPopoverHeaderHeight)
            .padding(.horizontal, 10)

            Divider()

            ForEach(TaskPriority.displayOrder) { priority in
                TaskPriorityTextRow(priority: priority, selected: selectedPriority == priority) {
                    select(priority)
                }
            }
        }
        .padding(6)
        .frame(width: width)
        .frame(maxHeight: WeekflowLayout.taskPriorityPopoverMaximumHeight, alignment: .topLeading)
        .background(WeekflowPalette.surface)
    }
}

struct TaskPriorityTextRow: View {
    let priority: TaskPriority
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: priority.flagSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(priority.flagColor)
                    .frame(width: 16)
                Text(priority == .none ? "无优先级" : priority.label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textSecondary)
                        .frame(width: 16)
                } else {
                    Text("\(priority.sortRank + 1)")
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(WeekflowPalette.textMuted)
                        .frame(width: 16)
                }
            }
            .frame(height: WeekflowLayout.taskPriorityPopoverRowHeight)
            .padding(.horizontal, 10)
            .background(
                hovering || selected ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering = $0 }
    }
}

struct TaskTimerInlinePanel: View {
    @Bindable var store: WeekflowStore
    let goalID: UUID
    let taskID: UUID
    let estimatedMinutes: Int
    @Binding var showsEstimatedDurationPopover: Bool
    let toggleEstimatedDurationPopover: () -> Void
    @State private var isEstimatedHovering = false

    init(
        store: WeekflowStore,
        goalID: UUID,
        taskID: UUID,
        estimatedMinutes: Int,
        showsEstimatedDurationPopover: Binding<Bool> = .constant(false),
        toggleEstimatedDurationPopover: @escaping () -> Void = {}
    ) {
        self.store = store
        self.goalID = goalID
        self.taskID = taskID
        self.estimatedMinutes = estimatedMinutes
        _showsEstimatedDurationPopover = showsEstimatedDurationPopover
        self.toggleEstimatedDurationPopover = toggleEstimatedDurationPopover
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 6) {
                    WeekflowButton {
                        store.toggleTaskTimer(goalID: goalID, taskID: taskID, now: context.date)
                    } label: {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: WeekflowLayout.taskPopoverIconSize, weight: .semibold))
                            .foregroundStyle(WeekflowPalette.textMuted)
                            .frame(
                                width: WeekflowLayout.taskTimerControlSize,
                                height: WeekflowLayout.taskTimerControlSize
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .help(isRunning ? "暂停计时" : "开始计时")

                    Spacer(minLength: 8)

                    HStack(spacing: 10) {
                        timerColumn(title: "实际", value: actualText(at: context.date))
                        estimatedDurationButton
                    }
                }
                .padding(.horizontal, WeekflowLayout.taskTimerPanelInnerHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: WeekflowLayout.taskTimerInlinePanelHeight)
                .task(id: minuteBucket(at: context.date)) {
                    store.synchronizeActiveTaskTimer(at: context.date)
                }
            }

        }
        .accessibilityLabel("任务计时")
    }

    private func timerColumn(title: String, value: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(WeekflowPalette.textMuted)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(WeekflowPalette.textPrimary)
        }
        .frame(
            minWidth: WeekflowLayout.taskTimerColumnWidth,
            maxWidth: WeekflowLayout.taskTimerColumnWidth,
            minHeight: 28,
            alignment: .center
        )
    }

    private var estimatedDurationButton: some View {
        WeekflowButton(action: toggleEstimatedDurationPopover) {
            VStack(alignment: .center, spacing: 2) {
                Text("预计")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
                Text(TaskTimeDisplay.estimated(minutes: estimatedMinutes))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WeekflowPalette.textPrimary)
            }
            .frame(
                minWidth: WeekflowLayout.taskTimerColumnWidth,
                maxWidth: WeekflowLayout.taskTimerColumnWidth,
                minHeight: 28,
                alignment: .center
            )
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .anchorPreference(
            key: TaskDurationMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [.estimatedDurationButton(taskID): anchor]
        }
        .pointingHandCursor()
        .background(
            isEstimatedHovering || showsEstimatedDurationPopover
                ? WeekflowPalette.surfaceHover
                : .clear,
            in: WeekflowRoundedRectangle(cornerRadius: 5)
        )
        .onHover { isEstimatedHovering = $0 }
        .accessibilityLabel("修改预计时间")
    }

    private func actualText(at date: Date) -> String {
        TaskTimeDisplay.actual(
            minutes: store.liveTaskActualMinutes(goalID: goalID, taskID: taskID, at: date),
            estimatedMinutes: estimatedMinutes
        )
    }

    private var isRunning: Bool {
        store.isTaskTimerRunning(goalID: goalID, taskID: taskID)
    }

    private func minuteBucket(at date: Date) -> Int {
        guard let startedAt = store.taskTimerStartedAt(goalID: goalID, taskID: taskID) else { return -1 }
        return max(Int(date.timeIntervalSince(startedAt)) / 60, 0)
    }
}

struct TaskPopoverInteractiveHighlight: ViewModifier {
    let cornerRadius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                hovering ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: cornerRadius)
            )
            .pointingHandCursor()
            .onHover { hovering = $0 }
    }
}

struct TaskPopoverRow: View {
    let symbol: String?
    let title: String
    let tint: Color
    var selected = false
    var rowHeight: CGFloat = 40
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: 18)
                }
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isEnabled ? WeekflowPalette.textPrimary : WeekflowPalette.textMuted)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textSecondary)
                }
            }
            .frame(height: rowHeight)
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .background(
                hovering || focused ? WeekflowPalette.surfaceHover : (selected ? WeekflowPalette.selected.opacity(0.30) : .clear),
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .focused($focused)
        .opacity(isEnabled ? 1 : 0.52)
        .onHover { hovering = $0 }
    }
}
