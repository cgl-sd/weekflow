import AppKit
import SwiftUI

private enum WorkTimePickerAnchor: Hashable {
    case start
    case cutoff
}

private struct WorkTimePickerAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [WorkTimePickerAnchor: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [WorkTimePickerAnchor: Anchor<CGRect>],
        nextValue: () -> [WorkTimePickerAnchor: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct DailyPlanningView: View {
    @Bindable var store: WeekflowStore
    @Binding var step: Int
    @Binding var showingTaskForm: Bool
    @Binding var plannedDate: Date?
    let finish: () -> Void
    var referenceDate: Date = .now
    var planningDate: Date? = nil
    @State private var selectedStartMinutes = DailyPlanningState.defaultStartMinutes
    @State private var selectedShutdownMinutes = DailyPlanningState.defaultCutoffMinutes
    @State private var showsStartPicker = false
    @State private var showsShutdownPicker = false
    @State private var isStartTimeHovering = false
    @State private var isShutdownTimeHovering = false
    @State private var isAddToCalendarHovering = false
    @State private var draggedTaskToken: TaskDragToken?
    @State private var newlyAssignedTaskID: UUID?
    private let calendar = Calendar.current

    var body: some View {
        let tomorrow = planningDate.map { calendar.startOfDay(for: $0) }
            ?? calendar.date(byAdding: .day, value: 1, to: referenceDate)
            ?? referenceDate
        GeometryReader { proxy in
            let columnWidth = WeekflowLayout.threeColumnWidth(
                for: proxy.size.width,
                columnSpacing: WeekflowLayout.dailyWorkspaceColumnSpacing
            )
            Group {
                switch step {
                case 1:
                    waitingStep(date: tomorrow, columnWidth: columnWidth)
                case 2...:
                    finalPlanningStep(date: tomorrow, columnWidth: columnWidth)
                default:
                    firstPlanningStep(date: tomorrow, columnWidth: columnWidth)
                }
            }
            .id(step)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WeekflowPalette.canvas)
        .onAppear {
            store.activeDay = tomorrow
            selectedStartMinutes = store.dailyPlanningStartMinutes(on: tomorrow)
            selectedShutdownMinutes = store.dailyPlanningCutoffMinutes(on: tomorrow)
            store.ensureDailyPlanningTaskSchedule(on: tomorrow)
        }
        .onChange(of: tomorrow) { _, date in
            store.activeDay = date
            selectedStartMinutes = store.dailyPlanningStartMinutes(on: date)
            selectedShutdownMinutes = store.dailyPlanningCutoffMinutes(on: date)
            store.ensureDailyPlanningTaskSchedule(on: date)
            showsStartPicker = false
            showsShutdownPicker = false
        }
    }

    private func firstPlanningStep(date: Date, columnWidth: CGFloat) -> some View {
        let dayTitle = relativeDayTitle(date)
        return HStack(alignment: .top, spacing: WeekflowLayout.dailyWorkspaceColumnSpacing) {
            PlanningInstructionColumn(
                title: "安排\(dayTitle)的工作时间",
                detail: "设置时间，再选择任务。",
                backTitle: nil,
                nextTitle: "下一步",
                back: nil,
                next: { step = 1 }
            ) {
                workTimeCard(date: date)
            }
            .frame(width: columnWidth)

            VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
                DailyWorkspaceColumnHeader(
                    title: "每周任务池",
                    detail: "双击或拖动任务，添加到\(dayTitle)的每日任务。",
                    badge: nil
                ) {
                    EmptyView()
                }
                PlanningTaskPool(
                    store: store,
                    targetDate: date,
                    assignmentDate: date,
                    fillsAvailableHeight: true,
                    dragStarted: { draggedTaskToken = $0 },
                    taskAssigned: { newlyAssignedTaskID = $0 }
                )
            }
            .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
            .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
            .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
            .frame(width: columnWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            PlanningTaskList(
                title: dayTitle,
                date: date,
                store: store,
                draggedTaskToken: $draggedTaskToken,
                newlyAssignedTaskID: $newlyAssignedTaskID,
                addTask: {
                    plannedDate = date
                    showingTaskForm = true
                }
            )
            .frame(width: columnWidth)
        }
    }

    private func waitingStep(date: Date, columnWidth: CGFloat) -> some View {
        let currentDate = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        let currentDayTitle = relativeDayTitle(currentDate)
        let dayTitle = relativeDayTitle(date)

        return HStack(alignment: .top, spacing: WeekflowLayout.dailyWorkspaceColumnSpacing) {
            PlanningInstructionColumn(
                title: "接续未完成任务",
                detail: "检查\(currentDayTitle)尚未完成的事项，把需要继续推进的任务安排到\(dayTitle)。",
                backTitle: "返回",
                nextTitle: "下一步",
                back: { step = 0 },
                next: { step = 2 }
            ) {
                continuationSummary(currentDate: currentDate, targetDate: date)
            }
            .frame(width: columnWidth)

            PlanningTaskList(
                title: currentDayTitle,
                date: currentDate,
                store: store,
                draggedTaskToken: $draggedTaskToken,
                newlyAssignedTaskID: $newlyAssignedTaskID,
                addTask: {
                    plannedDate = currentDate
                    showingTaskForm = true
                }
            )
            .frame(width: columnWidth)

            PlanningTaskList(
                title: dayTitle,
                date: date,
                store: store,
                draggedTaskToken: $draggedTaskToken,
                newlyAssignedTaskID: $newlyAssignedTaskID,
                addTask: {
                    plannedDate = date
                    showingTaskForm = true
                }
            )
            .frame(width: columnWidth)
        }
    }

    private func finalPlanningStep(date: Date, columnWidth: CGFloat) -> some View {
        let dayTitle = relativeDayTitle(date)

        return HStack(alignment: .top, spacing: WeekflowLayout.dailyWorkspaceColumnSpacing) {
            PlanningInstructionColumn(
                title: "确定计划",
                detail: "确认工作时间与任务顺序，再检查日历安排。",
                backTitle: "返回",
                nextTitle: "完成计划",
                back: { step = 1 },
                next: finish
            ) {
                workTimeCard(date: date)
            }
            .frame(width: columnWidth)

            PlanningTaskList(
                title: dayTitle,
                date: date,
                store: store,
                draggedTaskToken: $draggedTaskToken,
                newlyAssignedTaskID: $newlyAssignedTaskID,
                addTask: {
                    plannedDate = date
                    showingTaskForm = true
                }
            )
            .frame(width: columnWidth)

            Color.clear
                .frame(width: columnWidth)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }

    private func continuationSummary(currentDate: Date, targetDate: Date) -> some View {
        let unfinishedCount = store.tasks(on: currentDate).lazy.filter {
            $0.task.status != .completed
        }.count
        let plannedMinutes = store.tasks(on: targetDate).lazy
            .filter { $0.task.status != .completed }
            .reduce(0) { $0 + max($1.task.estimatedMinutes, 0) }
        let availableMinutes = max(
            store.dailyPlanningCutoffMinutes(on: targetDate)
                - store.dailyPlanningStartMinutes(on: targetDate),
            1
        )
        let workloadFraction = Double(plannedMinutes) / Double(availableMinutes)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("今天 \(unfinishedCount) 项未完成")
                Spacer(minLength: 8)
                Text("明天已安排 \(plannedMinutes.hourMinuteText)")
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(WeekflowPalette.secondaryText)

            WeekflowDailyProgressTrack(
                fraction: workloadFraction,
                hasProgress: plannedMinutes > 0,
                alwaysVisible: true,
                accessibilityLabel: "明天工作量",
                accessibilityValue: "已安排 \(plannedMinutes.hourMinuteText)，可用 \(availableMinutes.hourMinuteText)"
            )
            .frame(height: WeekflowLayout.homeDailyProgressHeight)
        }
        .padding(.top, 2)
    }

    private func workTimeCard(date: Date) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("工作时间")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("开始工作")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            showsStartPicker.toggle()
                            showsShutdownPicker = false
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "sunrise")
                                .font(.system(size: 12, weight: .medium))
                            Text(workTimeText(selectedStartMinutes))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: WeekflowLayout.workCutoffControlHeight)
                        .background(
                            isStartTimeHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surface,
                            in: WeekflowRoundedRectangle(cornerRadius: 7)
                        )
                        .overlay(
                            WeekflowRoundedRectangle(cornerRadius: 7)
                                .stroke(isStartTimeHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { isStartTimeHovering = $0 }
                    .help("选择工作开始时间")
                    .anchorPreference(
                        key: WorkTimePickerAnchorPreferenceKey.self,
                        value: .bounds
                    ) { [.start: $0] }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("工作截止")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        showsShutdownPicker.toggle()
                        showsStartPicker = false
                    }
                } label: {
                    HStack(spacing: 7) {
                            Image(systemName: "sunset")
                            .font(.system(size: 12, weight: .medium))
                            Text(workTimeText(selectedShutdownMinutes))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(WeekflowPalette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: WeekflowLayout.workCutoffControlHeight)
                    .background(
                        isShutdownTimeHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surface,
                        in: WeekflowRoundedRectangle(cornerRadius: 7)
                    )
                    .overlay(
                        WeekflowRoundedRectangle(cornerRadius: 7)
                            .stroke(isShutdownTimeHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
                    )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .onHover { isShutdownTimeHovering = $0 }
                .help("选择 00:30–24:00 的工作截止时间")
                .anchorPreference(
                    key: WorkTimePickerAnchorPreferenceKey.self,
                    value: .bounds
                ) { [.cutoff: $0] }
                }
            }

            Button {
                selectedShutdownMinutes = store.setDailyPlanningCutoff(
                    minutes: selectedShutdownMinutes,
                    on: date
                )
                _ = store.addDailyPlanningCutoffToCalendar(on: date)
                store.activeDay = date
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: store.dailyPlanningCutoffEvent(on: date) == nil ? "calendar.badge.plus" : "calendar.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WeekflowPalette.objective)
                    Text("添加到日历")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: WeekflowLayout.workCutoffControlHeight)
                .background(
                    isAddToCalendarHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surface,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .overlay(
                    WeekflowRoundedRectangle(cornerRadius: 7)
                        .stroke(isAddToCalendarHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
                )
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .onHover { isAddToCalendarHovering = $0 }
            .help("在\(relativeDayTitle(date))日历中创建或更新工作截止标记")

            Text("新任务自动接续时间。")
                .font(.system(size: 10.5))
                .foregroundStyle(WeekflowPalette.textMuted)
        }
        .padding(14)
        .background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 9))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 9).stroke(WeekflowPalette.border, lineWidth: 1))
        .overlayPreferenceValue(WorkTimePickerAnchorPreferenceKey.self) { anchors in
            GeometryReader { geometry in
                if (showsStartPicker || showsShutdownPicker),
                   let startAnchor = anchors[.start],
                   let cutoffAnchor = anchors[.cutoff] {
                    let startFrame = geometry[startAnchor]
                    let cutoffFrame = geometry[cutoffAnchor]
                    WorkTimePickerMenuOverlay(
                        activeAnchor: showsStartPicker ? .start : .cutoff,
                        anchorDate: date,
                        startFrame: startFrame,
                        cutoffFrame: cutoffFrame,
                        containerWidth: geometry.size.width,
                        startSelection: selectedStartMinutes,
                        cutoffSelection: selectedShutdownMinutes,
                        selectStart: { minutes in
                            selectedStartMinutes = store.setDailyPlanningStart(
                                minutes: minutes,
                                on: date
                            )
                            selectedShutdownMinutes = store.dailyPlanningCutoffMinutes(on: date)
                            store.ensureDailyPlanningTaskSchedule(on: date)
                        },
                        selectCutoff: { minutes in
                            selectedShutdownMinutes = store.setDailyPlanningCutoff(
                                minutes: minutes,
                                on: date
                            )
                            selectedStartMinutes = store.dailyPlanningStartMinutes(on: date)
                            store.ensureDailyPlanningTaskSchedule(on: date)
                        },
                        dismiss: {
                            showsStartPicker = false
                            showsShutdownPicker = false
                        }
                    )
                }
            }
        }
        .zIndex(showsStartPicker || showsShutdownPicker ? 5 : 0)
        .animation(.easeOut(duration: 0.12), value: showsStartPicker)
        .animation(.easeOut(duration: 0.12), value: showsShutdownPicker)
    }

    private func workTimeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func relativeDayTitle(_ date: Date) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInTomorrow(date) { return "明天" }
        if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: .now)),
           calendar.isDate(date, inSameDayAs: dayAfterTomorrow) {
            return "后天"
        }
        return date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).month().day()
        )
    }

}

private struct WorkTimePickerMenuOverlay: View {
    let activeAnchor: WorkTimePickerAnchor
    let anchorDate: Date
    let startFrame: CGRect
    let cutoffFrame: CGRect
    let containerWidth: CGFloat
    let startSelection: Int
    let cutoffSelection: Int
    let selectStart: (Int) -> Void
    let selectCutoff: (Int) -> Void
    let dismiss: () -> Void
    private let calendar = Calendar.current

    var body: some View {
        let activeFrame = activeAnchor == .start ? startFrame : cutoffFrame
        let menuWidth = min(WeekflowLayout.workCutoffPopoverWidth, containerWidth)
        let menuLeading = min(
            max(activeFrame.midX - menuWidth / 2, 0),
            max(containerWidth - menuWidth, 0)
        )
        let menuTop = activeFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        let menuFrame = CGRect(
            x: menuLeading,
            y: menuTop,
            width: menuWidth,
            height: WeekflowLayout.workCutoffPopoverHeight
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame, startFrame, cutoffFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            ScrollClockTimePopover(
                selection: selectionDate,
                anchorDate: anchorDate,
                minuteRange: activeAnchor == .start
                    ? DailyPlanningState.minimumStartMinutes...DailyPlanningState.maximumStartMinutes
                    : DailyPlanningState.minimumCutoffMinutes...DailyPlanningState.maximumCutoffMinutes,
                minuteStep: activeAnchor == .start
                    ? DailyPlanningState.startStepMinutes
                    : DailyPlanningState.cutoffStepMinutes,
                allowsUnset: false,
                title: activeAnchor == .start ? "选择工作开始时间" : "选择工作截止时间",
                select: { selection in
                    guard let selection else { return }
                    let minutes = minuteValue(for: selection)
                    if activeAnchor == .start {
                        selectStart(minutes)
                    } else {
                        selectCutoff(minutes)
                    }
                }
            )
            .frame(width: menuWidth, height: WeekflowLayout.workCutoffPopoverHeight)
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 6))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 6)
                    .fill(WeekflowPalette.surface)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 6)
                    .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
            .position(x: menuFrame.midX, y: menuFrame.midY)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))

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
                    x: activeFrame.midX,
                    y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
    }

    private var selectionDate: Date {
        let minutes = activeAnchor == .start ? startSelection : cutoffSelection
        let day = calendar.startOfDay(for: anchorDate)
        return calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
    }

    private func minuteValue(for date: Date) -> Int {
        let anchorDay = calendar.startOfDay(for: anchorDate)
        if calendar.startOfDay(for: date) > anchorDay { return 24 * 60 }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

struct DailyShutdownView: View {
    @Bindable var store: WeekflowStore
    @State private var phase = 0
    @State private var originalTaskIDs: Set<UUID> = []
    @State private var summary = ""
    @State private var hasLoadedSummary = false
    @State private var summarySaveTask: Task<Void, Never>?

    init(store: WeekflowStore, initialPhase: Int = 0) {
        self.store = store
        _phase = State(initialValue: initialPhase)
    }

    private var reviewEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        if originalTaskIDs.isEmpty { return shutdownSourceEntries }
        return store.activeTasks.filter { originalTaskIDs.contains($0.task.id) }
    }

    private var shutdownSourceEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        var seenTaskIDs = Set<UUID>()
        return (store.todayTasks + store.completionCreditTasks(on: .now)).filter {
            seenTaskIDs.insert($0.task.id).inserted
        }
    }

    var body: some View {
        Group {
            if phase == 0 {
                GeometryReader { proxy in
                    let columnWidth = WeekflowLayout.threeColumnWidth(
                        for: proxy.size.width,
                        columnSpacing: WeekflowLayout.dailyWorkspaceColumnSpacing
                    )
                    HStack(alignment: .top, spacing: WeekflowLayout.dailyWorkspaceColumnSpacing) {
                        reviewSummaryColumn
                            .frame(width: columnWidth)
                        reviewedTaskColumn(
                            title: "已完成",
                            entries: completedEntries,
                            emptyText: "今天还没有完成任务"
                        )
                        .frame(width: columnWidth)
                        reviewedTaskColumn(
                            title: "未完成",
                            entries: unfinishedEntries,
                            emptyText: "今天没有未完成任务"
                        )
                        .frame(width: columnWidth)
                    }
                }
            } else {
                summaryEditor
            }
        }
        .onAppear {
            if originalTaskIDs.isEmpty {
                originalTaskIDs = Set(shutdownSourceEntries.map { $0.task.id })
            }
            loadOrPrepareSummaryIfNeeded()
        }
        .onDisappear {
            summarySaveTask?.cancel()
            if hasLoadedSummary { store.saveDailySummary(summary, on: .now) }
        }
        .background(WeekflowPalette.canvas)
    }

    private var progressedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { $0.task.hasExecutionProgress }
    }

    private var notStartedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { !$0.task.hasExecutionProgress }
    }

    private var completedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { $0.task.status == .completed }
    }

    private var unfinishedEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        reviewEntries.filter { $0.task.status != .completed }
    }

    private var reviewSummaryColumn: some View {
        PlanningInstructionColumn(
            title: "今日回顾",
            detail: "看看今天已经推进了什么，还有哪些事项尚未开始。",
            backTitle: nil,
            nextTitle: "下一步",
            back: nil,
            next: {
                prepareSummary()
                phase = 1
            }
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    ShutdownTimeMetric(
                        title: "用时",
                        minutes: reviewEntries.reduce(0) {
                            $0 + DailyShutdownTimeDistribution.reviewMinutes(for: $1.task)
                        },
                        tint: WeekflowPalette.objective
                    )
                    ShutdownTimeMetric(
                        title: "计划",
                        minutes: reviewEntries.reduce(0) { $0 + $1.task.estimatedMinutes },
                        tint: WeekflowPalette.secondaryText
                    )
                }

                Text("时间花在哪里")
                    .font(.system(size: 14, weight: .semibold))
                ChannelTimeDonut(entries: reviewEntries, store: store)
                    .frame(height: 236)
            }
        }
    }

    private func reviewedTaskColumn(
        title: String,
        entries: [(goal: WeeklyGoal, task: WeekTask)],
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
            DailyWorkspaceColumnHeader(
                title: title,
                detail: "今日任务",
                badge: "\(entries.count)"
            ) {
                EmptyView()
            }
            ShutdownTaskGroupColumn(
                entries: entries,
                emptyText: emptyText,
                store: store
            )
        }
        .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var summaryEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PlanningNavigationButton(
                    title: "返回",
                    role: .secondary,
                    action: { phase = 0 }
                )
                .frame(width: 88)
                Spacer()
                Text("今日总结")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Color.clear.frame(width: 88, height: WeekflowLayout.primaryActionHeight)
            }
            TextEditor(text: Binding(
                get: { summary },
                set: { newValue in
                    summary = newValue
                    scheduleSummarySave()
                }
            ))
            .font(.system(size: 14))
            .padding(14)
            .background(WeekflowPalette.button, in: WeekflowRoundedRectangle(cornerRadius: 10))
            .overlay(WeekflowRoundedRectangle(cornerRadius: 10).stroke(WeekflowPalette.border, lineWidth: 1))
        }
        .padding(36)
    }

    private func prepareSummary() {
        if let saved = store.dailySummary(on: .now), !saved.content.isEmpty {
            summary = saved.content
        } else {
            summary = summaryTemplate(reviewEntries)
            store.saveDailySummary(summary, on: .now)
        }
        hasLoadedSummary = true
    }

    private func scheduleSummarySave() {
        summarySaveTask?.cancel()
        let content = summary
        summarySaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            store.saveDailySummary(content, on: .now)
        }
    }

    private func loadOrPrepareSummaryIfNeeded() {
        guard !hasLoadedSummary else { return }
        if let saved = store.dailySummary(on: .now) {
            summary = saved.content
            hasLoadedSummary = true
        } else if phase > 0 {
            prepareSummary()
        }
    }

    private func summaryTemplate(_ entries: [(goal: WeeklyGoal, task: WeekTask)]) -> String {
        DailyShutdownSummaryBuilder.build(
            entries: entries,
            focusMinutes: store.focusMinutes(on: .now),
            channelTitle: { store.channel(for: $0)?.title ?? "未分类" }
        )
    }
}

private struct ShutdownTaskGroupColumn: View {
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    let emptyText: String
    @Bindable var store: WeekflowStore

    var body: some View {
        GeometryReader { proxy in
            let taskScrollViewportWidth = WeekflowLayout.homeTaskScrollViewportWidth(
                for: proxy.size.width
            )
            let showsVerticalScroller = WeekflowLayout.homeShowsVerticalScroller(
                taskCount: entries.count,
                expandedAdditionalHeight: 0,
                viewportHeight: proxy.size.height
            )
            let taskCardWidth = WeekflowLayout.homeTaskCardWidth(
                for: proxy.size.width,
                showsVerticalScroller: showsVerticalScroller
            )

            ScrollView(.vertical) {
                LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                    ForEach(entries, id: \.task.id) { entry in
                        let rolloverAction = rolloverAction(for: entry)
                        SunsamaTaskCard(
                            entry: entry,
                            store: store,
                            dragSourceDate: .now,
                            compactHeight: WeekflowLayout.homeTaskCardHeight,
                            showsDateControl: false,
                            showsEstimatedDurationMenu: .constant(false),
                            showsStartTimeMenu: .constant(false),
                            showsDateMenu: .constant(false),
                            showsChannelMenu: .constant(false),
                            showsPriorityMenu: .constant(false),
                            auxiliaryActionSymbol: rolloverAction == nil ? nil : "arrow.right",
                            auxiliaryActionHelp: "移到明天",
                            auxiliaryAction: rolloverAction
                        )
                    }
                    if entries.isEmpty {
                        Text(emptyText)
                            .font(.system(size: 11))
                            .foregroundStyle(WeekflowPalette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    }
                }
                .frame(width: taskCardWidth, alignment: .topLeading)
                .frame(minHeight: 70, alignment: .topLeading)
                .background(
                    ZeroInsetVerticalScroller(
                        isVisible: showsVerticalScroller,
                        columnWidth: taskScrollViewportWidth,
                        scrollRequest: nil,
                        onTrackWidthChange: { _ in }
                    )
                )
            }
            .frame(
                width: taskScrollViewportWidth,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .scrollIndicators(.visible)
        }
    }

    private func rolloverAction(
        for entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> (() -> Void)? {
        guard entry.task.status != .completed,
              !isScheduled(entry.task, on: tomorrow) else { return nil }
        return {
            store.rolloverTaskManually(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                from: .now,
                to: tomorrow
            )
        }
    }

    private var tomorrow: Date {
        Calendar.current.date(
            byAdding: .day,
            value: 1,
            to: Calendar.current.startOfDay(for: .now)
        ) ?? .now
    }

    private func isScheduled(_ task: WeekTask, on date: Date) -> Bool {
        let calendar = Calendar.current
        return task.plannedDate.map {
            calendar.isDate($0, inSameDayAs: date)
        } == true || task.isAssigned(on: date, calendar: calendar)
    }
}

private struct PlanningInstructionColumn<Supplement: View>: View {
    let title: String
    let detail: String
    let backTitle: String?
    let nextTitle: String
    let back: (() -> Void)?
    let next: () -> Void
    @ViewBuilder let supplement: () -> Supplement

    var body: some View {
        VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
            DailyWorkspaceColumnHeader(title: title, detail: detail, badge: nil) {
                EmptyView()
            }
            supplement()
            Spacer()
            HStack(spacing: 8) {
                if let backTitle, let back {
                    PlanningNavigationButton(
                        title: backTitle,
                        role: .secondary,
                        action: back
                    )
                    .frame(maxWidth: .infinity)
                }
                PlanningNavigationButton(
                    title: nextTitle,
                    role: .primary,
                    action: next
                )
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DailyWorkspaceColumnHeader<Trailing: View>: View {
    let title: String
    let detail: String
    let badge: String?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                Spacer(minLength: 6)
                trailing()
            }
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: WeekflowLayout.dailyWorkspaceHeaderHeight,
            maxHeight: WeekflowLayout.dailyWorkspaceHeaderHeight,
            alignment: .topLeading
        )
    }
}

private struct PlanningNavigationButton: View {
    enum Role {
        case primary
        case secondary
    }

    let title: String
    let role: Role
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(role == .primary ? .white : WeekflowPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: WeekflowLayout.primaryActionHeight)
                .background(background, in: WeekflowRoundedRectangle(cornerRadius: 8))
                .overlay(
                    WeekflowRoundedRectangle(cornerRadius: 8)
                        .stroke(role == .secondary ? border : .clear)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var background: Color {
        switch role {
        case .primary:
            isHovering ? WeekflowPalette.objective.opacity(0.86) : WeekflowPalette.objective
        case .secondary:
            isHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover
        }
    }

    private var border: Color {
        isHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border
    }
}

private struct PlanningDropRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct PlanningSortMenuAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct PlanningTaskList: View {
    let title: String
    let date: Date
    @Bindable var store: WeekflowStore
    @Binding var draggedTaskToken: TaskDragToken?
    @Binding var newlyAssignedTaskID: UUID?
    let addTask: () -> Void
    @State private var isDropTarget = false
    @State private var taskRowFrames: [UUID: CGRect] = [:]
    @State private var poolDropPreview: PlanningPoolDropPreview?
    @State private var timerScrollRequest: VerticalScrollRequest?
    @State private var taskExpansionHeights: [UUID: CGFloat] = [:]
    @State private var expandedDurationTaskIDs: Set<UUID> = []
    @State private var reservedDurationMenuTaskID: UUID?
    @State private var pendingDurationMenuScrollTaskID: UUID?
    @State private var presentedStartTimeTaskIDs: Set<UUID> = []
    @State private var pendingStartTimeMenuAdjustmentTaskID: UUID?
    @State private var presentedChannelTaskIDs: Set<UUID> = []
    @State private var pendingChannelMenuAdjustmentTaskID: UUID?
    @State private var presentedPriorityTaskIDs: Set<UUID> = []
    @State private var pendingPriorityMenuAdjustmentTaskID: UUID?
    @State private var pendingTimerPanelAdjustmentTaskID: UUID?
    @State private var taskRowFrameCache = HomeTaskRowFrameCache()
    @State private var showsSortMenu = false
    @State private var isSortButtonHovering = false
    @State private var verticalScrollerTrackWidth = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: .legacy
    )

    private var dragCoordinateSpace: String {
        "daily-planning-drop-\(Int(date.timeIntervalSinceReferenceDate))"
    }

    private var taskScrollCoordinateSpace: String {
        "daily-planning-scroll-\(Int(date.timeIntervalSinceReferenceDate))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WeekflowLayout.dailyWorkspaceContentSpacing) {
            DailyWorkspaceColumnHeader(
                title: title,
                detail: date.dayLabel,
                badge: nil
            ) {
                Button {
                    toggleSortMenu()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(
                            showsSortMenu || isSortButtonHovering
                                ? WeekflowPalette.surfaceHover
                                : .clear,
                            in: WeekflowRoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .foregroundStyle(WeekflowPalette.iconDefault)
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 6))
                .anchorPreference(
                    key: PlanningSortMenuAnchorPreferenceKey.self,
                    value: .bounds,
                    transform: { $0 }
                )
                .onHover { isSortButtonHovering = $0 }
                .help("任务排序")
            }
            GeometryReader { proxy in
                let cardContentWidth = WeekflowLayout.homeCardContentWidth(for: proxy.size.width)
                let taskScrollViewportWidth = WeekflowLayout.homeTaskScrollViewportWidth(
                    for: proxy.size.width
                )
                let displayedEntries = planningDisplayedEntries(
                    store: store,
                    date: date,
                    preview: poolDropPreview
                )
                VStack(alignment: .leading, spacing: 10) {
                    HomeAddTaskButton(action: addTask)
                        .frame(width: cardContentWidth, alignment: .leading)
                    GeometryReader { taskArea in
                        let expandedAdditionalHeight = taskExpansionHeights.values.reduce(0, +)
                            + durationMenuOverflowHeight(in: displayedEntries)
                            + startTimeMenuOverflowHeight(in: displayedEntries)
                            + channelMenuOverflowHeight(in: displayedEntries)
                            + priorityMenuOverflowHeight(in: displayedEntries)
                            + timerPanelBottomReserve
                        let showsVerticalScroller = WeekflowLayout.homeShowsVerticalScroller(
                            taskCount: displayedEntries.count,
                            expandedAdditionalHeight: expandedAdditionalHeight,
                            viewportHeight: taskArea.size.height
                        )
                        let taskCardWidth = WeekflowLayout.homeTaskCardWidth(
                            for: proxy.size.width,
                            showsVerticalScroller: showsVerticalScroller
                        )

                        ScrollViewReader { scrollProxy in
                            ScrollView(.vertical) {
                                LazyVStack(spacing: WeekflowLayout.homeTaskCardSpacing) {
                                    ForEach(displayedEntries, id: \.task.id) { entry in
                                        SunsamaTaskCard(
                                            entry: entry,
                                            store: store,
                                            dragSourceDate: date,
                                            compactHeight: WeekflowLayout.homeTaskCardHeight,
                                            showsDateControl: false,
                                            showsEstimatedDurationMenu: Binding(
                                                get: { expandedDurationTaskIDs.contains(entry.task.id) },
                                                set: {
                                                    setDurationMenuPresented(
                                                        $0,
                                                        taskID: entry.task.id,
                                                        viewportHeight: taskArea.size.height
                                                    )
                                                }
                                            ),
                                            showsStartTimeMenu: Binding(
                                                get: { presentedStartTimeTaskIDs.contains(entry.task.id) },
                                                set: { setStartTimeMenuPresented($0, taskID: entry.task.id) }
                                            ),
                                            showsChannelMenu: Binding(
                                                get: { presentedChannelTaskIDs.contains(entry.task.id) },
                                                set: { setChannelMenuPresented($0, taskID: entry.task.id) }
                                            ),
                                            showsPriorityMenu: Binding(
                                                get: { presentedPriorityTaskIDs.contains(entry.task.id) },
                                                set: { setPriorityMenuPresented($0, taskID: entry.task.id) }
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
                                            openTask: {}
                                        )
                                        .id(entry.task.id)
                                        .background {
                                            GeometryReader { row in
                                                Color.clear
                                                    .preference(
                                                        key: PlanningDropRowFramePreferenceKey.self,
                                                        value: [
                                                            entry.task.id: row.frame(in: .named(dragCoordinateSpace))
                                                        ]
                                                    )
                                                    .preference(
                                                        key: HomeTaskRowFramePreferenceKey.self,
                                                        value: [
                                                            entry.task.id: row.frame(in: .named(taskScrollCoordinateSpace))
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
                                        + durationMenuOverflowHeight(in: displayedEntries)
                                        + startTimeMenuOverflowHeight(in: displayedEntries)
                                        + channelMenuOverflowHeight(in: displayedEntries)
                                        + priorityMenuOverflowHeight(in: displayedEntries)
                                        + timerPanelBottomReserve
                                )
                                .frame(width: taskCardWidth, alignment: .topLeading)
                                .frame(minHeight: 70, alignment: .topLeading)
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
                                        let contentFrame = overlay.frame(in: .named(taskScrollCoordinateSpace))
                                        let viewportBottom = -contentFrame.minY + taskArea.size.height
                                        ZStack(alignment: .topLeading) {
                                            if let taskID = expandedDurationTaskIDs.first,
                                               let cardAnchor = anchors[.card(taskID)],
                                               let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                                let displayedSubtaskCount = entry.task.subtasks.lazy.filter {
                                                    !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                                }.count
                                                TaskCardDurationMenuOverlay(
                                                    entry: entry,
                                                    store: store,
                                                    cardFrame: overlay[cardAnchor],
                                                    durationButtonFrame: anchors[.durationButton(taskID)].map { overlay[$0] },
                                                    estimatedDurationButtonFrame: anchors[.estimatedDurationButton(taskID)].map { overlay[$0] },
                                                    cardWidth: taskCardWidth,
                                                    viewportBottom: viewportBottom,
                                                    minimumPresentationCardBottom: overlay[cardAnchor].minY
                                                        + WeekflowLayout.homeTaskCardHeight(
                                                            subtaskCount: displayedSubtaskCount,
                                                            timerExpanded: true
                                                        ),
                                                    dismiss: {
                                                        setDurationMenuPresented(
                                                            false,
                                                            taskID: taskID,
                                                            viewportHeight: taskArea.size.height
                                                        )
                                                    }
                                                )
                                            }

                                            if let taskID = pendingTimerPanelAdjustmentTaskID,
                                               let cardAnchor = anchors[.card(taskID)],
                                               expandedDurationTaskIDs.isEmpty,
                                               presentedStartTimeTaskIDs.isEmpty,
                                               presentedChannelTaskIDs.isEmpty,
                                               presentedPriorityTaskIDs.isEmpty {
                                                let cardBottom = overlay[cardAnchor].maxY
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
                            .coordinateSpace(name: taskScrollCoordinateSpace)
                            .scrollIndicators(.visible)
                            .contentShape(Rectangle())
                            .onChange(of: newlyAssignedTaskID) { _, taskID in
                                guard let taskID else { return }
                                DispatchQueue.main.async {
                                    withAnimation(.easeOut(duration: 0.22)) {
                                        scrollProxy.scrollTo(taskID, anchor: .bottom)
                                    }
                                    if newlyAssignedTaskID == taskID {
                                        newlyAssignedTaskID = nil
                                    }
                                }
                            }
                            .overlayPreferenceValue(TaskDurationMenuAnchorPreferenceKey.self) { anchors in
                                GeometryReader { overlay in
                                    if let taskID = presentedStartTimeTaskIDs.first,
                                       let cardAnchor = anchors[.card(taskID)],
                                       let controlAnchor = anchors[.startTimeButton(taskID)],
                                       let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                        TaskCardStartTimeMenuOverlay(
                                            entry: entry,
                                            store: store,
                                            anchorDate: date,
                                            cardFrame: overlay[cardAnchor],
                                            controlFrame: overlay[controlAnchor],
                                            viewportWidth: taskScrollViewportWidth,
                                            scrollerTrackWidth: verticalScrollerTrackWidth,
                                            viewportBottom: overlay.size.height,
                                            allowsUnset: false,
                                            dismiss: { setStartTimeMenuPresented(false, taskID: taskID) }
                                        )
                                    }

                                    if let taskID = presentedChannelTaskIDs.first,
                                       let cardAnchor = anchors[.card(taskID)],
                                       let controlAnchor = anchors[.channelButton(taskID)],
                                       let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                        TaskCardChannelMenuOverlay(
                                            entry: entry,
                                            store: store,
                                            cardFrame: overlay[cardAnchor],
                                            controlFrame: overlay[controlAnchor],
                                            viewportWidth: taskScrollViewportWidth,
                                            scrollerTrackWidth: verticalScrollerTrackWidth,
                                            viewportBottom: overlay.size.height,
                                            dismiss: { setChannelMenuPresented(false, taskID: taskID) }
                                        )
                                    }

                                    if let taskID = presentedPriorityTaskIDs.first,
                                       let cardAnchor = anchors[.card(taskID)],
                                       let controlAnchor = anchors[.priorityButton(taskID)],
                                       let entry = displayedEntries.first(where: { $0.task.id == taskID }) {
                                        TaskCardPriorityMenuOverlay(
                                            entry: entry,
                                            store: store,
                                            anchorDate: date,
                                            cardFrame: overlay[cardAnchor],
                                            controlFrame: overlay[controlAnchor],
                                            viewportWidth: taskScrollViewportWidth,
                                            scrollerTrackWidth: verticalScrollerTrackWidth,
                                            viewportBottom: overlay.size.height,
                                            dismiss: { setPriorityMenuPresented(false, taskID: taskID) }
                                        )
                                    }
                                }
                            }
                            .onPreferenceChange(HomeTaskRowFramePreferenceKey.self) {
                                taskRowFrameCache.frames = $0
                            }
                            .onPreferenceChange(TaskDurationMenuOverflowPreferenceKey.self) { overflow in
                                guard let overflow else { return }
                                if let taskID = pendingDurationMenuScrollTaskID,
                                   expandedDurationTaskIDs.contains(taskID) {
                                    pendingDurationMenuScrollTaskID = nil
                                    guard overflow > 0 else { return }
                                    requestVerticalScroll(by: overflow)
                                    return
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
                        }
                        .zIndex(hasActivePrimaryMenu ? 1 : 0)
                    }
                }
            }
        }
        .padding(.top, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.bottom, WeekflowLayout.dailyWorkspaceColumnTopInset)
        .padding(.horizontal, WeekflowLayout.dailyWorkspaceColumnHorizontalInset)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            isDropTarget ? WeekflowPalette.surfaceSelected.opacity(0.48) : .clear,
            in: WeekflowRoundedRectangle(cornerRadius: 10)
        )
        .contentShape(Rectangle())
        .coordinateSpace(name: dragCoordinateSpace)
        .onPreferenceChange(PlanningDropRowFramePreferenceKey.self) {
            taskRowFrames = $0
        }
        .onDrop(
            of: [.utf8PlainText],
            delegate: PlanningColumnTaskDropDelegate(
                draggedTaskToken: $draggedTaskToken,
                date: date,
                rowFrames: taskRowFrames,
                store: store,
                isDropTarget: $isDropTarget,
                poolDropPreview: $poolDropPreview,
                taskAssigned: { newlyAssignedTaskID = $0 }
            )
        )
        .overlayPreferenceValue(PlanningSortMenuAnchorPreferenceKey.self) { anchor in
            GeometryReader { geometry in
                if showsSortMenu, let anchor {
                    PlanningSortMenuOverlay(
                        controlFrame: geometry[anchor],
                        containerWidth: geometry.size.width,
                        sortByPriority: {
                            store.sortTasksByPriority(on: date)
                        },
                        sortByStartTime: {
                            store.sortTasksByStartTime(on: date)
                        },
                        dismiss: dismissSortMenu
                    )
                }
            }
        }
        .zIndex(showsSortMenu ? 6 : 0)
        .animation(.easeOut(duration: 0.12), value: showsSortMenu)
    }

    private var hasActivePrimaryMenu: Bool {
        !expandedDurationTaskIDs.isEmpty
            || !presentedStartTimeTaskIDs.isEmpty
            || !presentedChannelTaskIDs.isEmpty
            || !presentedPriorityTaskIDs.isEmpty
    }

    private func toggleSortMenu() {
        let shouldPresent = !showsSortMenu
        dismissDurationMenu()
        dismissStartTimeMenu()
        dismissChannelMenu()
        dismissPriorityMenu()
        withAnimation(.easeOut(duration: 0.12)) {
            showsSortMenu = shouldPresent
        }
    }

    private func dismissSortMenu() {
        withAnimation(.easeOut(duration: 0.12)) {
            showsSortMenu = false
        }
    }

    private var timerPanelBottomReserve: CGFloat {
        guard expandedDurationTaskIDs.isEmpty,
              reservedDurationMenuTaskID == nil,
              presentedStartTimeTaskIDs.isEmpty,
              presentedChannelTaskIDs.isEmpty,
              presentedPriorityTaskIDs.isEmpty,
              !taskExpansionHeights.isEmpty else { return 0 }
        return WeekflowLayout.taskDurationMenuViewportBottomClearance
    }

    private func durationMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = reservedDurationMenuTaskID,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskDurationMenuOverflow(
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func startTimeMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = presentedStartTimeTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskStartTimeMenuHeight,
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func channelMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = presentedChannelTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskChannelPopoverHeight(channelCount: store.activeChannels.count),
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func priorityMenuOverflowHeight(
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> CGFloat {
        guard let taskID = presentedPriorityTaskIDs.first,
              entries.contains(where: { $0.task.id == taskID }) else { return 0 }
        return WeekflowLayout.taskAnchoredMenuOverflow(
            menuHeight: WeekflowLayout.taskPriorityPopoverHeight,
            remainingCardHeights: remainingCardHeights(after: taskID, in: entries)
        )
    }

    private func setDurationMenuPresented(
        _ isPresented: Bool,
        taskID: UUID,
        viewportHeight: CGFloat
    ) {
        if isPresented {
            dismissSortMenu()
            dismissStartTimeMenu()
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
            dismissSortMenu()
            dismissDurationMenu()
            dismissChannelMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedStartTimeTaskIDs = [taskID]
            pendingStartTimeMenuAdjustmentTaskID = taskID
        } else {
            dismissStartTimeMenu(ifPresentedTaskID: taskID)
        }
    }

    private func setChannelMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissSortMenu()
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissPriorityMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedChannelTaskIDs = [taskID]
            pendingChannelMenuAdjustmentTaskID = taskID
        } else {
            dismissChannelMenu(ifPresentedTaskID: taskID)
        }
    }

    private func setPriorityMenuPresented(_ isPresented: Bool, taskID: UUID) {
        if isPresented {
            dismissSortMenu()
            dismissDurationMenu()
            dismissStartTimeMenu()
            dismissChannelMenu()
            pendingTimerPanelAdjustmentTaskID = nil
            presentedPriorityTaskIDs = [taskID]
            pendingPriorityMenuAdjustmentTaskID = taskID
        } else {
            dismissPriorityMenu(ifPresentedTaskID: taskID)
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

    private func remainingCardHeights(
        after taskID: UUID,
        in entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> [CGFloat] {
        guard let taskIndex = entries.firstIndex(where: { $0.task.id == taskID }) else { return [] }
        return entries.dropFirst(taskIndex + 1).map { entry in
            WeekflowLayout.homeTaskCardHeight + (taskExpansionHeights[entry.task.id] ?? 0)
        }
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
              let entry = planningDisplayedEntries(
                store: store,
                date: date,
                preview: poolDropPreview
              ).first(where: { $0.task.id == taskID }) else { return nil }
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

private struct PlanningSortMenuOverlay: View {
    let controlFrame: CGRect
    let containerWidth: CGFloat
    let sortByPriority: () -> Void
    let sortByStartTime: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let menuWidth = min(WeekflowLayout.taskPriorityPopoverWidth, containerWidth)
        let menuHeight = WeekflowLayout.taskPriorityPopoverRowHeight * 2 + 12
        let menuLeading = min(
            max(controlFrame.midX - menuWidth + 20, 0),
            max(containerWidth - menuWidth, 0)
        )
        let menuTop = controlFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        let menuFrame = CGRect(
            x: menuLeading,
            y: menuTop,
            width: menuWidth,
            height: menuHeight
        )
        let pointerX = min(
            max(controlFrame.midX, menuFrame.minX + 14),
            menuFrame.maxX - 14
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [controlFrame, menuFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                PlanningSortMenuRow(
                    icon: "flag",
                    title: "按优先级排序",
                    action: sortByPriority
                )
                PlanningSortMenuRow(
                    icon: "clock",
                    title: "按开始时间排序",
                    action: sortByStartTime
                )
            }
            .padding(6)
            .frame(width: menuWidth, height: menuHeight)
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .fill(WeekflowPalette.surface)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
            .position(x: menuFrame.midX, y: menuFrame.midY)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))

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
                    x: pointerX,
                    y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
    }
}

private struct PlanningSortMenuRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 8)
            .frame(height: WeekflowLayout.taskPriorityPopoverRowHeight)
            .background(
                isHovering ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}

private struct PlanningTaskPool: View {
    @Bindable var store: WeekflowStore
    let targetDate: Date?
    let assignmentDate: Date
    var fillsAvailableHeight = false
    let dragStarted: (TaskDragToken) -> Void
    let taskAssigned: (UUID) -> Void
    private let contentInset: CGFloat = 12
    private let cardWidthReduction: CGFloat = 10
    @State private var verticalScrollerTrackWidth = NSScroller.scrollerWidth(
        for: .regular,
        scrollerStyle: .legacy
    )

    private var poolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        store.weeklyPlanningPoolEntries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "tray")
                    .foregroundStyle(WeekflowPalette.iconDefault)
                Text("来自每周计划的任务池")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, contentInset)

            if poolEntries.isEmpty {
                Text("任务池为空，可在每周计划中添加任务。")
                    .font(.system(size: 11))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .padding(.vertical, 12)
                    .padding(.horizontal, contentInset)
            } else {
                GeometryReader { proxy in
                    let cardWidth = max(
                        proxy.size.width - verticalScrollerTrackWidth - cardWidthReduction,
                        1
                    )
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 7) {
                            ForEach(poolEntries, id: \.task.id) { entry in
                                PlanningTaskPoolCard(
                                    entry: entry,
                                    assignedToTarget: targetDate.map { entry.task.isAssigned(on: $0) } ?? false,
                                    store: store,
                                    dragStarted: dragStarted,
                                    assignToTarget: {
                                        if assignPlanningPoolTaskToBottom(
                                            store: store,
                                            goalID: entry.goal.id,
                                            taskID: entry.task.id,
                                            date: assignmentDate
                                        ) {
                                            taskAssigned(entry.task.id)
                                        }
                                    },
                                    removeFromTarget: {
                                        store.removeTaskAssignment(
                                            goalID: entry.goal.id,
                                            taskID: entry.task.id,
                                            from: assignmentDate
                                        )
                                    }
                                )
                            }
                        }
                        .frame(width: cardWidth, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .background(
                            ZeroInsetVerticalScroller(
                                isVisible: true,
                                columnWidth: proxy.size.width,
                                scrollRequest: nil,
                                onTrackWidthChange: { measuredWidth in
                                    guard abs(verticalScrollerTrackWidth - measuredWidth) >= 0.5 else {
                                        return
                                    }
                                    verticalScrollerTrackWidth = measuredWidth
                                }
                            )
                        )
                    }
                }
                .frame(maxHeight: fillsAvailableHeight ? .infinity : 220)
                .padding(.leading, contentInset)
                .padding(.bottom, contentInset)
            }
        }
        .padding(.top, contentInset)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 9))
        .overlay(WeekflowRoundedRectangle(cornerRadius: 9).stroke(WeekflowPalette.border))
    }
}

private struct PlanningTaskPoolCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let assignedToTarget: Bool
    @Bindable var store: WeekflowStore
    let dragStarted: (TaskDragToken) -> Void
    let assignToTarget: () -> Void
    let removeFromTarget: () -> Void
    @State private var isHovering = false
    @State private var isAssignmentControlHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.task.title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(entry.goal.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if assignedToTarget {
                    Button(action: removeFromTarget) {
                        Label("已添加", systemImage: "checkmark")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(
                                isAssignmentControlHovering
                                    ? WeekflowPalette.textPrimary
                                    : WeekflowPalette.complete
                            )
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(
                                isAssignmentControlHovering
                                    ? WeekflowPalette.complete.opacity(0.14)
                                    : .clear,
                                in: Capsule()
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .onHover { isAssignmentControlHovering = $0 }
                    .help("点击取消添加")
                } else if !entry.task.assignedDates.isEmpty {
                    Text("已安排 \(entry.task.assignedDates.count) 天")
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(WeekflowPalette.textMuted)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovering ? WeekflowPalette.surfaceHover : WeekflowPalette.appBackground,
            in: WeekflowRoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(isHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 5, y: 2)
        .animation(.easeOut(duration: 0.14), value: isHovering)
        .pointingHandCursor()
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .onTapGesture(count: 2, perform: assignToTarget)
        .onDrag {
            let token = TaskDragToken(goalID: entry.goal.id, taskID: entry.task.id)
            dragStarted(token)
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                Text(entry.goal.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WeekflowPalette.textMuted)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(width: 190, alignment: .leading)
            .frame(minHeight: 54, alignment: .leading)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong, lineWidth: 1)
            }
        }
        .help("拖动或双击添加到当天任务")
    }
}

struct PlanningPoolDropPreview: Equatable {
    let token: TaskDragToken
    let before: TaskReference?

    static func == (lhs: PlanningPoolDropPreview, rhs: PlanningPoolDropPreview) -> Bool {
        lhs.token.goalID == rhs.token.goalID
            && lhs.token.taskID == rhs.token.taskID
            && lhs.before == rhs.before
    }
}

private struct PlanningColumnTaskDropDelegate: DropDelegate {
    @Binding var draggedTaskToken: TaskDragToken?
    let date: Date
    let rowFrames: [UUID: CGRect]
    let store: WeekflowStore
    @Binding var isDropTarget: Bool
    @Binding var poolDropPreview: PlanningPoolDropPreview?
    var taskAssigned: (UUID) -> Void = { _ in }

    func validateDrop(info: DropInfo) -> Bool {
        draggedTaskToken != nil
    }

    func dropEntered(info: DropInfo) {
        guard draggedTaskToken?.sourceDate == nil else {
            homeDelegate.dropEntered(info: info)
            return
        }
        isDropTarget = true
        updatePoolPreview(at: info.location.y)
    }

    func dropExited(info: DropInfo) {
        guard draggedTaskToken?.sourceDate == nil else {
            homeDelegate.dropExited(info: info)
            return
        }
        isDropTarget = false
        poolDropPreview = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedTaskToken?.sourceDate == nil else {
            return homeDelegate.dropUpdated(info: info)
        }
        updatePoolPreview(at: info.location.y)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let token = draggedTaskToken else { return false }
        guard token.sourceDate == nil else {
            return homeDelegate.performDrop(info: info)
        }

        updatePoolPreview(at: info.location.y)
        let target = poolDropPreview?.before
        store.relocateTask(
            goalID: token.goalID,
            taskID: token.taskID,
            from: nil,
            to: date,
            persistImmediately: false
        )
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            store.reorderTask(
                goalID: token.goalID,
                taskID: token.taskID,
                before: target,
                on: date
            )
        }
        store.ensureDailyPlanningTaskSchedule(
            on: date,
            newlyAssigned: TaskReference(goalID: token.goalID, taskID: token.taskID)
        )
        store.activeDay = Calendar.current.startOfDay(for: date)
        taskAssigned(token.taskID)
        isDropTarget = false
        poolDropPreview = nil
        draggedTaskToken = nil
        return true
    }

    private var homeDelegate: HomeColumnTaskDropDelegate {
        HomeColumnTaskDropDelegate(
            draggedTaskToken: $draggedTaskToken,
            date: date,
            rowFrames: { rowFrames },
            store: store,
            isDropTarget: $isDropTarget
        )
    }

    private func updatePoolPreview(at y: CGFloat) {
        guard let token = draggedTaskToken else { return }
        let target = store.tasks(on: date).first { entry in
            entry.task.id != token.taskID
                && (rowFrames[entry.task.id]?.midY ?? -.infinity) > y
        }.map { TaskReference(goalID: $0.goal.id, taskID: $0.task.id) }
        let preview = PlanningPoolDropPreview(token: token, before: target)
        guard preview != poolDropPreview else { return }
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            poolDropPreview = preview
        }
    }
}

func planningDisplayedEntries(
    store: WeekflowStore,
    date: Date,
    preview: PlanningPoolDropPreview?
) -> [(goal: WeeklyGoal, task: WeekTask)] {
    var entries = store.tasks(on: date)
    guard let preview,
          let goal = store.goals.first(where: { $0.id == preview.token.goalID }),
          let task = goal.tasks.first(where: { $0.id == preview.token.taskID }) else {
        return entries
    }

    entries.removeAll { $0.task.id == preview.token.taskID }
    let previewEntry = (goal: goal, task: task)
    if let target = preview.before,
       let targetIndex = entries.firstIndex(where: {
           $0.goal.id == target.goalID && $0.task.id == target.taskID
       }) {
        entries.insert(previewEntry, at: targetIndex)
    } else {
        entries.append(previewEntry)
    }
    return entries
}

@discardableResult
func assignPlanningPoolTaskToBottom(
    store: WeekflowStore,
    goalID: UUID,
    taskID: UUID,
    date: Date
) -> Bool {
    guard let task = store.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }),
          !task.isAssigned(on: date) else { return false }
    store.relocateTask(
        goalID: goalID,
        taskID: taskID,
        from: nil,
        to: date,
        persistImmediately: false
    )
    store.reorderTask(
        goalID: goalID,
        taskID: taskID,
        before: nil,
        on: date
    )
    store.ensureDailyPlanningTaskSchedule(
        on: date,
        newlyAssigned: TaskReference(goalID: goalID, taskID: taskID)
    )
    store.activeDay = Calendar.current.startOfDay(for: date)
    return true
}

func removePlanningTaskFromDay(
    store: WeekflowStore,
    goalID: UUID,
    taskID: UUID,
    date: Date
) {
    guard let task = store.goals.first(where: { $0.id == goalID })?
        .tasks.first(where: { $0.id == taskID }) else { return }
    if task.isAssigned(on: date) {
        store.removeTaskAssignment(goalID: goalID, taskID: taskID, from: date)
    } else {
        store.moveTaskToBacklog(goalID: goalID, taskID: taskID, atTop: false)
    }
}

private struct ShutdownTimeMetric: View {
    let title: String
    let minutes: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                .font(.system(size: 19, weight: .semibold))
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(WeekflowPalette.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14), in: WeekflowRoundedRectangle(cornerRadius: 8))
    }
}

private struct ChannelTimeDonut: View {
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
    @Bindable var store: WeekflowStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ChartPalettePreferences.storageKey)
    private var chartPaletteRawValue = ChartPalettePreferences.defaultPreset

    private var chartPalette: ChartPalettePreset {
        ChartPalettePreferences.preset(for: chartPaletteRawValue)
    }

    private var slices: [(channel: TaskChannel?, minutes: Int)] {
        let grouped = Dictionary(grouping: entries) { $0.task.channelID }
        return grouped.map { channelID, values in
            let minutes = values.reduce(0) {
                $0 + DailyShutdownTimeDistribution.reviewMinutes(for: $1.task)
            }
            return (store.channel(for: channelID), minutes)
        }
        .filter { $0.minutes > 0 }
        .sorted { $0.minutes > $1.minutes }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Canvas { context, size in
                    let total = max(slices.reduce(0) { $0 + $1.minutes }, 1)
                    let diameter = min(size.width, size.height)
                    let rect = CGRect(
                        x: (size.width - diameter) / 2,
                        y: (size.height - diameter) / 2,
                        width: diameter,
                        height: diameter
                    ).insetBy(dx: 3, dy: 3)
                    var start = Angle.degrees(-90)
                    if slices.isEmpty {
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(WeekflowPalette.surfaceSelected.opacity(0.72))
                        )
                    } else {
                        for slice in slices {
                            let angle = 360 * Double(slice.minutes) / Double(total)
                            let end = start + .degrees(angle)
                            var path = Path()
                            path.move(to: CGPoint(x: rect.midX, y: rect.midY))
                            path.addArc(
                                center: CGPoint(x: rect.midX, y: rect.midY),
                                radius: rect.width / 2,
                                startAngle: start,
                                endAngle: end,
                                clockwise: false
                            )
                            path.closeSubpath()
                            context.fill(
                                path,
                                with: .color(chartPalette.taskColor(
                                    channelID: slice.channel?.id,
                                    channels: store.channels,
                                    colorScheme: colorScheme
                                ))
                            )
                            start = end
                        }
                    }
                }
                .frame(width: 166, height: 166)

                if slices.isEmpty {
                    Text("暂无计时")
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                }
            }

            if !slices.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 6
                ) {
                    ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(chartPalette.taskColor(
                                    channelID: slice.channel?.id,
                                    channels: store.channels,
                                    colorScheme: colorScheme
                                ))
                                .frame(width: 7, height: 7)
                            Text(slice.channel?.title ?? "未分类")
                                .lineLimit(1)
                            Text(slice.minutes.hourMinuteClockText)
                                .monospacedDigit()
                                .foregroundStyle(WeekflowPalette.textMuted)
                    }
                        .font(.system(size: 9.5))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
