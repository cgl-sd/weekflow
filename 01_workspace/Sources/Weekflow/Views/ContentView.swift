import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: WeekflowStore
    @Bindable var focusTimer: FocusTimerService
    @State private var coordinator: AppCoordinator
    @State private var activeAssistantPanel: AssistantPanel?
    @State private var assistantCalendarPresentation: AssistantCalendarPresentation = .timeline
    @State private var showingTaskForm = false
    @State private var isSidebarCollapsed = false
    @State private var homeVisibleDayIndex = 7.0
    @State private var dailyPlanningDate = SystemBusinessCalendar.current.calendar.date(
        byAdding: .day,
        value: 1,
        to: SystemBusinessCalendar.current.calendar.startOfDay(for: .now)
    ) ?? .now
    @State private var weeklyReferenceDate = SystemBusinessCalendar.current.calendar.startOfDay(for: .now)
    @State private var weeklyPlanningPresentation: WeeklyPlanningPresentation = .sections
    @State private var selectedTaskChannel = "all"
    @State private var presentedWorkspaceToolbarMenu: WorkspaceToolbarMenu?
    @State private var quickTaskPlannedDate: Date?
    @State private var presentedTask: TaskDetailTarget?
    @State private var taskDetailMenuDismissToken = 0
    @State private var showingShortcutHelp = false
    @State private var presentedSettingsSection: WorkspaceSettingsSection?
    @State private var dailyPlanningStep = 0
    @State private var showsPlanImporter = false
    @State private var planImportError: String?

    init(
        store: WeekflowStore,
        focusTimer: FocusTimerService = FocusTimerService(),
        initialDestination: AppDestination = .home,
        initialWorkspaceView: WorkspaceView = .board,
        initialAssistantPanelPresented: Bool = false
    ) {
        self.store = store
        self.focusTimer = focusTimer
        _coordinator = State(initialValue: AppCoordinator(
            navigation: NavigationStore(
                destination: initialDestination,
                workspaceView: initialWorkspaceView
            )
        ))
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
        .fileImporter(
            isPresented: $showsPlanImporter,
            allowedContentTypes: [.json]
        ) { result in
            handlePlanImportResult(result)
        }
        .alert("导入失败", isPresented: Binding(
            get: { planImportError != nil },
            set: { if !$0 { planImportError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(planImportError ?? "")
        }
        .alert(
            "发现异常中断的计时",
            isPresented: Binding(
                get: { store.pendingTimerRecovery != nil },
                set: { if !$0, store.pendingTimerRecovery != nil { store.resolveInterruptedTimer(includeElapsedTime: false) } }
            )
        ) {
            Button("补记中断时长") { store.resolveInterruptedTimer(includeElapsedTime: true) }
            Button("忽略中断时长", role: .cancel) { store.resolveInterruptedTimer(includeElapsedTime: false) }
        } message: {
            Text("上次计时持续时间异常，请确认是否计入任务实际时长。")
        }
        .onChange(of: coordinator.commands.latest) { _, routed in
            guard let routed,
                  coordinator.accepts(routed) else { return }
            handle(routed.command)
        }
        .onChange(of: homeVisibleDayIndex) { _, index in
            store.activeDay = SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: Int(index.rounded()) - 7, to: SystemBusinessCalendar.current.calendar.startOfDay(for: .now)) ?? .now
        }
        .onChange(of: destination) { _, newDestination in
            presentedWorkspaceToolbarMenu = nil
            if newDestination == .focus {
                activeAssistantPanel = nil
            }
            if newDestination == .dailyPlanning {
                dailyPlanningStep = 0
                activeAssistantPanel = nil
                dailyPlanningDate = SystemBusinessCalendar.current.calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: SystemBusinessCalendar.current.calendar.startOfDay(for: .now)
                ) ?? .now
            }
            guard newDestination == .home else { return }
            workspaceView = .board
            homeVisibleDayIndex = 7
            store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: .now)
        }
        .onAppear {
            coordinator.activate()
            focusTimer.configureTaskWriter { [weak store] reference, seconds in
                store?.recordFocusSeconds(for: reference, seconds: seconds)
            }
            focusTimer.configureFocusWriter { [weak store] mode, seconds, date in
                store?.recordFocusSession(mode: mode, seconds: seconds, date: date)
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

    private var destination: AppDestination {
        get { coordinator.navigation.destination }
        nonmutating set { coordinator.navigation.destination = newValue }
    }

    private var workspaceView: WorkspaceView {
        get { coordinator.navigation.workspaceView }
        nonmutating set { coordinator.navigation.workspaceView = newValue }
    }

    private var destinationBinding: Binding<AppDestination> {
        Binding(get: { destination }, set: { destination = $0 })
    }

    private var workspaceViewBinding: Binding<WorkspaceView> {
        Binding(get: { workspaceView }, set: { workspaceView = $0 })
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

    private func navigateDailyPlanning(_ navigation: ContentCommandHandler.GlobalDateNavigation) {
        let calendar = SystemBusinessCalendar.current.calendar
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
            workspaceView: workspaceViewBinding,
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
                AppSidebarView(store: store, destination: destinationBinding)
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
                    workspaceView: workspaceViewBinding,
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
                    store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
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
        let calendar = SystemBusinessCalendar.current.calendar
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
        let calendar = SystemBusinessCalendar.current.calendar
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

    private func handle(_ command: AppCommand) {
        // Delegate command handling to ContentCommandHandler (P2-2 ContentView split)
        let handler = ContentCommandHandler(
            store: store,
            focusTimer: focusTimer,
            setShowTaskForm: { showingTaskForm = $0 },
            setShowShortcutHelp: { showingShortcutHelp = $0 },
            setPresentedSettings: { presentedSettingsSection = $0 },
            setPresentedTask: { presentedTask = $0 },
            setDestination: { destination = $0 },
            navigateDate: { routeDateNavigation($0) },
            setShowPlanImporter: { showsPlanImporter = $0 }
        )
        handler.handle(command)
    }

    private func handlePlanImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                planImportError = "无法访问所选文件"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                switch PlanImportService.parse(data: data) {
                case .success(let payload):
                    let conflict = PlanImportService.detectConflict(
                        startDate: PlanImportService.parseDatePublic(payload.startDate) ?? .now,
                        endDate: PlanImportService.parseDatePublic(payload.endDate) ?? .now,
                        activePlan: store.activePlan
                    )
                    let archiveExisting: Bool
                    switch conflict {
                    case .none:
                        archiveExisting = false
                    case .partialOverlap(let title), .fullOverlap(let title):
                        // For now, auto-archive on conflict; a dialog could be added later
                        archiveExisting = true
                        _ = title
                    }
                    if PlanImportService.importIntoStore(payload, store: store, archiveExisting: archiveExisting) == nil {
                        planImportError = "导入过程中日期解析失败"
                    }
                case .failure(let error):
                    planImportError = error.localizedDescription
                }
            } catch {
                planImportError = "读取文件失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            planImportError = "选择文件失败：\(error.localizedDescription)"
        }
    }

    private func routeDateNavigation(_ navigation: ContentCommandHandler.GlobalDateNavigation) {
        if destination == .dailyPlanning {
            switch navigation {
            case .today: navigateDailyPlanning(.today)
            case .previous: navigateDailyPlanning(.previous)
            case .next: navigateDailyPlanning(.next)
            }
        } else {
            switch navigation {
            case .today: showHomeDay(index: 7)
            case .previous: showHomeDay(index: max(homeVisibleDayIndex - 1, 0))
            case .next: showHomeDay(index: min(homeVisibleDayIndex + 1, 13))
            }
        }
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
                    store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
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

    private var visibleStartDate: Date {
        SystemBusinessCalendar.current.calendar.date(
            byAdding: .day,
            value: Int(homeVisibleDayIndex.rounded()) - 7,
            to: SystemBusinessCalendar.current.calendar.startOfDay(for: .now)
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
