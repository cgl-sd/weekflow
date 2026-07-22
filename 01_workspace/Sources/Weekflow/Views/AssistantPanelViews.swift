import SwiftUI

extension View {
    func assistantPanelLeadingDivider() -> some View {
        overlay(alignment: .leading) {
            Rectangle()
                .fill(WeekflowPalette.border)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
    }
}

struct SunsamaAssistantRail: View {
    @Bindable var store: WeekflowStore
    @Binding var activePanel: AssistantPanel?
    @Binding var showingTaskForm: Bool

    var body: some View {
        VStack(spacing: 4) {
            AssistantRailCollapseButton(isExpanded: activePanel != nil) {
                activePanel = activePanel == nil ? .calendar : nil
            }
            ForEach(AssistantPanel.railCases) { item in
                AssistantRailButton(
                    item: item,
                    isSelected: activePanel == item
                ) {
                    activePanel = AssistantPanel.toggled(item, current: activePanel)
                }
            }
            Spacer()
        }
        .padding(.top, 9)
        .padding(.bottom, 16)
        .padding(.horizontal, 4)
        .background(WeekflowPalette.canvas)
    }
}

struct AssistantRailCollapseButton: View {
    let isExpanded: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Image(systemName: isExpanded ? "chevron.right.2" : "chevron.left.2")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isHovering ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .frame(width: 40, height: 40)
                .background(isHovering ? WeekflowPalette.surfaceSelected : .clear, in: WeekflowRoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { isHovering = $0 }
        .help(isExpanded ? "收起右侧栏" : "展开右侧栏")
    }
}

struct AssistantRailButton: View {
    let item: AssistantPanel
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    private var isHighlighted: Bool {
        SidebarRowVisualState.resolve(
            isSelected: isSelected,
            isHovering: isHovering
        ) == .highlighted
    }

    var body: some View {
        WeekflowButton(action: action) {
            Image(systemName: item.symbol)
                .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isHighlighted ? WeekflowPalette.primaryText : WeekflowPalette.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    isHighlighted ? WeekflowPalette.surfaceSelected : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .stablePointingHandHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(item.title)
    }
}

struct SunsamaAssistantPanel: View {
    @Bindable var store: WeekflowStore
    let panel: AssistantPanel
    @Binding var activeDate: Date
    @Binding var calendarPresentation: AssistantCalendarPresentation
    @Binding var selectedChannelID: String
    let openCalendarDate: (Date) -> Void
    let returnToDashboard: (Date) -> Void
    let addTaskOnDate: (Date) -> Void
    let planDay: (Date) -> Void
    let openTask: ((goal: WeeklyGoal, task: WeekTask)) -> Void
    @State private var showsTaskFilter = false
    @State private var showsCalendarOptions = false
    @State private var isPanelTitleHovering = false
    @AppStorage("weekflow.calendar.showsDailyCutoff")
    private var showsDailyCutoff = true

    init(
        store: WeekflowStore,
        panel: AssistantPanel,
        activeDate: Binding<Date>,
        calendarPresentation: Binding<AssistantCalendarPresentation> = .constant(.timeline),
        selectedChannelID: Binding<String> = .constant("all"),
        openCalendarDate: @escaping (Date) -> Void = { _ in },
        returnToDashboard: @escaping (Date) -> Void = { _ in },
        addTaskOnDate: @escaping (Date) -> Void = { _ in },
        planDay: @escaping (Date) -> Void = { _ in },
        openTask: @escaping ((goal: WeeklyGoal, task: WeekTask)) -> Void = { _ in }
    ) {
        self.store = store
        self.panel = panel
        _activeDate = activeDate
        _calendarPresentation = calendarPresentation
        _selectedChannelID = selectedChannelID
        self.openCalendarDate = openCalendarDate
        self.returnToDashboard = returnToDashboard
        self.addTaskOnDate = addTaskOnDate
        self.planDay = planDay
        self.openTask = openTask
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack {
                    if panel == .calendar && calendarPresentation == .dayTasks {
                        AssistantTaskFilterButton(isPresented: showsTaskFilter) {
                            withAnimation(.easeOut(duration: 0.12)) {
                                showsTaskFilter.toggle()
                            }
                        }
                    } else if panel == .calendar {
                        WeekflowButton {
                            withAnimation(.easeOut(duration: 0.12)) {
                                showsCalendarOptions.toggle()
                            }
                        } label: {
                            Label(panel.title, systemImage: panel.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 7)
                                .frame(minHeight: 24)
                                .background(
                                    isPanelTitleHovering || showsCalendarOptions
                                        ? WeekflowPalette.surfaceSelected
                                        : .clear,
                                    in: WeekflowRoundedRectangle(cornerRadius: 5)
                                )
                                .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .stablePointingHandHover { isPanelTitleHovering = $0 }
                        .help("日历显示设置")
                    } else {
                        Label(panel.title, systemImage: panel.symbol)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Spacer()
                }
                .frame(height: 24)
                .padding(.horizontal, 14)
                .padding(.top, 17)
                .padding(.bottom, 4)
                Divider()

                Group {
                    switch panel {
                    case .calendar:
                        if calendarPresentation == .timeline {
                            AssistantCalendarView(
                                store: store,
                                activeDate: $activeDate,
                                openDayTasks: openCalendarDate
                            )
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                        } else {
                            AssistantDayTaskListView(
                                store: store,
                                activeDate: $activeDate,
                                selectedChannelID: selectedChannelID,
                                addTask: { addTaskOnDate(activeDate) },
                                returnToDashboard: {
                                    showsTaskFilter = false
                                    returnToDashboard(activeDate)
                                },
                                planDay: { planDay(activeDate) }
                            )
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    case .goals: AssistantGoalsView(store: store)
                    case .backlog: AssistantBacklogView(store: store, openTask: openTask)
                    case .shutdown: AssistantShutdownView(store: store)
                    case .search: AssistantSearchView(store: store, openTask: openTask)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showsTaskFilter && panel == .calendar && calendarPresentation == .dayTasks {
                assistantTaskFilterOverlay
                    .zIndex(5)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
            }

            if showsCalendarOptions && panel == .calendar && calendarPresentation == .timeline {
                assistantCalendarOptionsOverlay
                    .zIndex(5)
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
            }
        }
        .background(WeekflowPalette.canvas)
        .overlay {
            SecondaryClickOcclusionRegion()
                .allowsHitTesting(false)
        }
    }

    private var assistantCalendarOptionsOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismissCalendarOptions() }

            AssistantCalendarOptionsMenu(
                showsDailyCutoff: showsDailyCutoff,
                toggleDailyCutoff: {
                    showsDailyCutoff.toggle()
                    dismissCalendarOptions()
                }
            )
            .frame(width: 196, height: 44, alignment: .topLeading)
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
            .offset(x: 14, y: 52)

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
                .offset(x: 35, y: 45)
        }
    }

    private func dismissCalendarOptions() {
        withAnimation(.easeOut(duration: 0.1)) {
            showsCalendarOptions = false
        }
    }

    private var assistantTaskFilterOverlay: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showsTaskFilter = false
                    }
                }

            TaskFilterPopover(
                store: store,
                selection: $selectedChannelID,
                dismiss: {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showsTaskFilter = false
                    }
                }
            )
            .frame(
                width: WeekflowLayout.taskFilterPopoverWidth,
                height: WeekflowLayout.taskFilterPopoverMaximumHeight,
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
            .offset(x: 14, y: 52)

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
                .offset(x: 35, y: 45)
        }
    }
}

