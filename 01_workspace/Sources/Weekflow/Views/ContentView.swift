import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @Bindable var store: WeekflowStore
    @Bindable var focusTimer: FocusTimerService
    @State private var destination: AppDestination = .home
    @State private var workspaceView: WorkspaceView = .board
    @State private var activeAssistantPanel: AssistantPanel?
    @State private var assistantCalendarPresentation: AssistantCalendarPresentation = .timeline
    @State private var showingTaskForm = false
    @State private var isSidebarCollapsed = false
    @State private var homeVisibleDayIndex = 7.0
    @State private var dailyPlanningDate = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: Calendar.current.startOfDay(for: .now)
    ) ?? .now
    @State private var weeklyReferenceDate = Calendar.current.startOfDay(for: .now)
    @State private var weeklyPlanningPresentation: WeeklyPlanningPresentation = .sections
    @State private var selectedTaskChannel = "all"
    @State private var presentedWorkspaceToolbarMenu: WorkspaceToolbarMenu?
    @State private var quickTaskPlannedDate: Date?
    @State private var presentedTask: TaskDetailTarget?
    @State private var taskDetailMenuDismissToken = 0
    @State private var showingShortcutHelp = false
    @State private var presentedSettingsSection: WorkspaceSettingsSection?
    @State private var dailyPlanningStep = 0

    init(
        store: WeekflowStore,
        focusTimer: FocusTimerService = FocusTimerService(),
        initialDestination: AppDestination = .home,
        initialWorkspaceView: WorkspaceView = .board,
        initialAssistantPanelPresented: Bool = false
    ) {
        self.store = store
        self.focusTimer = focusTimer
        _destination = State(initialValue: initialDestination)
        _workspaceView = State(initialValue: initialWorkspaceView)
        _activeAssistantPanel = State(initialValue: initialAssistantPanelPresented ? .calendar : nil)
    }

    var body: some View {
        ZStack {
            workspaceLayout

            if showingTaskForm {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closeTaskComposer() }

                QuickTaskFormView(
                    store: store,
                    initialPlannedDate: quickTaskPlannedDate,
                    initialStartTime: dailyPlanningTaskDefaultStartTime,
                    defaultMinutes: destination == .dailyPlanning ? 60 : 0,
                    defaultChannelID: selectedTaskChannel == "all" ? nil : selectedTaskChannel,
                    onDismiss: closeTaskComposer
                )
                .offset(y: -140)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
                .zIndex(2)
            }

            taskDetailOverlay
        }
        .background(TitlebarSidebarToggle(isCollapsed: $isSidebarCollapsed))
        .sheet(isPresented: $showingShortcutHelp) { ShortcutHelpView() }
        .sheet(item: $presentedSettingsSection) { section in
            ChannelSettingsView(store: store, initialSection: section)
        }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowAddTask)) { _ in showingTaskForm = true }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowShortcutHelp)) { _ in showingShortcutHelp = true }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowOpenHighlightedTask)) { _ in openHighlightedTask() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowFocusHighlightedTask)) { _ in openFocusForHighlightedTask() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowToggleTimer)) { _ in toggleHighlightedTimer() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowCompleteHighlightedTask)) { _ in toggleHighlightedCompletion() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowAutoScheduleHighlightedTask)) { _ in store.autoScheduleHighlightedTask() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowDelayHighlightedTask)) { _ in delayHighlightedTask() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowBacklogHighlightedTask)) { _ in moveHighlightedTaskToBacklog() }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowDeleteHighlightedTask)) { _ in deleteHighlightedTask() }
        .onReceive(taskClipboardCommandPublisher) { command in
            switch command {
            case .copy: store.copyHighlightedTask()
            case .cut: store.copyHighlightedTask(cutsSource: true)
            case .paste: _ = store.pasteTaskClipboard(on: store.activeDay)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowOpenSettings)) { _ in
            presentedSettingsSection = .general
        }
        .onReceive(NotificationCenter.default.publisher(for: .weekflowOpenChannelSettings)) { _ in
            presentedSettingsSection = .channels
        }
        .onReceive(globalDateNavigationPublisher) { navigation in
            if destination == .dailyPlanning {
                navigateDailyPlanning(navigation)
            } else {
                switch navigation {
                case .today: showHomeDay(index: 7)
                case .previous: showHomeDay(index: max(homeVisibleDayIndex - 1, 0))
                case .next: showHomeDay(index: min(homeVisibleDayIndex + 1, 13))
                }
            }
        }
        .onChange(of: homeVisibleDayIndex) { _, index in
            store.activeDay = Calendar.current.date(byAdding: .day, value: Int(index.rounded()) - 7, to: Calendar.current.startOfDay(for: .now)) ?? .now
        }
        .onChange(of: destination) { _, newDestination in
            presentedWorkspaceToolbarMenu = nil
            if newDestination == .focus {
                activeAssistantPanel = nil
            }
            if newDestination == .dailyPlanning {
                dailyPlanningStep = 0
                activeAssistantPanel = nil
                dailyPlanningDate = Calendar.current.date(
                    byAdding: .day,
                    value: 1,
                    to: Calendar.current.startOfDay(for: .now)
                ) ?? .now
            }
            guard newDestination == .home else { return }
            workspaceView = .board
            homeVisibleDayIndex = 7
            store.activeDay = Calendar.current.startOfDay(for: .now)
        }
        .onAppear {
            focusTimer.configureTaskWriter { [weak store] reference, minutes in
                store?.recordFocusMinutes(for: reference, minutes: minutes)
            }
            focusTimer.configureFocusWriter { [weak store] mode, minutes, date in
                store?.recordFocusSession(mode: mode, minutes: minutes, date: date)
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            focusTimer.reconcileAfterInactivity()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            focusTimer.pause()
        }
        .tint(WeekflowPalette.objective)
    }

    private var workspaceLayout: some View {
        GeometryReader { proxy in
            let assistantPanelWidth = resolvedAssistantPanelWidth(
                windowWidth: proxy.size.width
            )
            let calendarAssistantReservesSpace = destination == .home
                && workspaceView.isCalendar
                && activeAssistantPanel != nil
            ZStack(alignment: .topTrailing) {
                workspaceColumns(
                    size: proxy.size,
                    assistantPanelWidth: assistantPanelWidth,
                    calendarAssistantReservesSpace: calendarAssistantReservesSpace
                )
                assistantPanel(width: assistantPanelWidth, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .onChange(of: dailyPlanningStep) { oldStep, newStep in
            handleDailyPlanningStepChange(oldStep: oldStep, newStep: newStep)
        }
        .accessibilityHidden(presentedTask != nil)
    }

    private func handleDailyPlanningStepChange(oldStep: Int, newStep: Int) {
        guard destination == .dailyPlanning else { return }
        presentedWorkspaceToolbarMenu = nil
        if newStep >= 2 {
            assistantCalendarPresentation = .timeline
            activeAssistantPanel = .calendar
        } else if oldStep >= 2 {
            activeAssistantPanel = nil
        }
    }

    private func resolvedAssistantPanelWidth(windowWidth: CGFloat) -> CGFloat {
        guard destination == .dailyPlanning, dailyPlanningStep >= 2 else {
            return WeekflowLayout.assistantPanelWidth
        }
        let sidebarWidth = isSidebarCollapsed
            ? 0
            : WeekflowLayout.sidebarWidth + WeekflowLayout.sidebarDividerWidth
        let assistantRailWidth = showsAssistantRail
            ? WeekflowLayout.assistantRailWidth + WeekflowLayout.sidebarDividerWidth
            : 0
        return max((windowWidth - sidebarWidth - assistantRailWidth) / 3, 1)
    }

    private func showHomeDay(index: Double) {
        presentedWorkspaceToolbarMenu = nil
        destination = .home
        workspaceView = .board
        homeVisibleDayIndex = index
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private func navigateDailyPlanning(_ navigation: GlobalDateNavigation) {
        let calendar = Calendar.current
        switch navigation {
        case .today:
            dailyPlanningDate = calendar.startOfDay(for: .now)
        case .previous:
            dailyPlanningDate = calendar.date(
                byAdding: .day,
                value: -1,
                to: dailyPlanningDate
            ) ?? dailyPlanningDate
        case .next:
            dailyPlanningDate = calendar.date(
                byAdding: .day,
                value: 1,
                to: dailyPlanningDate
            ) ?? dailyPlanningDate
        }
    }

    private func workspaceToolbar(
        assistantPanelWidth: CGFloat,
        calendarAssistantReservesSpace: Bool
    ) -> some View {
        WorkspaceToolbar(
            store: store,
            destination: destination,
            dailyPlanningStep: dailyPlanningStep,
            workspaceView: $workspaceView,
            homeVisibleDayIndex: $homeVisibleDayIndex,
            dailyPlanningDate: $dailyPlanningDate,
            weeklyReferenceDate: $weeklyReferenceDate,
            weeklyPlanningPresentation: $weeklyPlanningPresentation,
            selectedTaskChannel: $selectedTaskChannel,
            presentedMenu: $presentedWorkspaceToolbarMenu
        )
        .padding(
            .trailing,
            showsAssistantRail
                && activeAssistantPanel != nil
                && !calendarAssistantReservesSpace ? assistantPanelWidth : 0
        )
        .animation(.easeInOut(duration: 0.16), value: activeAssistantPanel)
    }

    private func workspaceColumns(
        size: CGSize,
        assistantPanelWidth: CGFloat,
        calendarAssistantReservesSpace: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if !isSidebarCollapsed {
                AppSidebarView(store: store, destination: $destination)
                    .frame(width: WeekflowLayout.sidebarWidth, height: size.height, alignment: .top)
                    .zIndex(10)
                Divider()
            }
            VStack(spacing: 0) {
                if destination != .focus {
                    workspaceToolbar(
                        assistantPanelWidth: assistantPanelWidth,
                        calendarAssistantReservesSpace: calendarAssistantReservesSpace
                    )
                    Divider()
                }
                mainScreen
            }
            .padding(.trailing, calendarAssistantReservesSpace ? assistantPanelWidth : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(-1)
            .background(WeekflowPalette.canvas)
            .overlayPreferenceValue(WorkspaceToolbarMenuAnchorPreferenceKey.self) { anchors in
                WorkspaceToolbarMenuLayer(
                    store: store,
                    presentedMenu: $presentedWorkspaceToolbarMenu,
                    homeVisibleDayIndex: $homeVisibleDayIndex,
                    dailyPlanningDate: $dailyPlanningDate,
                    weeklyReferenceDate: $weeklyReferenceDate,
                    selectedTaskChannel: $selectedTaskChannel,
                    destination: destination,
                    workspaceView: $workspaceView,
                    visibleDayCount: toolbarVisibleDayCount,
                    anchors: anchors
                )
            }
            .zIndex(presentedWorkspaceToolbarMenu == nil ? 0 : 15)

            if showsAssistantRail {
                Divider()
                SunsamaAssistantRail(
                    store: store,
                    activePanel: $activeAssistantPanel,
                    showingTaskForm: $showingTaskForm
                )
                .frame(width: WeekflowLayout.assistantRailWidth)
                .layoutPriority(1)
                .zIndex(30)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder
    private func assistantPanel(width: CGFloat, height: CGFloat) -> some View {
        if let activeAssistantPanel, showsAssistantRail {
            SunsamaAssistantPanel(
                store: store,
                panel: activeAssistantPanel,
                activeDate: $store.activeDay,
                calendarPresentation: $assistantCalendarPresentation,
                selectedChannelID: $selectedTaskChannel,
                openCalendarDate: openCalendarDate,
                returnToDashboard: returnToDashboard,
                addTaskOnDate: { date in
                    quickTaskPlannedDate = date
                    showingTaskForm = true
                },
                planDay: { date in
                    store.activeDay = Calendar.current.startOfDay(for: date)
                    destination = .dailyPlanning
                },
                openTask: { entry in
                    store.highlightedTask = TaskReference(
                        goalID: entry.goal.id,
                        taskID: entry.task.id
                    )
                    presentedTask = TaskDetailTarget(
                        goalID: entry.goal.id,
                        taskID: entry.task.id
                    )
                }
            )
            .frame(width: width, height: height)
            .assistantPanelLeadingDivider()
            .padding(.trailing, showsAssistantRail ? WeekflowLayout.assistantRailWidth : 0)
            .zIndex(20)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private func openCalendarDate(_ date: Date) {
        let calendar = Calendar.current
        let selectedDate = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)
        let dayOffset = calendar.dateComponents([.day], from: today, to: selectedDate).day ?? 0

        presentedWorkspaceToolbarMenu = nil
        activeAssistantPanel = .calendar
        assistantCalendarPresentation = .dayTasks
        store.activeDay = selectedDate
        destination = .home

        DispatchQueue.main.async {
            homeVisibleDayIndex = Double(dayOffset + 7)
            workspaceView = .monthCalendar
        }
    }

    private func returnToDashboard(_ date: Date) {
        let calendar = Calendar.current
        let selectedDate = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: .now)
        let dayOffset = calendar.dateComponents([.day], from: today, to: selectedDate).day ?? 0

        presentedWorkspaceToolbarMenu = nil
        store.activeDay = selectedDate
        withAnimation(.easeInOut(duration: 0.16)) {
            assistantCalendarPresentation = .timeline
            workspaceView = .board
            homeVisibleDayIndex = Double(min(max(dayOffset + 7, 0), 13))
        }
    }

    private enum GlobalDateNavigation {
        case today
        case previous
        case next
    }

    private enum TaskClipboardCommand {
        case copy
        case cut
        case paste
    }

    private var globalDateNavigationPublisher: AnyPublisher<GlobalDateNavigation, Never> {
        Publishers.Merge3(
            NotificationCenter.default.publisher(for: .weekflowJumpToToday)
                .map { _ in GlobalDateNavigation.today },
            NotificationCenter.default.publisher(for: .weekflowJumpToPreviousDay)
                .map { _ in GlobalDateNavigation.previous },
            NotificationCenter.default.publisher(for: .weekflowJumpToNextDay)
                .map { _ in GlobalDateNavigation.next }
        )
        .eraseToAnyPublisher()
    }

    private var taskClipboardCommandPublisher: AnyPublisher<TaskClipboardCommand, Never> {
        Publishers.Merge3(
            NotificationCenter.default.publisher(for: .weekflowCopyHighlightedTask)
                .map { _ in TaskClipboardCommand.copy },
            NotificationCenter.default.publisher(for: .weekflowCutHighlightedTask)
                .map { _ in TaskClipboardCommand.cut },
            NotificationCenter.default.publisher(for: .weekflowPasteTask)
                .map { _ in TaskClipboardCommand.paste }
        )
        .eraseToAnyPublisher()
    }

    @ViewBuilder
    private var mainScreen: some View {
        switch destination {
        case .home:
            if workspaceView == .board {
                HomeBoardView(
                    store: store,
                    visibleDayIndex: $homeVisibleDayIndex,
                    selectedChannelID: selectedTaskChannel,
                    additionalVisibleWidth: isSidebarCollapsed
                        ? WeekflowLayout.collapsedSidebarBoardWidthGain
                        : 0
                ) { date in
                    quickTaskPlannedDate = date
                    showingTaskForm = true
                } openTask: { entry in
                    store.highlightedTask = TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
                    presentedTask = TaskDetailTarget(goalID: entry.goal.id, taskID: entry.task.id)
                } showCalendar: {
                    activeAssistantPanel = .calendar
                } planDay: { date in
                    store.activeDay = Calendar.current.startOfDay(for: date)
                    destination = .dailyPlanning
                }
            }
            else {
                WorkspaceCalendarView(
                    store: store,
                    mode: workspaceView,
                    selectedDate: visibleStartDate,
                    selectedChannelID: selectedTaskChannel
                )
            }
        case .focus: FocusView(timer: focusTimer)
        case .dailyPlanning:
            DailyPlanningView(
                store: store,
                step: $dailyPlanningStep,
                showingTaskForm: $showingTaskForm,
                plannedDate: $quickTaskPlannedDate,
                finish: { destination = .home },
                planningDate: dailyPlanningDate
            )
        case .dailyShutdown: DailyShutdownView(store: store)
        case .weeklyPlanning:
            WeeklyBoardView(
                store: store,
                presentedTask: $presentedTask,
                referenceDate: weeklyReferenceDate,
                presentation: $weeklyPlanningPresentation
            )
            .id(WeeklyDateNavigation.weekStart(for: weeklyReferenceDate))
        case .weeklyReview:
            WeeklyReviewView(store: store, referenceDate: weeklyReferenceDate)
        case .archive:
            ArchiveSummaryView(store: store, selectedChannelID: selectedTaskChannel) { entry in
                presentedTask = TaskDetailTarget(goalID: entry.goal.id, taskID: entry.task.id)
            }
        case .trash:
            TrashSummaryView(store: store, selectedChannelID: selectedTaskChannel) { entry in
                presentedTask = TaskDetailTarget(goalID: entry.goal.id, taskID: entry.task.id)
            }
        }
    }

    @ViewBuilder
    private var taskDetailOverlay: some View {
        if let presentedTask {
            ZStack {
                WeekflowPalette.taskDetailBackdrop
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { taskDetailMenuDismissToken += 1 }

                TaskDetailView(
                    store: store,
                    target: presentedTask,
                    menuDismissToken: taskDetailMenuDismissToken,
                    onClose: closeTaskDetail
                )
                .clipShape(
                    WeekflowRoundedRectangle(
                        cornerRadius: WeekflowLayout.taskDetailCornerRadius
                    )
                )
                .overlay {
                    WeekflowRoundedRectangle(
                        cornerRadius: WeekflowLayout.taskDetailCornerRadius
                    )
                    .strokeBorder(WeekflowPalette.border.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
                .transition(.scale(scale: 0.985).combined(with: .opacity))
            }
            .zIndex(100)
            .transition(.opacity)
        }
    }

    private func openHighlightedTask() {
        guard let highlighted = store.highlightedTask else { return }
        presentedTask = TaskDetailTarget(goalID: highlighted.goalID, taskID: highlighted.taskID)
    }

    private func openFocusForHighlightedTask() {
        linkHighlightedTaskToFocus()
        destination = .focus
    }

    private func linkHighlightedTaskToFocus() {
        if let reference = store.highlightedTask,
           let entry = store.activeTasks.first(where: { $0.goal.id == reference.goalID && $0.task.id == reference.taskID }) {
            guard focusTimer.linkedTask != reference else { return }
            focusTimer.linkTask(reference, title: entry.task.title, estimatedMinutes: entry.task.estimatedMinutes)
        }
    }

    private func closeTaskComposer() {
        showingTaskForm = false
        quickTaskPlannedDate = nil
    }

    private var dailyPlanningTaskDefaultStartTime: Date? {
        guard destination == .dailyPlanning, let quickTaskPlannedDate else { return nil }
        return store.nextDailyPlanningTaskStart(on: quickTaskPlannedDate)
    }

    private func closeTaskDetail() {
        presentedTask = nil
    }

    private func toggleHighlightedTimer() {
        guard let reference = store.highlightedTask else { return }
        store.toggleTaskTimer(goalID: reference.goalID, taskID: reference.taskID)
    }

    private func toggleHighlightedCompletion() {
        guard let reference = store.highlightedTask else { return }
        store.toggleTask(goalID: reference.goalID, taskID: reference.taskID)
    }

    private func delayHighlightedTask() {
        guard let reference = store.highlightedTask,
              let entry = store.activeTasks.first(where: { $0.goal.id == reference.goalID && $0.task.id == reference.taskID }) else { return }
        store.moveTask(goalID: reference.goalID, taskID: reference.taskID, to: Calendar.current.date(byAdding: .day, value: 1, to: entry.task.plannedDate ?? store.activeDay))
    }

    private func moveHighlightedTaskToBacklog() {
        guard let reference = store.highlightedTask else { return }
        store.unassignTask(goalID: reference.goalID, taskID: reference.taskID)
    }

    private func deleteHighlightedTask() {
        guard let reference = store.highlightedTask else { return }
        store.deleteTask(goalID: reference.goalID, taskID: reference.taskID)
    }

    private var visibleStartDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: Int(homeVisibleDayIndex.rounded()) - 7,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
    }

    private var toolbarVisibleDayCount: Int {
        if destination == .home && workspaceView == .board {
            return Int(WeekflowLayout.boardVisibleDayCount)
        }
        return max(workspaceView.visibleDayCount, 1)
    }

    private var showsAssistantRail: Bool {
        switch destination {
        case .focus, .archive, .trash:
            false
        default:
            true
        }
    }

}
