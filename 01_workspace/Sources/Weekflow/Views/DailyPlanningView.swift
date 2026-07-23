import SwiftUI

import AppKit
import SwiftUI

enum WorkTimePickerAnchor: Hashable {
    case start
    case cutoff
}

struct WorkTimePickerAnchorPreferenceKey: PreferenceKey {
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
    @Environment(\.businessCalendar) private var businessCalendar
    private var calendar: Calendar { businessCalendar.calendar }

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
                    WeekflowButton {
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
                WeekflowButton {
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

            WeekflowButton {
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

struct WorkTimePickerMenuOverlay: View {
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
    @Environment(\.businessCalendar) private var businessCalendar
    private var calendar: Calendar { businessCalendar.calendar }

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

