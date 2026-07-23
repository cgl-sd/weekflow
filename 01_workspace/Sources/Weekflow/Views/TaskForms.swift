import SwiftUI

/// The sidebar action creates a task first, then lets the user choose which active weekly goal owns it.
struct QuickTaskFormView: View {
    @Bindable var store: WeekflowStore
    let onDismiss: () -> Void
    @State private var selectedGoalID: WeeklyGoal.ID?
    @State private var title = ""
    @State private var description = ""
    @State private var plannedDate = Date.now
    @State private var keepInTaskPool = true
    @State private var executionWeekStart: Date?
    @State private var milestoneID: Milestone.ID?
    @State private var hasDueDate = false
    @State private var dueDate = Date.now
    @State private var minutes = 0
    @State private var selectedStartTime: Date?
    @State private var selectedStartTimeIsEndOfDay = false
    @State private var selectedChannelID: String?
    @State private var selectedPriority: TaskPriority = .none
    @State private var sourceURL = ""
    @State private var showingDatePopover = false
    @State private var showingTimePopover = false
    @State private var showingStartTimePopover = false
    @State private var showingChannelPopover = false
    @State private var showingGoalPopover = false
    @State private var showingPriorityPopover = false
    @State private var showingChannelSettings = false
    @State private var channelSearch = ""
    @FocusState private var isTitleFocused: Bool

    init(
        store: WeekflowStore,
        initialPlannedDate: Date? = nil,
        initialStartTime: Date? = nil,
        defaultMinutes: Int = 0,
        defaultChannelID: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onDismiss = onDismiss
        _selectedGoalID = State(initialValue: nil)
        _plannedDate = State(initialValue: initialPlannedDate ?? Date.now)
        _keepInTaskPool = State(initialValue: initialPlannedDate == nil)
        _minutes = State(initialValue: max(defaultMinutes, 0))
        _selectedStartTime = State(initialValue: initialStartTime)
        _selectedChannelID = State(initialValue: defaultChannelID)
    }

    private var selectedChannel: TaskChannel? { store.channel(for: selectedChannelID) }
    private var selectedGoal: WeeklyGoal? { store.activeGoals.first { $0.id == selectedGoalID } }
    private var dateLabel: String {
        if executionWeekStart != nil { return "下周内" }
        if keepInTaskPool { return "以后" }
        if SystemBusinessCalendar.current.calendar.isDateInToday(plannedDate) { return "今日" }
        return plannedDate.formatted(.dateTime.month(.abbreviated).day())
    }
    private var timeLabel: String {
        minutes == 0 ? TaskTimeDisplay.unsetEstimated : minutes.hourMinuteText
    }
    private var startTimeLabel: String? {
        if selectedStartTimeIsEndOfDay { return "24:00" }
        return selectedStartTime?.formatted(
            .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        )
    }
    private var priorityColor: Color {
        switch selectedPriority { case .must: .red; case .should: .purple; case .later: .gray; case .none: WeekflowPalette.secondaryText }
    }
    private var visibleChannels: [TaskChannel] {
        channelSearch.isEmpty ? store.activeChannels : store.activeChannels.filter { $0.title.localizedCaseInsensitiveContains(channelSearch) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("添加任务...", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($isTitleFocused)
                .submitLabel(.done)
                .onSubmit { saveTask(openDetails: false) }
                .help("按 Return 创建任务；按 Command-Return 创建并打开详情")
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Spacer(minLength: 14)

            HStack(spacing: 7) {
                Spacer()

                ComposerControl(tooltip: "设置开始日期", isExpanded: showingDatePopover, action: { showingDatePopover.toggle() }) {
                    HStack(spacing: 5) {
                        ComposerSymbol("calendar")
                        Text(dateLabel)
                    }
                }
                .popover(isPresented: $showingDatePopover, arrowEdge: .bottom) {
                    ComposerDatePicker(
                        plannedDate: $plannedDate,
                        keepInTaskPool: $keepInTaskPool,
                        executionWeekStart: $executionWeekStart
                    )
                }

                ComposerControl(tooltip: "设置起始时间", isExpanded: showingStartTimePopover, action: { showingStartTimePopover.toggle() }) {
                    HStack(spacing: 5) {
                        ComposerSymbol("clock")
                        if let startTimeLabel {
                            Text(startTimeLabel)
                                .monospacedDigit()
                        }
                    }
                }
                .popover(isPresented: $showingStartTimePopover, arrowEdge: .bottom) {
                    ScrollClockTimePopover(
                        selection: selectedStartTime,
                        anchorDate: plannedDate,
                        minuteRange: 360...1_440,
                        minuteStep: 30
                    ) { time in
                        selectedStartTime = time
                        selectedStartTimeIsEndOfDay = time.map {
                            SystemBusinessCalendar.current.calendar.startOfDay(for: $0) > SystemBusinessCalendar.current.calendar.startOfDay(for: plannedDate)
                        } ?? false
                    }
                }

                ComposerControl(tooltip: "设置预计时长", isExpanded: showingTimePopover, action: { showingTimePopover.toggle() }) {
                    HStack(spacing: 5) {
                        ComposerSymbol("hourglass")
                        Text(timeLabel)
                    }
                }
                .popover(isPresented: $showingTimePopover, arrowEdge: .bottom) {
                    ScrollDurationPopover(
                        minutes: $minutes,
                        range: 0...240,
                        step: 15,
                        allowsZero: false,
                        title: "预计时长",
                        width: WeekflowLayout.composerDurationPopoverWidth,
                        height: WeekflowLayout.composerDurationPopoverMaximumHeight,
                        presetChoices: [5, 10, 15, 20, 25, 30, 45, 60, 75, 90, 120, 180, 240]
                    )
                }

                ComposerControl(tooltip: "分配频道", isExpanded: showingChannelPopover, action: { showingChannelPopover.toggle() }) {
                    HStack(spacing: 5) {
                        ComposerSymbol(selectedChannel?.isPersonal == true ? "lock" : "number")
                            .foregroundStyle(selectedChannel?.color ?? WeekflowPalette.secondaryText)
                        if let selectedChannel {
                            Text(selectedChannel.title)
                        }
                    }
                }
                .popover(isPresented: $showingChannelPopover, arrowEdge: .bottom) {
                    ComposerChannelPicker(channels: visibleChannels, selection: $selectedChannelID, query: $channelSearch) {
                        showingChannelPopover = false
                        showingChannelSettings = true
                    }
                }

                ComposerControl(tooltip: "关联周目标", isExpanded: showingGoalPopover, action: { showingGoalPopover.toggle() }) {
                    HStack(spacing: 5) {
                        ComposerSymbol("target")
                        if let selectedGoal {
                            Text(selectedGoal.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 76, alignment: .leading)
                        }
                    }
                }
                .popover(isPresented: $showingGoalPopover, arrowEdge: .bottom) {
                    ComposerGoalPicker(goals: store.activeGoals, selection: $selectedGoalID)
                }

                ComposerControl(tooltip: "设置每日优先级", isExpanded: showingPriorityPopover, action: { showingPriorityPopover.toggle() }) {
                    ComposerSymbol(selectedPriority == .none ? "flag" : "flag.fill")
                        .foregroundStyle(priorityColor)
                }
                .popover(isPresented: $showingPriorityPopover, arrowEdge: .bottom) {
                    ComposerPriorityPicker(selection: $selectedPriority)
                }

            }
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(WeekflowPalette.secondaryText)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            WeekflowButton("") { saveTask(openDetails: true) }
                .keyboardShortcut(.return, modifiers: [.command])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .frame(width: 570, height: 110)
        .background {
            WeekflowRoundedRectangle(cornerRadius: 7)
                .fill(WeekflowPalette.button)
                .overlay(WeekflowRoundedRectangle(cornerRadius: 7).stroke(WeekflowPalette.border, lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.19), radius: 22, y: 9)
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 10))
        .onChange(of: selectedGoalID) { milestoneID = nil }
        .onAppear { isTitleFocused = true }
        .onExitCommand { onDismiss() }
        .sheet(isPresented: $showingChannelSettings) { ChannelSettingsView(store: store) }
    }

    private func saveTask(openDetails: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let destinationGoalID = store.quickCaptureGoalID(preferred: selectedGoalID) else { return }
        let source = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskID = store.addTask(
            to: destinationGoalID,
            title: cleanTitle,
            plannedDate: keepInTaskPool ? nil : plannedDate,
            dueDate: hasDueDate ? dueDate : nil,
            minutes: minutes,
            notes: description.trimmingCharacters(in: .whitespacesAndNewlines),
            milestoneID: milestoneID,
            startTime: normalizedStartTime,
            executionWeekStart: executionWeekStart,
            channelID: selectedChannelID,
            priority: selectedPriority,
            sourceType: source.isEmpty ? (keepInTaskPool ? .backlog : .native) : .url,
            sourceURL: source.isEmpty ? nil : source,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if openDetails, let taskID {
            store.highlightedTask = TaskReference(goalID: destinationGoalID, taskID: taskID)
            onDismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                CommandRouter.shared.send(.openHighlightedTask)
            }
            return
        }
        onDismiss()
    }

    private var normalizedStartTime: Date? {
        guard !keepInTaskPool, let selectedStartTime else { return nil }
        let calendar = SystemBusinessCalendar.current.calendar
        if selectedStartTimeIsEndOfDay {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: plannedDate))
        }
        let components = calendar.dateComponents([.hour, .minute], from: selectedStartTime)
        return calendar.date(
            bySettingHour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: 0,
            of: plannedDate
        )
    }

}

struct ComposerControl<Label: View>: View {
    let tooltip: String
    let isExpanded: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var isHovering = false

    var body: some View {
        WeekflowButton {
            isHovering = false
            action()
        } label: {
            label()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: WeekflowLayout.composerControlHeight)
                .background(isHovering ? WeekflowPalette.selected.opacity(0.44) : .clear, in: WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovering = hovering }
        }
        .background {
            FloatingTooltipAnchor(
                isPresented: isHovering && !isExpanded,
                text: tooltip,
                shortcut: nil
            )
        }
    }
}

struct ComposerSymbol: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        Image(systemName: name)
            .frame(
                width: WeekflowLayout.composerIconSize,
                height: WeekflowLayout.composerIconSize,
                alignment: .center
            )
    }
}

struct ComposerDatePicker: View {
    @Binding var plannedDate: Date
    @Binding var keepInTaskPool: Bool
    @Binding var executionWeekStart: Date?
    @Environment(\.businessCalendar) private var businessCalendar
    private var calendar: Calendar { businessCalendar.calendar }
    @State private var displayedMonth = Date.now
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Text("以后")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 5)
                quickDateRow("T", "明天", days: 1, color: .blue)
                WeekflowButton(action: chooseNextWeek) {
                    quickLabel("W", "下周内", color: .green)
                }
                .buttonStyle(.plain)
                quickDateRow("M", "下月内", days: 30, color: .mint)
                WeekflowButton { clearSchedule() } label: { quickLabel("S", "以后再做", color: .gray) }
                    .buttonStyle(.plain)
                WeekflowButton { clearSchedule() } label: { quickLabel("N", "不安排", color: .secondary) }
                    .buttonStyle(.plain)
                Divider().padding(.top, 5)
                Text("选择确切日期")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                compactCalendar
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
        }
        .scrollIndicators(.visible)
        .frame(width: WeekflowLayout.composerDatePopoverWidth)
        .frame(maxHeight: WeekflowLayout.composerDatePopoverMaximumHeight, alignment: .topLeading)
        .onAppear { displayedMonth = monthStart(for: plannedDate) }
    }

    private var compactCalendar: some View {
        VStack(spacing: 6) {
            HStack {
                WeekflowButton { shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(displayedMonth.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                WeekflowButton { shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .frame(height: 28)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 10))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 18)
                }
                ForEach(monthDates, id: \.self) { date in
                    calendarDay(date)
                }
            }
        }
    }

    private var monthDates: [Date] {
        let start = monthStart(for: displayedMonth)
        let weekday = calendar.component(.weekday, from: start)
        let daysBeforeMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -daysBeforeMonday, to: start) else { return [] }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func calendarDay(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: plannedDate) && !keepInTaskPool
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        return WeekflowButton {
            plannedDate = date
            keepInTaskPool = false
            executionWeekStart = nil
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : (isCurrentMonth ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText.opacity(0.42)))
                .frame(maxWidth: .infinity, minHeight: 23)
                .background(isSelected ? WeekflowPalette.objective : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func shiftMonth(by value: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
    }

    private func quickDateRow(_ letter: String, _ title: String, days: Int, color: Color) -> some View {
        WeekflowButton {
            plannedDate = calendar.date(byAdding: .day, value: days, to: .now) ?? .now
            keepInTaskPool = false
            executionWeekStart = nil
        } label: { quickLabel(letter, title, color: color) }
        .buttonStyle(.plain)
    }

    private func chooseNextWeek() {
        let today = calendar.startOfDay(for: .now)
        let daysUntilNextMonday = 8 - calendar.component(.weekday, from: today)
        executionWeekStart = calendar.date(byAdding: .day, value: daysUntilNextMonday, to: today)
        keepInTaskPool = true
    }

    private func clearSchedule() {
        keepInTaskPool = true
        executionWeekStart = nil
    }

    private func quickLabel(_ letter: String, _ title: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Text(letter)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(color, in: Circle())
            Text(title).font(.system(size: 13))
            Spacer()
        }
        .foregroundStyle(WeekflowPalette.primaryText)
        .padding(.horizontal, 14)
        .frame(height: 27)
        .contentShape(Rectangle())
    }
}

struct ComposerChannelPicker: View {
    let channels: [TaskChannel]
    @Binding var selection: String?
    @Binding var query: String
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("分配频道")
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            TextField("搜索...", text: $query)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 34)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ComposerChannelRow(
                        id: nil,
                        title: "未分类",
                        color: .gray,
                        selection: $selection
                    )
                    ForEach(channels) { channel in
                        ComposerChannelRow(
                            id: channel.id,
                            title: channel.title,
                            color: channel.color,
                            selection: $selection
                        )
                    }
                }
                .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: WeekflowLayout.composerChannelPopoverListMaximumHeight)
            Divider()
            WeekflowButton("管理频道", action: onManage)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.objective)
                .padding(10)
        }
        .frame(width: WeekflowLayout.composerChannelPopoverWidth)
        .frame(maxHeight: WeekflowLayout.composerChannelPopoverMaximumHeight, alignment: .topLeading)
    }
}

struct ComposerChannelRow: View {
    let id: String?
    let title: String
    let color: Color
    @Binding var selection: String?
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        WeekflowButton { selection = id } label: {
            HStack(spacing: 9) {
                Image(systemName: "number").foregroundStyle(color)
                Text(title).lineLimit(1)
                Spacer()
                if selection == id { Image(systemName: "checkmark") }
            }
            .font(.system(size: 13))
            .foregroundStyle(isEnabled ? WeekflowPalette.primaryText : WeekflowPalette.textMuted)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
            .background(
                hovering || focused ? WeekflowPalette.surfaceHover : (selection == id ? WeekflowPalette.selected.opacity(0.42) : .clear),
                in: WeekflowRoundedRectangle(cornerRadius: 5)
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

struct ComposerGoalPicker: View {
    let goals: [WeeklyGoal]
    @Binding var selection: WeeklyGoal.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("关联每周目标")
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(10)
            if goals.isEmpty {
                Text("当前没有可用的周目标")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(goals) { goal in
                            ComposerGoalRow(goal: goal, selection: $selection)
                        }
                    }
                    .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: WeekflowLayout.composerGoalPopoverListMaximumHeight)
            }
        }
        .frame(width: WeekflowLayout.composerGoalPopoverWidth)
        .frame(maxHeight: WeekflowLayout.composerGoalPopoverMaximumHeight, alignment: .topLeading)
    }
}

struct ComposerGoalRow: View {
    let goal: WeeklyGoal
    @Binding var selection: WeeklyGoal.ID?
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        WeekflowButton { selection = goal.id } label: {
            HStack {
                Image(systemName: "target")
                Text(goal.title).lineLimit(1)
                Spacer()
                if selection == goal.id { Image(systemName: "checkmark") }
            }
            .font(.system(size: 12))
            .foregroundStyle(isEnabled ? WeekflowPalette.primaryText : WeekflowPalette.textMuted)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 31, alignment: .leading)
            .background(
                hovering || focused ? WeekflowPalette.surfaceHover : (selection == goal.id ? WeekflowPalette.selected.opacity(0.42) : .clear),
                in: WeekflowRoundedRectangle(cornerRadius: 5)
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

struct ComposerPriorityPicker: View {
    @Binding var selection: TaskPriority

    private let rows: [(TaskPriority, String, Color)] = [
        (.must, "紧急", .red),
        (.should, "优先", .purple),
        (.none, "普通", .primary),
        (.later, "低优先级", .gray)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("每日优先级")
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 5)
            ForEach(rows, id: \.0) { row in
                WeekflowButton { selection = row.0 } label: {
                    HStack(spacing: 9) {
                        Image(systemName: row.0 == .none ? "flag" : "flag.fill").foregroundStyle(row.2)
                        Text(row.1)
                        Spacer()
                        if selection == row.0 { Image(systemName: "checkmark") }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(WeekflowPalette.primaryText)
                    .padding(.horizontal, 14)
                    .frame(height: 25)
                    .background(selection == row.0 ? WeekflowPalette.selected.opacity(0.42) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: WeekflowLayout.composerPriorityPopoverWidth)
        .frame(maxHeight: WeekflowLayout.composerPriorityPopoverMaximumHeight, alignment: .topLeading)
        .padding(.bottom, 4)
    }
}
