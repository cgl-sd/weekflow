import SwiftUI

enum WorkspaceToolbarMenu: Hashable {
    case date
    case filter
    case view
    case calendarOptions
}

struct WorkspaceToolbarMenuAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceToolbarMenu: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [WorkspaceToolbarMenu: Anchor<CGRect>],
        nextValue: () -> [WorkspaceToolbarMenu: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct WorkspaceToolbar: View {
    @Bindable var store: WeekflowStore
    let destination: AppDestination
    let dailyPlanningStep: Int
    @Binding var workspaceView: WorkspaceView
    @Binding var homeVisibleDayIndex: Double
    @Binding var dailyPlanningDate: Date
    @Binding var weeklyReferenceDate: Date
    @Binding var weeklyPlanningPresentation: WeeklyPlanningPresentation
    @Binding var selectedTaskChannel: String
    @Binding var presentedMenu: WorkspaceToolbarMenu?

    private let calendar = Calendar.current

    private var selectedDate: Date {
        if destination == .dailyPlanning {
            return calendar.startOfDay(for: dailyPlanningDate)
        }
        if destination == .weeklyPlanning || destination == .weeklyReview {
            return calendar.startOfDay(for: weeklyReferenceDate)
        }
        return calendar.date(
            byAdding: .day,
            value: Int(homeVisibleDayIndex.rounded()) - 7,
            to: calendar.startOfDay(for: .now)
        ) ?? .now
    }

    private var navigationStep: Double {
        switch workspaceView {
        case .board, .dayCalendar: 1
        case .threeDayCalendar: 3
        case .weekdaysCalendar: 5
        case .weekCalendar: 7
        case .monthCalendar: 7
        }
    }

    private var contextualDateTitle: String? {
        if destination == .dailyPlanning {
            if calendar.isDateInToday(selectedDate) { return "今日" }
            if calendar.isDateInTomorrow(selectedDate) { return "明天" }
            return nil
        }
        if destination == .weeklyPlanning || destination == .weeklyReview {
            return WeeklyDateNavigation.isCurrentWeek(selectedDate)
                ? "本周"
                : Date.weekRangeLabel(for: selectedDate)
        }
        return Self.contextualDateTitle(
            for: destination,
            dailyPlanningStep: dailyPlanningStep
        )
    }

    static func contextualDateTitle(
        for destination: AppDestination,
        dailyPlanningStep: Int
    ) -> String? {
        switch destination {
        case .home:
            nil
        case .dailyShutdown:
            "今日"
        case .dailyPlanning:
            dailyPlanningStep >= 1 ? "明天" : "今日"
        case .weeklyPlanning, .weeklyReview:
            "本周"
        case .focus, .archive, .trash:
            nil
        }
    }

    private var showsViewSwitcher: Bool { destination == .home }
    private var showsCalendarNavigation: Bool { destination == .home && workspaceView.isCalendar }
    private var showsPlanningCalendar: Bool {
        destination == .dailyPlanning && dailyPlanningStep == 0
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsCalendarNavigation {
                ToolbarIconButton(systemImage: "chevron.left", help: "向前") {
                    homeVisibleDayIndex = max(0, homeVisibleDayIndex - navigationStep)
                }
                ToolbarIconButton(systemImage: "chevron.right", help: "向后") {
                    homeVisibleDayIndex = min(13, homeVisibleDayIndex + navigationStep)
                }
            }

            if destination == .archive || destination == .trash {
                ToolbarStaticPill(
                    title: destination == .archive ? "已归档" : "垃圾桶",
                    systemImage: destination == .archive ? "archivebox" : "trash"
                )
            } else {
                DateJumpButton(
                    date: selectedDate,
                    isToday: isCurrentDatePeriod,
                    calendarMode: workspaceView,
                    forcedTitle: contextualDateTitle,
                    allowsReset: destination == .home
                        || destination == .dailyPlanning
                        || destination == .weeklyPlanning
                        || destination == .weeklyReview,
                    resetHelp: destination == .weeklyPlanning || destination == .weeklyReview
                        ? "回到本周"
                        : "回到今天"
                ) {
                    toggleMenu(.date)
                } resetToday: {
                    if destination == .dailyPlanning {
                        dailyPlanningDate = calendar.startOfDay(for: .now)
                    } else if destination == .weeklyPlanning || destination == .weeklyReview {
                        weeklyReferenceDate = calendar.startOfDay(for: .now)
                    } else {
                        homeVisibleDayIndex = 7
                    }
                }
                .anchorPreference(
                    key: WorkspaceToolbarMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) {
                    [.date: $0]
                }
            }

            if workspaceView.isCalendar && destination == .home {
                ToolbarPillButton(
                    title: "日历",
                    systemImage: "line.3.horizontal.decrease"
                ) {}
                .help("日历工具")
            } else {
                ToolbarPillButton(
                    title: "筛选",
                    systemImage: "line.3.horizontal.decrease"
                ) {
                    toggleMenu(.filter)
                }
                .help("按频道筛选任务")
                .anchorPreference(
                    key: WorkspaceToolbarMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) {
                    [.filter: $0]
                }
            }

            Spacer()

            if destination == .weeklyPlanning {
                ToolbarPillButton(
                    title: weeklyPlanningPresentation == .sections ? "关系图" : "分区图",
                    systemImage: weeklyPlanningPresentation == .sections
                        ? WeeklyPlanningPresentation.relationships.symbol
                        : WeeklyPlanningPresentation.sections.symbol,
                    fixedWidth: 96
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        weeklyPlanningPresentation = weeklyPlanningPresentation == .sections
                            ? .relationships
                            : .sections
                    }
                }
                .help(weeklyPlanningPresentation == .sections ? "切换到本周关系图" : "返回分区图")
            }

            if showsPlanningCalendar {
                ToolbarPillButton(title: "日历", systemImage: "calendar") {
                    toggleMenu(.calendarOptions)
                }
                .help("日历显示设置")
                .anchorPreference(
                    key: WorkspaceToolbarMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) {
                    [.calendarOptions: $0]
                }
            }

            if showsViewSwitcher {
                ToolbarPillButton(title: workspaceView.rawValue, systemImage: "rectangle.3.group") {
                    toggleMenu(.view)
                }
                .help("切换工作区视图")
                .anchorPreference(
                    key: WorkspaceToolbarMenuAnchorPreferenceKey.self,
                    value: .bounds
                ) {
                    [.view: $0]
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 17)
        .padding(.bottom, 4)
        .background(WeekflowPalette.canvas)
    }

    private var isCurrentDatePeriod: Bool {
        if destination == .weeklyPlanning || destination == .weeklyReview {
            return WeeklyDateNavigation.isCurrentWeek(selectedDate)
        }
        return calendar.isDateInToday(selectedDate)
    }

    private func toggleMenu(_ menu: WorkspaceToolbarMenu) {
        withAnimation(.easeOut(duration: 0.12)) {
            presentedMenu = presentedMenu == menu ? nil : menu
        }
    }
}

struct WorkspaceToolbarMenuLayer: View {
    @Bindable var store: WeekflowStore
    @Binding var presentedMenu: WorkspaceToolbarMenu?
    @Binding var homeVisibleDayIndex: Double
    @Binding var dailyPlanningDate: Date
    @Binding var weeklyReferenceDate: Date
    @Binding var selectedTaskChannel: String
    let destination: AppDestination
    @Binding var workspaceView: WorkspaceView
    let visibleDayCount: Int
    let anchors: [WorkspaceToolbarMenu: Anchor<CGRect>]
    @AppStorage("weekflow.calendar.showsDailyCutoff")
    private var showsDailyCutoff = true

    var body: some View {
        GeometryReader { proxy in
            if let presentedMenu,
               let activeAnchor = anchors[presentedMenu] {
                let activeFrame = proxy[activeAnchor]
                let menuSize = size(for: presentedMenu)
                let menuFrame = frame(
                    below: activeFrame,
                    menuSize: menuSize,
                    containerWidth: proxy.size.width
                )
                let protectedAnchors = anchors.values.map { proxy[$0] }

                ZStack(alignment: .topLeading) {
                    WindowOutsideClickMonitor(
                        protectedRects: [menuFrame] + protectedAnchors,
                        action: dismiss
                    )
                    .allowsHitTesting(false)

                    menuContent(for: presentedMenu, size: menuSize)
                        .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
                        .background {
                            WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(WeekflowPalette.surface)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 3)
                        }
                        .overlay {
                            WeekflowRoundedRectangle(cornerRadius: 8)
                                .stroke(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
                        .position(x: menuFrame.midX, y: menuFrame.midY)
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                        .zIndex(2)

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
                            x: min(
                                max(activeFrame.midX, menuFrame.minX + 14),
                                menuFrame.maxX - 14
                            ),
                            y: menuFrame.minY
                                - WeekflowLayout.taskDurationMenuPointerHeight / 2
                                + 1
                        )
                        .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                        .zIndex(3)
                }
            }
        }
    }

    private func size(for menu: WorkspaceToolbarMenu) -> CGSize {
        switch menu {
        case .date:
            CGSize(
                width: WeekflowLayout.dateJumpPopoverWidth,
                height: WeekflowLayout.dateJumpPopoverMaximumHeight
            )
        case .filter:
            CGSize(
                width: WeekflowLayout.taskFilterPopoverWidth,
                height: WeekflowLayout.taskFilterPopoverMaximumHeight
            )
        case .view:
            CGSize(
                width: WeekflowLayout.workspaceViewPopoverWidth,
                height: WeekflowLayout.workspaceViewPopoverMaximumHeight
            )
        case .calendarOptions:
            CGSize(width: 196, height: 44)
        }
    }

    private func frame(
        below anchor: CGRect,
        menuSize: CGSize,
        containerWidth: CGFloat
    ) -> CGRect {
        let horizontalMargin: CGFloat = 8
        let pointerHeight = WeekflowLayout.taskDurationMenuPointerHeight
        let proposedMidX = anchor.midX
        let minimumMidX = horizontalMargin + menuSize.width / 2
        let maximumMidX = max(minimumMidX, containerWidth - horizontalMargin - menuSize.width / 2)
        let midX = min(max(proposedMidX, minimumMidX), maximumMidX)
        let top = anchor.maxY + pointerHeight - 1
        return CGRect(
            x: midX - menuSize.width / 2,
            y: top,
            width: menuSize.width,
            height: menuSize.height
        )
    }

    @ViewBuilder
    private func menuContent(for menu: WorkspaceToolbarMenu, size: CGSize) -> some View {
        switch menu {
        case .date:
            if destination == .dailyPlanning {
                PlanningDateJumpPopover(
                    selectedDate: $dailyPlanningDate
                )
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            } else if destination == .weeklyPlanning || destination == .weeklyReview {
                WeeklyDateJumpPopover(
                    selectedDate: $weeklyReferenceDate
                )
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            } else {
                DateJumpPopover(
                    selectedIndex: $homeVisibleDayIndex,
                    visibleDayCount: visibleDayCount
                )
                .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
        case .filter:
            TaskFilterPopover(
                store: store,
                selection: $selectedTaskChannel,
                dismiss: dismiss
            )
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .view:
            WorkspaceViewMenu(selection: $workspaceView)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .calendarOptions:
            AssistantCalendarOptionsMenu(
                showsDailyCutoff: showsDailyCutoff,
                toggleDailyCutoff: {
                    showsDailyCutoff.toggle()
                }
            )
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.1)) {
            presentedMenu = nil
        }
    }
}

private struct ToolbarStaticPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(minWidth: 62, minHeight: 24)
            .foregroundStyle(WeekflowPalette.textSecondary)
            .background(WeekflowPalette.surface.opacity(0.58), in: WeekflowRoundedRectangle(cornerRadius: 5))
            .overlay(WeekflowRoundedRectangle(cornerRadius: 5).stroke(WeekflowPalette.border.opacity(0.55), lineWidth: 1))
    }
}

private struct WorkspaceViewMenu: View {
    @Binding var selection: WorkspaceView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("视图：")
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(.horizontal, 15)
                .frame(height: 29, alignment: .bottomLeading)
                .padding(.bottom, 3)

            ForEach(WorkspaceView.allCases) { view in
                WorkspaceViewMenuRow(view: view, isSelected: selection == view) {
                    selection = view
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: WeekflowLayout.workspaceViewPopoverWidth)
        .frame(maxHeight: WeekflowLayout.workspaceViewPopoverMaximumHeight, alignment: .topLeading)
    }
}

private struct WorkspaceViewMenuRow: View {
    let view: WorkspaceView
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(view.rawValue)
                    .font(.system(size: 13))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(isHovering ? WeekflowPalette.selected.opacity(0.42) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}

private struct ToolbarIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 23, height: 24)
                .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .background(WeekflowPalette.button.opacity(isHovering ? 1 : 0.58), in: WeekflowRoundedRectangle(cornerRadius: 5))
                .overlay(WeekflowRoundedRectangle(cornerRadius: 5).stroke(WeekflowPalette.border.opacity(isHovering ? 1 : 0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(help)
        .onHover { isHovering = $0 }
    }
}

private struct ToolbarPillButton: View {
    let title: String
    let systemImage: String
    var fixedWidth: CGFloat? = nil
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(minWidth: fixedWidth ?? 62, maxWidth: fixedWidth, minHeight: 24)
                .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .background(WeekflowPalette.button.opacity(isHovering ? 1 : 0.58), in: WeekflowRoundedRectangle(cornerRadius: 5))
                .overlay(WeekflowRoundedRectangle(cornerRadius: 5).stroke(WeekflowPalette.border.opacity(isHovering ? 1 : 0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

private struct DateJumpButton: View {
    let date: Date
    let isToday: Bool
    let calendarMode: WorkspaceView
    let forcedTitle: String?
    let allowsReset: Bool
    let resetHelp: String
    let action: () -> Void
    let resetToday: () -> Void
    @State private var isHovering = false

    private var dateTitle: String {
        if let forcedTitle { return forcedTitle }
        if !calendarMode.isCalendar { return isToday ? "今日" : compactDate(date) }
        switch calendarMode {
        case .board: return isToday ? "今日" : compactDate(date)
        case .dayCalendar: return isToday ? "今日" : compactDate(date)
        case .threeDayCalendar:
            let end = Calendar.current.date(byAdding: .day, value: 2, to: date) ?? date
            return "\(compactDate(date)) – \(compactDate(end))"
        case .weekdaysCalendar: return "本工作周"
        case .weekCalendar: return "本周"
        case .monthCalendar:
            return date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).year().month(.wide))
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Button(action: action) {
                Label(dateTitle, systemImage: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
            }
            .buttonStyle(.plain)
            .help("可以跳转日期")

            if allowsReset && !isToday {
                Button(action: resetToday) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                }
                .buttonStyle(.plain)
                .help(resetHelp)
            }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 62, minHeight: 24)
        .background(WeekflowPalette.button.opacity(isHovering ? 1 : 0.58), in: WeekflowRoundedRectangle(cornerRadius: 5))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 5).stroke(WeekflowPalette.border.opacity(isHovering ? 1 : 0.55), lineWidth: 1))
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
    }

    private func compactDate(_ date: Date) -> String {
        date.formatted(.dateTime.locale(Locale(identifier: "en_US")).month(.abbreviated).day())
    }
}

struct DateJumpPopover: View {
    @Binding var selectedIndex: Double
    let visibleDayCount: Int
    @State private var displayedMonth: Date
    private let calendar = Calendar.current

    init(
        selectedIndex: Binding<Double>,
        visibleDayCount: Int
    ) {
        _selectedIndex = selectedIndex
        self.visibleDayCount = visibleDayCount
        let selectedDate = Calendar.current.date(
            byAdding: .day,
            value: Int(selectedIndex.wrappedValue.rounded()) - 7,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
        _displayedMonth = State(initialValue: Self.startOfMonth(containing: selectedDate))
    }

    private var selectedDate: Date {
        calendar.date(byAdding: .day, value: Int(selectedIndex.rounded()) - 7, to: calendar.startOfDay(for: .now)) ?? .now
    }

    private var visibleRange: ClosedRange<Date> {
        let start = calendar.startOfDay(for: selectedDate)
        let end = calendar.date(byAdding: .day, value: max(visibleDayCount - 1, 0), to: start) ?? start
        return start...end
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                DateCommandRow(title: "跳转到今天", shortcut: "⇧ Space", key: .space) {
                    selectedIndex = 7
                }
                DateCommandRow(title: "跳转到下一天", shortcut: "⇧ →", key: .rightArrow) {
                    selectedIndex = min(selectedIndex + 1, 13)
                }
                DateCommandRow(title: "跳转到上一天", shortcut: "⇧ ←", key: .leftArrow) {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
            }
            Divider()
            CompactTaskMonthCalendar(
                displayedMonth: $displayedMonth,
                selectedDate: selectedDate,
                highlightsToday: true,
                minimumDate: nil,
                highlightedRangeStart: visibleRange.lowerBound,
                highlightedRangeEnd: visibleRange.upperBound,
                select: selectDate
            )
        }
        .padding(8)
        .frame(width: WeekflowLayout.dateJumpPopoverWidth)
        .frame(height: WeekflowLayout.dateJumpPopoverMaximumHeight, alignment: .topLeading)
        .background(WeekflowPalette.surface)
        .onChange(of: selectedDate) { _, date in
            displayedMonth = Self.startOfMonth(containing: date)
        }
    }

    private func selectDate(_ date: Date) {
        let dayOffset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: .now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        selectedIndex = min(max(Double(dayOffset) + 7, 0), 13)
    }

    private static func startOfMonth(containing date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }
}

private struct PlanningDateJumpPopover: View {
    @Binding var selectedDate: Date
    @State private var displayedMonth: Date
    private let calendar = Calendar.current

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate
        _displayedMonth = State(
            initialValue: Calendar.current.dateInterval(
                of: .month,
                for: selectedDate.wrappedValue
            )?.start ?? selectedDate.wrappedValue
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                DateCommandRow(title: "跳转到今天", shortcut: "⇧ Space", key: .space) {
                    select(calendar.startOfDay(for: .now))
                }
                DateCommandRow(title: "跳转到下一天", shortcut: "⇧ →", key: .rightArrow) {
                    select(calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate)
                }
                DateCommandRow(title: "跳转到上一天", shortcut: "⇧ ←", key: .leftArrow) {
                    select(calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate)
                }
            }
            Divider()
            CompactTaskMonthCalendar(
                displayedMonth: $displayedMonth,
                selectedDate: selectedDate,
                highlightsToday: true,
                minimumDate: nil,
                highlightedRangeStart: selectedDate,
                highlightedRangeEnd: selectedDate,
                select: select
            )
        }
        .padding(8)
        .frame(width: WeekflowLayout.dateJumpPopoverWidth)
        .frame(height: WeekflowLayout.dateJumpPopoverMaximumHeight, alignment: .topLeading)
        .background(WeekflowPalette.surface)
        .onChange(of: selectedDate) { _, date in
            displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }
}

private struct WeeklyDateJumpPopover: View {
    @Binding var selectedDate: Date
    @State private var displayedMonth: Date
    private let calendar = Calendar.current

    init(selectedDate: Binding<Date>) {
        _selectedDate = selectedDate
        _displayedMonth = State(
            initialValue: Calendar.current.dateInterval(
                of: .month,
                for: selectedDate.wrappedValue
            )?.start ?? selectedDate.wrappedValue
        )
    }

    private var weekStart: Date {
        WeeklyDateNavigation.weekStart(for: selectedDate, calendar: calendar)
    }

    private var weekEnd: Date {
        WeeklyDateNavigation.weekEnd(for: selectedDate, calendar: calendar)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                DateCommandRow(title: "跳转到本周", shortcut: "⇧ Space", key: .space) {
                    select(calendar.startOfDay(for: .now))
                }
                DateCommandRow(title: "跳转到下一周", shortcut: "⇧ →", key: .rightArrow) {
                    select(calendar.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate)
                }
                DateCommandRow(title: "跳转到上一周", shortcut: "⇧ ←", key: .leftArrow) {
                    select(calendar.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate)
                }
            }
            Divider()
            CompactTaskMonthCalendar(
                displayedMonth: $displayedMonth,
                selectedDate: selectedDate,
                highlightsToday: true,
                highlightsSelectedDate: false,
                minimumDate: nil,
                highlightedRangeStart: weekStart,
                highlightedRangeEnd: weekEnd,
                select: select
            )
        }
        .padding(8)
        .frame(width: WeekflowLayout.dateJumpPopoverWidth)
        .frame(height: WeekflowLayout.dateJumpPopoverMaximumHeight, alignment: .topLeading)
        .background(WeekflowPalette.surface)
        .onChange(of: selectedDate) { _, date in
            displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }
}

private struct DateCommandRow: View {
    let title: String
    let shortcut: String
    let key: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut)
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WeekflowPalette.textSecondary)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 29)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 5))
        .pointingHandCursor()
        .keyboardShortcut(key, modifiers: [.shift])
    }
}

struct TaskFilterPopover: View {
    @Bindable var store: WeekflowStore
    @Binding var selection: String
    let dismiss: () -> Void
    let headerTitle: String
    let searchPlaceholder: String
    let allTitle: String
    let showsManageChannelAction: Bool
    let listHeight: CGFloat?
    @State private var query = ""

    init(
        store: WeekflowStore,
        selection: Binding<String>,
        headerTitle: String = "筛选频道",
        searchPlaceholder: String = "搜索频道",
        allTitle: String = "全部频道",
        showsManageChannelAction: Bool = true,
        listHeight: CGFloat? = nil,
        dismiss: @escaping () -> Void = {}
    ) {
        self.store = store
        _selection = selection
        self.headerTitle = headerTitle
        self.searchPlaceholder = searchPlaceholder
        self.allTitle = allTitle
        self.showsManageChannelAction = showsManageChannelAction
        self.listHeight = listHeight
        self.dismiss = dismiss
    }

    private var visibleChannels: [TaskChannel] {
        guard !query.isEmpty else { return store.activeChannels }
        return store.activeChannels.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(headerTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    TaskFilterRow(
                        title: allTitle,
                        symbol: "number",
                        color: WeekflowPalette.iconDefault,
                        selected: selection == "all"
                    ) { selection = "all" }
                    filterSectionTitle("频道")
                    ForEach(visibleChannels) { channel in
                        TaskFilterRow(
                            title: channel.title,
                            symbol: channel.resolvedIconName,
                            color: channel.color,
                            selected: selection == channel.id
                        ) { selection = channel.id }
                    }
                }
                .padding(.vertical, 5)
                .padding(.trailing, WeekflowLayout.scrollbarGutterWidth)
            }
            .scrollIndicators(.visible)
            .frame(height: listHeight)
            .frame(maxHeight: WeekflowLayout.taskFilterPopoverListMaximumHeight)

            if showsManageChannelAction {
                Divider()

                Button("管理频道") {
                    dismiss()
                    DispatchQueue.main.async { WeekflowCommand.post(.weekflowOpenChannelSettings) }
                }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(WeekflowPalette.objective)
                    .padding(10)
            }
        }
        .frame(width: WeekflowLayout.taskFilterPopoverWidth)
        .frame(maxHeight: WeekflowLayout.taskFilterPopoverMaximumHeight, alignment: .topLeading)
    }

    private func filterSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(WeekflowPalette.secondaryText)
            .padding(.horizontal, 10)
            .padding(.top, 4)
    }
}

private struct TaskFilterRow: View {
    let title: String
    let symbol: String
    let color: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isEnabled ? WeekflowPalette.secondaryText : WeekflowPalette.textMuted)
                    .lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            .background(
                hovering || focused ? WeekflowPalette.surfaceHover : (selected ? WeekflowPalette.selected.opacity(0.32) : .clear),
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
