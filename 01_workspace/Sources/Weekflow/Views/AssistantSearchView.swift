import SwiftUI

struct AssistantSearchView: View {
    @Bindable var store: WeekflowStore
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void
    @State private var query = ""
    @State private var dateFilter: AssistantSearchDateFilter = .anytime
    @State private var channelID = "all"
    @State private var activeMenu: SearchMenu?
    @State private var hoveredButton: SearchFilterButton?

    private enum SearchMenu {
        case date
        case channel
    }

    private enum SearchFilterButton {
        case filter
        case date
        case channel
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                searchField
                filterRow
                AssistantTaskCardList(
                    entries: Array(filteredEntries.prefix(12)),
                    store: store,
                    emptyTitle: "没有符合条件的任务",
                    openTask: openTask
                )
            }

            if let activeMenu {
                menuOverlay(for: activeMenu)
                    .zIndex(4)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: activeMenu)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WeekflowPalette.textMuted.opacity(0.72))
            TextField("搜索...", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(WeekflowPalette.borderStrong.opacity(0.72)).frame(height: 1)
        }
    }

    private var filterRow: some View {
        HStack(spacing: 5) {
            filterButton(
                id: .filter,
                title: "Filter",
                symbol: "line.3.horizontal.decrease",
                isOpen: false
            ) {}
            filterButton(id: .date, title: dateFilter.title, isOpen: activeMenu == .date) {
                toggle(.date)
            }
            filterButton(
                id: .channel,
                title: selectedChannelTitle,
                isOpen: activeMenu == .channel
            ) {
                toggle(.channel)
            }
        }
    }

    private func menuOverlay(for menu: SearchMenu) -> some View {
        GeometryReader { geometry in
            let menuTop: CGFloat = 73
            let availableWidth = geometry.size.width
            let menuWidth = min(
                menu == .date ? 176 : WeekflowLayout.taskFilterPopoverWidth,
                availableWidth
            )
            let menuHeight = menu == .date ? 132 : channelMenuHeight
            let buttonWidth = max((availableWidth - 10) / 3, 1)
            let triggerCenterX = menu == .date
                ? buttonWidth * 1.5 + 5
                : buttonWidth * 2.5 + 10
            let menuLeading = min(
                max(triggerCenterX - menuWidth / 2, 0),
                max(availableWidth - menuWidth, 0)
            )

            ZStack(alignment: .topLeading) {
                let menuFrame = CGRect(
                    x: menuLeading,
                    y: menuTop,
                    width: menuWidth,
                    height: menuHeight
                )
                WindowOutsideClickMonitor(
                    protectedRect: menuFrame,
                    action: {
                        // The monitor closes asynchronously. If the same click
                        // already switched to another filter menu, keep the new
                        // menu open instead of letting the old one dismiss it.
                        if activeMenu == menu {
                            activeMenu = nil
                        }
                    }
                )
                .allowsHitTesting(false)

                menuContent(for: menu)
                    .frame(
                        width: menuWidth,
                        height: menuHeight,
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
                    .offset(x: menuLeading, y: menuTop)

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
                        x: triggerCenterX,
                        y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                    )
                    .zIndex(3)
            }
        }
    }

    @ViewBuilder
    private func menuContent(for menu: SearchMenu) -> some View {
        switch menu {
        case .date:
            AssistantSearchDatePopover(selection: $dateFilter)
        case .channel:
            TaskFilterPopover(
                store: store,
                selection: $channelID,
                headerTitle: "筛选频道",
                searchPlaceholder: "搜索频道",
                allTitle: "全部频道",
                showsManageChannelAction: false,
                listHeight: channelListHeight
            )
        }
    }

    private var filteredEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        store.activeTasks.filter { entry in
            let matchesQuery = query.isEmpty
                || entry.task.title.localizedCaseInsensitiveContains(query)
            let matchesChannel = channelID == "all" || entry.task.channelID == channelID
            return matchesQuery && matchesChannel && dateFilter.matches(entry.task)
        }
    }

    private var selectedChannelTitle: String {
        guard channelID != "all" else { return "全部频道" }
        return store.channel(for: channelID)?.title ?? "全部频道"
    }

    private var channelListHeight: CGFloat {
        let rowCount = store.activeChannels.count + 1
        let rows = CGFloat(rowCount) * 26
        let rowSpacing = CGFloat(max(rowCount - 1, 0)) * 2
        let sectionAndPadding: CGFloat = 27
        return min(
            rows + rowSpacing + sectionAndPadding,
            WeekflowLayout.taskFilterPopoverListMaximumHeight
        )
    }

    private var channelMenuHeight: CGFloat {
        57 + channelListHeight
    }

    private func toggle(_ menu: SearchMenu) {
        activeMenu = activeMenu == menu ? nil : menu
    }

    private func filterButton(
        id: SearchFilterButton,
        title: String,
        symbol: String? = nil,
        isOpen: Bool,
        action: @escaping () -> Void
    ) -> some View {
        WeekflowButton(action: action) {
            HStack(spacing: 3) {
                if let symbol { Image(systemName: symbol) }
                Text(title).lineLimit(1)
                if symbol == nil {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
            }
            .font(.system(
                size: 10.5,
                weight: isOpen || hoveredButton == id ? .semibold : .regular
            ))
            .foregroundStyle(
                isOpen || hoveredButton == id
                    ? WeekflowPalette.primaryText
                    : WeekflowPalette.secondaryText
            )
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 25)
            .background(
                isOpen || hoveredButton == id
                    ? WeekflowPalette.surfaceSelected
                    : .clear,
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                hoveredButton = hovering ? id : (hoveredButton == id ? nil : hoveredButton)
            }
        }
    }

}

private struct AssistantSearchDatePopover: View {
    @Binding var selection: AssistantSearchDateFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("按时间筛选")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(10)
            Divider()
            VStack(spacing: 2) {
                ForEach(AssistantSearchDateFilter.allCases) { filter in
                    AssistantSearchFilterRow(
                        title: filter.title,
                        symbol: "calendar",
                        selected: selection == filter
                    ) {
                        selection = filter
                    }
                }
            }
            .padding(5)
        }
    }
}

private struct AssistantSearchFilterRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).frame(width: 13)
                Text(title).lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.objective)
                }
            }
            .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background(
                isHovering || selected ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}

enum AssistantSearchDateFilter: String, CaseIterable, Identifiable {
    case anytime, lastWeek, lastMonth
    var id: String { rawValue }
    var title: String {
        switch self {
        case .anytime: "任意时间"
        case .lastWeek: "上周"
        case .lastMonth: "上个月"
        }
    }

    func matches(_ task: WeekTask, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard self != .anytime else { return true }
        let date = task.plannedDate ?? task.updatedAt
        switch self {
        case .anytime:
            return true
        case .lastWeek:
            guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
                  let previousWeek = calendar.dateInterval(
                    of: .weekOfYear,
                    for: currentWeek.start.addingTimeInterval(-1)
                  ) else { return false }
            return previousWeek.contains(date)
        case .lastMonth:
            guard let currentMonth = calendar.dateInterval(of: .month, for: now),
                  let previousMonth = calendar.dateInterval(
                    of: .month,
                    for: currentMonth.start.addingTimeInterval(-1)
                  ) else { return false }
            return previousMonth.contains(date)
        }
    }
}
