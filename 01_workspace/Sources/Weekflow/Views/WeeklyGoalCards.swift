import SwiftUI

struct WeeklyGoalTreeCard: View {
    let goal: WeeklyGoal
    @Bindable var store: WeekflowStore
    let pasteWeekReference: Date
    let edit: () -> Void
    @State private var isHovering = false
    @State private var showsContextPopover = false

    private var goalChannelColor: Color? {
        store.channel(for: goal.channelID)?.color
    }

    private var goalCardFill: Color {
        goalChannelColor?.opacity(isHovering ? 0.13 : 0.075)
            ?? (isHovering ? WeekflowPalette.surfaceHover : .clear)
    }

    private var goalCardBorder: Color {
        goalChannelColor?.opacity(isHovering ? 0.62 : 0.34)
            ?? (isHovering ? WeekflowPalette.borderStrong : WeekflowPalette.border)
    }

    private var primaryTask: WeekTask? {
        guard let primaryTaskID = goal.primaryTaskID,
              let primaryTask = goal.tasks.first(where: { $0.id == primaryTaskID }) else { return nil }
        return primaryTask
    }

    private var totalEstimatedMinutes: Int {
        guard !goal.subgoals.isEmpty else {
            return primaryTask?.estimatedMinutes ?? goal.plannedMinutes
        }
        return goal.subgoals.reduce(0) { total, subgoal in
            total + estimatedMinutes(for: subgoal)
        }
    }

    private var completionCountText: String {
        if goal.subgoals.isEmpty {
            return "\(goal.completedAt == nil ? 0 : 1)/1"
        }
        return "\(goal.subgoals.filter(\.isCompleted).count)/\(goal.subgoals.count)"
    }

    private func estimatedMinutes(for subgoal: GoalSubgoal) -> Int {
        primaryTask?.subtasks.first(where: { $0.id == subgoal.id })?.plannedMinutes ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                WeekflowButton(action: edit) {
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 22, height: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(goal.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WeekflowPalette.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 10) {
                                Label(
                                    "预计 \(TaskTimeDisplay.estimated(minutes: totalEstimatedMinutes))",
                                    systemImage: "clock"
                                )
                                Label("完成 \(completionCountText)", systemImage: "checkmark.circle")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("\(Int(goal.progress * 100))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WeekflowPalette.textSecondary)
                            WeekflowDailyProgressTrack(
                                fraction: goal.progress,
                                hasProgress: goal.progress > 0,
                                accessibilityLabel: "周目标完成进度",
                                accessibilityValue: "已完成 \(Int(goal.progress * 100))%"
                            )
                            .frame(width: 72, height: WeekflowLayout.homeDailyProgressHeight)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, goal.subgoals.isEmpty ? 10 : 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                WeekflowButton {
                    store.setGoalCompleted(id: goal.id, completed: goal.progress < 1)
                } label: {
                    Image(systemName: goal.progress >= 1 ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(goal.progress >= 1 ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.top, 10)
                .help(goal.progress >= 1 ? "标记为未完成" : "标记为已完成")
            }

            ForEach(goal.subgoals) { subgoal in
                ZStack(alignment: .leading) {
                    WeekflowButton(action: edit) {
                        HStack(spacing: 12) {
                            Color.clear.frame(width: 22, height: 32)
                            Text(subgoal.title)
                                .font(.system(size: 13))
                                .strikethrough(subgoal.isCompleted)
                            Spacer()
                            Label(
                                "预计 \(TaskTimeDisplay.estimated(minutes: estimatedMinutes(for: subgoal)))",
                                systemImage: "clock"
                            )
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WeekflowPalette.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    WeekflowButton {
                        store.toggleSubgoal(goalID: goal.id, subgoalID: subgoal.id)
                    } label: {
                        Image(systemName: subgoal.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(subgoal.isCompleted ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                            .frame(width: 22, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
        }
        .background {
            WeekflowRoundedRectangle(cornerRadius: 10)
                .fill(WeekflowPalette.surface)
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 10)
                        .fill(goalCardFill)
                }
        }
        .background {
            TaskCardContextMenuAnchor(
                isPresented: $showsContextPopover,
                menuHeight: 178,
                onOpen: {}
            ) {
                WeeklyGoalContextPopover(
                    copy: {
                        store.copyGoalToClipboard(id: goal.id)
                        showsContextPopover = false
                    },
                    cut: {
                        store.copyGoalToClipboard(id: goal.id, cutsSource: true)
                        showsContextPopover = false
                    },
                    paste: {
                        _ = store.pasteGoalClipboard(
                            toWeekContaining: pasteWeekReference,
                            afterGoalID: goal.id
                        )
                        showsContextPopover = false
                    },
                    canPaste: store.hasGoalClipboard,
                    delete: {
                        store.deleteGoal(id: goal.id)
                        showsContextPopover = false
                    },
                    moveToNextWeek: {
                        store.moveGoalToNextWeek(id: goal.id)
                        showsContextPopover = false
                    }
                )
            }
        }
        .background {
            TaskCardKeyboardShortcutAnchor(
                isActive: isHovering || showsContextPopover,
                copy: {
                    store.copyGoalToClipboard(id: goal.id)
                    showsContextPopover = false
                },
                cut: {
                    store.copyGoalToClipboard(id: goal.id, cutsSource: true)
                    showsContextPopover = false
                },
                paste: {
                    _ = store.pasteGoalClipboard(
                        toWeekContaining: pasteWeekReference,
                        afterGoalID: goal.id
                    )
                    showsContextPopover = false
                },
                delete: {
                    store.deleteGoal(id: goal.id)
                    showsContextPopover = false
                },
                moveToNextWeek: {
                    store.moveGoalToNextWeek(id: goal.id)
                    showsContextPopover = false
                }
            )
        }
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 10)
                .stroke(goalCardBorder, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if let goalChannelColor {
                WeekflowRoundedRectangle(cornerRadius: 2)
                    .fill(goalChannelColor)
                    .frame(width: 3)
                    .padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { store.highlightedTask = nil }
        }
        .pointingHandCursor(coversDescendants: true)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

struct WeeklyTaskPoolCard: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let tint: Color
    @Bindable var store: WeekflowStore
    let calendarAnchorDate: Date
    var dragStarted: (TaskDragToken) -> Void = { _ in }
    @State private var isHovering = false
    @State private var showsAssignmentPicker = false
    @State private var isAssignmentButtonHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                WeekflowRoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 5, height: 22)
                Text(subgoalTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            Text(relationshipTitle)
                .font(.system(size: 10.5))
                .foregroundStyle(WeekflowPalette.textSecondary)
                .lineLimit(1)

            WeekflowButton {
                showsAssignmentPicker.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                    Text(assignmentActionLabel)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(
                    showsAssignmentPicker || isAssignmentButtonHovering
                        ? WeekflowPalette.objective
                        : WeekflowPalette.textSecondary
                )
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
                .contentShape(WeekflowRoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .onHover { isAssignmentButtonHovering = $0 }
            .background {
                TaskControlMenuAnchor(
                    isPresented: $showsAssignmentPicker,
                    menuSize: CGSize(width: 176, height: 274),
                    horizontalOffset: -WeekflowLayout.taskDurationMenuPointerWidth,
                    pointerCenterX: WeekflowLayout.taskDurationMenuPointerWidth * 1.5
                ) {
                    WeeklyTaskPoolDayPicker(
                        weekStart: calendarAnchorDate,
                        selectedDates: entry.task.assignedDates,
                        isUnset: entry.task.assignedDates.isEmpty && entry.task.plannedDate == nil,
                        toggle: toggleAssignment,
                        clear: clearAssignments
                    )
                    .frame(width: 176, height: 274, alignment: .topLeading)
                }
            }
        }
        .padding(8)
        .frame(width: 205, height: WeekflowLayout.weeklyTaskPoolCardHeight, alignment: .topLeading)
        .boxHoverChrome(
            isHovering: isHovering,
            cornerRadius: 9,
            fill: tint.opacity(0.09),
            border: tint.opacity(0.25),
            hoverBorder: tint.opacity(0.55)
        )
        .contentShape(WeekflowRoundedRectangle(cornerRadius: 9))
        .pointingHandCursor()
        .onDrag {
            let token = TaskDragToken(goalID: entry.goal.id, taskID: entry.task.id)
            dragStarted(token)
            return NSItemProvider(object: token.value as NSString)
        } preview: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    WeekflowRoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: 5, height: 22)
                    Text(subgoalTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(relationshipTitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .lineLimit(1)
                Label(assignmentActionLabel, systemImage: "calendar.badge.plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WeekflowPalette.objective)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(width: 205, height: WeekflowLayout.weeklyTaskPoolCardHeight, alignment: .topLeading)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 9))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 9).stroke(tint.opacity(0.45), lineWidth: 1)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovering = true
            case .ended:
                isHovering = false
            }
        }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var subgoalTitle: String {
        guard let subgoalID = entry.task.subgoalID,
              let subgoal = entry.goal.subgoals.first(where: { $0.id == subgoalID }) else {
            return entry.task.title
        }
        return subgoal.title
    }

    private var relationshipTitle: String {
        entry.task.subgoalID == nil ? " " : entry.goal.title
    }

    private var weekDates: [Date] {
        let start = SystemBusinessCalendar.current.calendar.startOfDay(for: calendarAnchorDate)
        return (0..<7).compactMap {
            SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    private var assignmentActionLabel: String {
        let calendar = SystemBusinessCalendar.current.calendar
        let selected = weekDates.filter { date in
            entry.task.assignedDates.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        guard !selected.isEmpty else { return "安排" }
        return selected.map {
            $0.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).weekday(.short))
        }.joined(separator: "、")
    }

    private func toggleAssignment(_ date: Date) {
        if entry.task.isAssigned(on: date) {
            store.removeTaskAssignment(goalID: entry.goal.id, taskID: entry.task.id, from: date)
        } else {
            store.assignTask(goalID: entry.goal.id, taskID: entry.task.id, to: date)
        }
    }

    private func clearAssignments() {
        store.unassignTask(goalID: entry.goal.id, taskID: entry.task.id)
    }
}

struct WeeklyTaskPoolDayPicker: View {
    let weekStart: Date
    let selectedDates: [Date]
    let isUnset: Bool
    let toggle: (Date) -> Void
    let clear: () -> Void

    private var dates: [Date] {
        let start = SystemBusinessCalendar.current.calendar.startOfDay(for: weekStart)
        return (0..<7).compactMap {
            SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: $0, to: start)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("安排日期")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WeekflowPalette.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 32)

            Divider()

            ForEach(dates, id: \.self) { date in
                WeeklyTaskPoolDayRow(
                    leadingText: weekdayText(for: date),
                    detailText: monthDayText(for: date),
                    selected: selectedDates.contains {
                        SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date)
                    },
                    action: { toggle(date) }
                )
            }

            Divider()

            WeeklyTaskPoolDayRow(
                leadingText: "不设置",
                detailText: nil,
                selected: isUnset,
                action: clear
            )
        }
        .frame(width: 176, height: 274, alignment: .topLeading)
        .background(WeekflowPalette.surface)
    }

    private func weekdayText(for date: Date) -> String {
        date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).weekday(.short)
        )
    }

    private func monthDayText(for date: Date) -> String {
        date.formatted(
            .dateTime.locale(Locale(identifier: "zh_CN")).month().day()
        )
    }
}

struct WeeklyTaskPoolDayRow: View {
    let leadingText: String
    let detailText: String?
    let selected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Text(leadingText)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .frame(width: 38, alignment: .leading)
                if let detailText {
                    Text(detailText)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .monospacedDigit()
                        .frame(width: 58, alignment: .leading)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.objective)
                }
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                isHovering || selected ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
        .padding(.horizontal, 4)
        .accessibilityLabel([leadingText, detailText].compactMap { $0 }.joined(separator: " "))
        .accessibilityValue(selected ? "已选择" : "未选择")
    }
}

