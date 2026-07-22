import SwiftUI

extension TaskDetailView {
    func detailMenuAction(
        _ title: String,
        symbol: String,
        tint: Color = WeekflowPalette.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5, weight: .regular))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                Spacer()
            }
            .foregroundStyle(tint)
            .frame(height: 30)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }

    func toggleMenu(_ menu: TaskDetailMenu) {
        activeMenu = activeMenu == menu ? nil : menu
    }

    func closeDetail() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    func toggleMoreMenu() {
        morePage = .actions
        toggleMenu(.more)
    }

    func detailMenuOverlay(
        _ menu: TaskDetailMenu,
        anchorFrame: CGRect,
        containerSize: CGSize,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> some View {
        let size = detailMenuSize(menu)
        let panelFrame = detailMenuPanelFrame(
            menu,
            anchorFrame: anchorFrame,
            containerSize: containerSize
        )

        return ZStack(alignment: .topLeading) {
            detailMenuContent(menu, entry: entry)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipShape(WeekflowRoundedRectangle(cornerRadius: 6))
                .background {
                    WeekflowRoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WeekflowPalette.surface)
                }
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            WeekflowPalette.borderStrong.opacity(0.85),
                            lineWidth: 1,
                            antialiased: true
                        )
                }
                .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
                .position(
                    x: panelFrame.midX,
                    y: panelFrame.midY
                )
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
                    x: anchorFrame.midX,
                    y: panelFrame.minY - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
        .zIndex(1_000)
    }

    func detailMenuPanelFrame(
        _ menu: TaskDetailMenu,
        anchorFrame: CGRect,
        containerSize: CGSize
    ) -> CGRect {
        let size = detailMenuSize(menu)
        let horizontalInset: CGFloat = 8
        let proposedX = anchorFrame.midX - size.width / 2
        let maximumX = max(containerSize.width - size.width - horizontalInset, horizontalInset)
        let panelX = min(max(proposedX, horizontalInset), maximumX)
        let panelTop = anchorFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        return CGRect(origin: CGPoint(x: panelX, y: panelTop), size: size)
    }

    func detailMenuSize(_ menu: TaskDetailMenu) -> CGSize {
        switch menu {
        case .channel:
            CGSize(
                width: WeekflowLayout.taskDetailChannelMenuWidth,
                height: WeekflowLayout.taskChannelPopoverHeight(channelCount: store.activeChannels.count)
            )
        case .priority:
            CGSize(
                width: WeekflowLayout.taskDetailPriorityMenuWidth,
                height: WeekflowLayout.taskPriorityPopoverHeight
            )
        case .startDate:
            CGSize(
                width: WeekflowLayout.taskDetailDateMenuWidth,
                height: WeekflowLayout.taskDetailCalendarMenuHeight
            )
        case .dueDate:
            CGSize(
                width: WeekflowLayout.taskDetailDateMenuWidth,
                height: WeekflowLayout.taskDetailCalendarMenuHeight
            )
        case .more:
            switch morePage {
            case .actions:
                CGSize(width: 188, height: target.isWeeklyGoalDetail ? 100 : 164)
            case .recurrence:
                CGSize(width: 188, height: 190)
            case .goalLink:
                CGSize(
                    width: 188,
                    height: min(CGFloat(store.activeGoals.count) * 34 + 50, 244)
                )
            }
        case .startTime, .actualTime, .estimatedTime,
             .subtaskActualTime, .subtaskEstimatedTime:
            CGSize(width: 176, height: 244)
        }
    }

    @ViewBuilder
    func detailMenuContent(
        _ menu: TaskDetailMenu,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> some View {
        switch menu {
        case .channel:
            TaskChannelPopover(
                channels: store.activeChannels,
                selectedChannelID: channelID,
                width: WeekflowLayout.taskDetailChannelMenuWidth,
                select: { selection in
                    channelID = selection
                    save(entry)
                },
                manage: {
                    activeMenu = nil
                    DispatchQueue.main.async {
                        CommandRouter.shared.send(.openChannelSettings)
                    }
                }
            )
        case .priority:
            TaskPriorityPopover(
                selectedPriority: priority,
                width: WeekflowLayout.taskDetailPriorityMenuWidth
            ) { selection in
                priority = selection
                save(entry)
            }
        case .startDate:
            TaskDatePopover(
                selectedDate: plannedDate,
                exactWidth: WeekflowLayout.taskDetailDateMenuWidth,
                exactHeight: WeekflowLayout.taskDetailCalendarMenuHeight,
                showsQuickActions: false,
                highlightsToday: false,
                moveByDays: { moveStartDate(by: $0, entry: entry) },
                moveToDate: { setStartDate($0, entry: entry) }
            )
        case .dueDate:
            TaskDatePopover(
                selectedDate: dueDate,
                exactWidth: WeekflowLayout.taskDetailDateMenuWidth,
                exactHeight: WeekflowLayout.taskDetailCalendarMenuHeight,
                showsQuickActions: false,
                highlightsToday: false,
                minimumDate: plannedDate,
                highlightedRangeStart: hasDueDate ? plannedDate : nil,
                highlightedRangeEnd: hasDueDate ? dueDate : nil,
                moveByDays: { moveDueDate(by: $0, entry: entry) },
                moveToDate: { setDueDate($0, entry: entry) }
            )
        case .more:
            moreMenuContent(entry)
        case .startTime:
            ScrollClockTimePopover(
                selection: hasStartTime ? startTime : nil,
                anchorDate: plannedDate
            ) { selection in
                setStartTime(selection, entry: entry)
            }
        case .actualTime:
            ScrollDurationPopover(
                minutes: Binding(
                    get: {
                        TaskActualMinutesPolicy.resolved(
                            manual: actualMinutes,
                            live: store.liveTaskActualMinutes(goalID: entry.goal.id, taskID: entry.task.id),
                            timerIsRunning: isTimerRunning(entry)
                        )
                    },
                    set: { setActualMinutes($0, entry: entry) }
                ),
                range: 0...960,
                step: 15,
                title: "实际时间"
            )
        case .estimatedTime:
            ScrollDurationPopover(
                minutes: Binding(
                    get: { estimatedMinutes },
                    set: { setEstimatedMinutes($0, entry: entry) }
                ),
                range: 0...480,
                step: 15,
                title: "预计时间"
            )
        case let .subtaskActualTime(subtaskID):
            ScrollDurationPopover(
                minutes: Binding(
                    get: { subtask(entry, id: subtaskID)?.actualMinutes ?? 0 },
                    set: { setSubtaskActualMinutes($0, subtaskID: subtaskID, entry: entry) }
                ),
                range: 0...960,
                step: 15,
                title: "真实时间"
            )
        case let .subtaskEstimatedTime(subtaskID):
            ScrollDurationPopover(
                minutes: Binding(
                    get: { subtask(entry, id: subtaskID)?.plannedMinutes ?? 0 },
                    set: { setSubtaskPlannedMinutes($0, subtaskID: subtaskID, entry: entry) }
                ),
                range: 0...480,
                step: 15,
                title: "预计时间"
            )
        }
    }

    @ViewBuilder
    func moreMenuContent(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        switch morePage {
        case .actions:
            VStack(spacing: 0) {
                HStack {
                    Text("其他操作")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textMuted)
                    Spacer()
                }
                .frame(height: 26)
                .padding(.horizontal, 8)
                if !target.isWeeklyGoalDetail {
                    detailMenuAction("重复功能", symbol: "arrow.triangle.2.circlepath") {
                        morePage = .recurrence
                    }
                    detailMenuAction("建立目标联系", symbol: "target") {
                        morePage = .goalLink
                    }
                }
                detailMenuAction("复制", symbol: "doc.on.doc") {
                    save(entry)
                    if target.isWeeklyGoalDetail {
                        _ = store.duplicateGoal(id: entry.goal.id)
                    } else {
                        _ = store.duplicateTask(
                            goalID: entry.goal.id,
                            taskID: entry.task.id,
                            persistImmediately: false
                        )
                    }
                }
                detailMenuAction("删除", symbol: "trash") {
                    guard !isClosing else { return }
                    autosaveTask?.cancel()
                    activeMenu = nil
                    isClosing = true
                    closeDetail()
                    DispatchQueue.main.async {
                        if target.isWeeklyGoalDetail {
                            store.deleteGoal(id: entry.goal.id)
                        } else {
                            store.deleteTask(goalID: entry.goal.id, taskID: entry.task.id)
                        }
                    }
                }
            }
            .padding(6)
            .background(WeekflowPalette.surface)
        case .recurrence:
            VStack(spacing: 0) {
                detailMenuBackHeader("重复功能")
                detailMenuSelectionRow(
                    "不重复",
                    symbol: "minus.circle",
                    selected: entry.task.recurringRule == nil
                ) {
                    setRecurrence(nil, entry: entry)
                }
                ForEach(RecurringFrequency.allCases) { frequency in
                    detailMenuSelectionRow(
                        frequency.label,
                        symbol: "arrow.triangle.2.circlepath",
                        selected: entry.task.recurringRule?.frequency == frequency
                    ) {
                        setRecurrence(RecurringRule(frequency: frequency), entry: entry)
                    }
                }
            }
            .padding(6)
            .background(WeekflowPalette.surface)
        case .goalLink:
            VStack(spacing: 0) {
                detailMenuBackHeader("建立目标联系")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.activeGoals) { goal in
                            detailMenuSelectionRow(
                                goal.title,
                                symbol: "target",
                                selected: goal.id == entry.goal.id
                            ) {
                                guard goal.id != entry.goal.id else { return }
                                moveTaskResponsively(entry, toGoalID: goal.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
            .padding(6)
            .background(WeekflowPalette.surface)
        }
    }

    func detailMenuBackHeader(_ title: String) -> some View {
        WeekflowButton {
            morePage = .actions
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .foregroundStyle(WeekflowPalette.textSecondary)
            .frame(height: 30)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }

    func detailMenuSelectionRow(
        _ title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                Text(title).lineLimit(1)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? WeekflowPalette.primaryText : WeekflowPalette.textSecondary)
            .frame(height: 30)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
    }
}
