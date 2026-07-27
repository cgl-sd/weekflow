import SwiftUI

extension TaskDetailView {
    func detailContent(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titleAndTiming(entry)
            subtaskList(entry)
                .padding(.top, 18)
            descriptionEditor(entry)
                .padding(.top, 24)
            historyTimeline(entry.task)
                .padding(.top, 30)
        }
        .detailPageContentLayout()
    }

    func titleAndTiming(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(alignment: .center, spacing: 24) {
            titleEditor(entry)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            timingControls(entry)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    func titleEditor(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(alignment: .center, spacing: 12) {
            WeekflowButton {
                store.toggleTask(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    persistImmediately: false
                )
            } label: {
                Image(systemName: entry.task.status == .completed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(entry.task.status == .completed ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            TextField(target.isWeeklyGoalDetail ? "目标标题" : "任务标题", text: $title, axis: .vertical)
                .font(.system(size: 25, weight: .regular))
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .onChange(of: title) { _, _ in scheduleAutosave(entry) }
                .onSubmit { save(entry) }
        }
    }

    func timingControls(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        HStack(spacing: WeekflowLayout.taskDetailTimeColumnSpacing) {
            if !target.isWeeklyGoalDetail {
                startTimeEditor
            }
            // P1-3 fix: only subscribe to TimelineView when the timer is running.
            // Static display when not running; 60s refresh when running.
            if isTimerRunning(entry) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    timeMetricEditor(
                        title: "真实时间",
                        value: detailActualTime(at: context.date),
                        menu: .actualTime
                    )
                    .task(id: detailTimerMinuteBucket(entry, at: context.date)) {
                        store.synchronizeActiveTaskTimer(at: context.date)
                    }
                }
            } else {
                timeMetricEditor(
                    title: "真实时间",
                    value: detailActualTime(at: .now),
                    menu: .actualTime
                )
            }
            timeMetricEditor(
                title: "预计时间",
                value: TaskTimeDisplay.estimated(minutes: estimatedMinutes),
                menu: .estimatedTime
            )
        }
        .font(.system(size: 12.5))
        .foregroundStyle(WeekflowPalette.secondaryText)
        .frame(width: WeekflowLayout.taskDetailTimingWidth)
    }

    var startTimeEditor: some View {
        WeekflowButton { toggleMenu(.startTime) } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .medium))
                Text(hasStartTime ? ScrollClockTimePopover.clockText(for: startTime) : "开始时间")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(WeekflowPalette.textMuted)
            .padding(.horizontal, 12)
            .frame(width: WeekflowLayout.taskDetailStartTimeControlWidth, height: 32)
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 5)
                    .strokeBorder(WeekflowPalette.border.opacity(0.9), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 5))
        .anchorPreference(key: TaskDetailMenuAnchorPreferenceKey.self, value: .bounds) {
            [.startTime: $0]
        }
    }

    func timeMetricEditor(
        title: String,
        value: String,
        menu: TaskDetailMenu
    ) -> some View {
        WeekflowButton { toggleMenu(menu) } label: {
            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(WeekflowPalette.textMuted)
                Text(value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WeekflowPalette.primaryText)
                    .monospacedDigit()
            }
            .frame(width: WeekflowLayout.taskDetailTimeColumnWidth)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskPopoverInteractiveHighlight(cornerRadius: 6))
        .anchorPreference(
            key: TaskDetailMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [menu: anchor]
        }
    }

    func subtaskList(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.task.subtasks) { subtask in
                let isHovered = hoveredSubtaskID == subtask.id
                let isDragging = draggedSubtaskID == subtask.id
                let isDropTarget = dropTargetSubtaskID == subtask.id
                let isHighlighted = isHovered || isDragging || isDropTarget

                HStack(spacing: 12) {
                    WeekflowButton {
                        store.toggleSubtask(
                            goalID: entry.goal.id,
                            taskID: entry.task.id,
                            subtaskID: subtask.id,
                            persistImmediately: false
                        )
                    } label: {
                        Image(systemName: subtask.completed ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.system(size: 17))
                            .foregroundStyle(subtask.completed ? WeekflowPalette.complete : WeekflowPalette.iconDefault)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    TaskDetailSubtaskTextField(
                        text: subtaskTitleBinding(entry: entry, subtask: subtask),
                        placeholder: target.isWeeklyGoalDetail ? "子目标描述..." : "子任务描述...",
                        focusRequest: focusedSubtaskID == subtask.id ? subtaskRevealToken : nil,
                        onSubmit: { appendEmptySubtask(entry) },
                        onDeleteAtStart: {
                            deleteSubtaskAndRestoreFocus(entry, subtaskID: subtask.id)
                        }
                    )
                    .frame(height: 24)
                    .opacity(subtask.completed ? 0.58 : 1)
                    Spacer()
                    subtaskTimeValues(subtask)
                }
                .frame(minHeight: 32)
                .background(
                    isHighlighted ? WeekflowPalette.surfaceHover : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 6)
                )
                .opacity(isDragging ? 0.42 : 1)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    TaskDetailDragHandle(
                        isVisible: isHighlighted,
                        isDragging: isDragging
                    )
                    .contentShape(Rectangle())
                    .pointingHandCursor()
                    .gesture(subtaskDragGesture(entry, subtaskID: subtask.id))
                    .offset(x: taskDetailDragHandleLeadingOffset)
                    .help("拖动调整顺序")
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TaskDetailSubtaskRowFramePreferenceKey.self,
                            value: [
                                subtask.id: proxy.frame(
                                    in: .named(taskDetailSubtaskCoordinateSpace)
                                )
                            ]
                        )
                    }
                }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.14)) {
                        if hovering {
                            hoveredSubtaskID = subtask.id
                        } else if hoveredSubtaskID == subtask.id {
                            hoveredSubtaskID = nil
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: isHighlighted)
                .animation(
                    .interactiveSpring(response: 0.22, dampingFraction: 0.84),
                    value: isDragging
                )
                .id(subtask.id)
            }

            WeekflowButton(action: { appendEmptySubtask(entry) }) {
                HStack(spacing: 12) {
                    Image(systemName: isAddSubtaskHovered ? "plus.circle.fill" : "plus.circle")
                        .font(.system(size: 17, weight: isAddSubtaskHovered ? .semibold : .regular))
                        .frame(width: 22, height: 22)
                    Text(target.isWeeklyGoalDetail ? "添加子目标" : "添加子任务")
                        .font(.system(size: 12.5, weight: isAddSubtaskHovered ? .semibold : .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(
                isAddSubtaskHovered
                    ? WeekflowPalette.objective
                    : WeekflowPalette.textMuted
            )
            .background(
                isAddSubtaskHovered ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .pointingHandCursor()
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.14)) {
                    isAddSubtaskHovered = hovering
                }
            }
        }
        .coordinateSpace(name: taskDetailSubtaskCoordinateSpace)
        .onPreferenceChange(TaskDetailSubtaskRowFramePreferenceKey.self) {
            subtaskRowFrames = $0
        }
        .overlay(alignment: .topLeading) {
            if let draggedSubtaskID,
               let previewLocation = draggedSubtaskPreviewLocation,
               let frame = subtaskRowFrames[draggedSubtaskID],
               let subtask = entry.task.subtasks.first(where: { $0.id == draggedSubtaskID }) {
                subtaskDragPreview(subtask)
                    .frame(width: frame.width, height: frame.height)
                    .position(previewLocation)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .zIndex(100)
            }
        }
        .animation(
            .interactiveSpring(response: 0.22, dampingFraction: 0.86),
            value: entry.task.subtasks.map(\.id)
        )
    }

    func subtaskDragGesture(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(taskDetailSubtaskCoordinateSpace)
        )
        .onChanged { value in
            if draggedSubtaskID == nil {
                activeMenu = nil
                withAnimation(.easeInOut(duration: 0.12)) {
                    draggedSubtaskID = subtaskID
                    draggedSubtaskPreviewLocation = subtaskRowFrames[subtaskID].map { frame in
                        subtaskPreviewCenter(pointer: value.location, rowWidth: frame.width)
                    }
                }
            }
            guard draggedSubtaskID == subtaskID else { return }
            if let frame = subtaskRowFrames[subtaskID] {
                draggedSubtaskPreviewLocation = subtaskPreviewCenter(
                    pointer: value.location,
                    rowWidth: frame.width
                )
            }
            reorderSubtaskIfNeeded(
                entry,
                subtaskID: subtaskID,
                pointerY: value.location.y
            )
        }
        .onEnded { _ in
            withAnimation(.easeOut(duration: 0.14)) {
                draggedSubtaskID = nil
                draggedSubtaskPreviewLocation = nil
                dropTargetSubtaskID = nil
            }
        }
    }

    func subtaskPreviewCenter(pointer: CGPoint, rowWidth: CGFloat) -> CGPoint {
        CGPoint(
            x: pointer.x + rowWidth / 2 - taskDetailDragHandleCenterFromRowLeading,
            y: pointer.y
        )
    }

    func reorderSubtaskIfNeeded(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID,
        pointerY: CGFloat
    ) {
        let orderedIDs = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })?
            .subtasks.map(\.id) ?? []
        guard let sourceIndex = orderedIDs.firstIndex(of: subtaskID),
              !orderedIDs.isEmpty else { return }

        if let lastID = orderedIDs.last,
           lastID != subtaskID,
           let lastFrame = subtaskRowFrames[lastID],
           pointerY > lastFrame.maxY {
            dropTargetSubtaskID = lastID
            moveSubtaskWithAnimation(entry, subtaskID: subtaskID, to: nil)
            return
        }

        guard let targetID = orderedIDs.first(where: { id in
            guard let frame = subtaskRowFrames[id] else { return false }
            return frame.minY...frame.maxY ~= pointerY
        }),
        targetID != subtaskID,
        let targetIndex = orderedIDs.firstIndex(of: targetID),
        let targetFrame = subtaskRowFrames[targetID] else { return }

        let crossedTargetCenter = targetIndex > sourceIndex
            ? pointerY >= targetFrame.midY
            : pointerY <= targetFrame.midY
        guard crossedTargetCenter else { return }
        dropTargetSubtaskID = targetID
        moveSubtaskWithAnimation(entry, subtaskID: subtaskID, to: targetID)
    }

    func moveSubtaskWithAnimation(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID,
        to targetSubtaskID: UUID?
    ) {
        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            store.moveSubtask(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                subtaskID: subtaskID,
                to: targetSubtaskID,
                persistImmediately: false
            )
        }
    }

    func subtaskTimeValues(_ subtask: TaskSubtask) -> some View {
        HStack(spacing: WeekflowLayout.taskDetailTimeColumnSpacing) {
            Color.clear
                .frame(width: WeekflowLayout.taskDetailStartTimeControlWidth)
            subtaskTimeButton(
                value: TaskTimeDisplay.actual(
                    minutes: subtask.actualMinutes ?? 0,
                    estimatedMinutes: subtask.plannedMinutes ?? 0
                ),
                menu: .subtaskActualTime(subtask.id)
            )
            subtaskTimeButton(
                value: TaskTimeDisplay.estimated(minutes: subtask.plannedMinutes ?? 0),
                menu: .subtaskEstimatedTime(subtask.id)
            )
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(WeekflowPalette.textMuted)
        .monospacedDigit()
        .frame(width: WeekflowLayout.taskDetailTimingWidth, alignment: .trailing)
    }

    func subtaskTimeButton(value: String, menu: TaskDetailMenu) -> some View {
        WeekflowButton { toggleMenu(menu) } label: {
            Text(value)
                .frame(width: WeekflowLayout.taskDetailTimeColumnWidth, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(TaskDetailTextWeightHover())
        .anchorPreference(
            key: TaskDetailMenuAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [menu: anchor]
        }
        .accessibilityLabel("调整子任务时间")
    }

    func subtaskDragPreview(_ subtask: TaskSubtask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: subtask.completed ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 17))
                .foregroundStyle(
                    subtask.completed ? WeekflowPalette.complete : WeekflowPalette.iconDefault
                )
                .frame(width: 22, height: 22)
            Text(
                subtask.title.isEmpty
                    ? (target.isWeeklyGoalDetail ? "子目标描述..." : "子任务描述...")
                    : subtask.title
            )
                .font(.system(size: 13))
                .foregroundStyle(
                    subtask.title.isEmpty ? WeekflowPalette.textMuted : WeekflowPalette.primaryText
                )
                .lineLimit(1)
            Spacer()
            HStack(spacing: WeekflowLayout.taskDetailTimeColumnSpacing) {
                Color.clear.frame(width: WeekflowLayout.taskDetailStartTimeControlWidth)
                Text(TaskTimeDisplay.actual(
                    minutes: subtask.actualMinutes ?? 0,
                    estimatedMinutes: subtask.plannedMinutes ?? 0
                ))
                    .frame(width: WeekflowLayout.taskDetailTimeColumnWidth)
                Text(TaskTimeDisplay.estimated(minutes: subtask.plannedMinutes ?? 0))
                    .frame(width: WeekflowLayout.taskDetailTimeColumnWidth)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(WeekflowPalette.textMuted)
            .monospacedDigit()
            .frame(width: WeekflowLayout.taskDetailTimingWidth, alignment: .trailing)
        }
        .overlay(alignment: .leading) {
            TaskDetailDragHandle(isVisible: true, isDragging: true)
                .offset(x: taskDetailDragHandleLeadingOffset)
        }
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 6))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 6)
                .stroke(WeekflowPalette.borderStrong.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 9, x: 0, y: 5)
    }

    func descriptionEditor(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> some View {
        TextField(target.isWeeklyGoalDetail ? "目标描述..." : "任务描述...", text: $description, axis: .vertical)
            .font(.system(size: 14))
            .foregroundStyle(WeekflowPalette.secondaryText)
            .textFieldStyle(.plain)
            .lineLimit(2...8)
            .frame(minHeight: 50, maxHeight: 142, alignment: .topLeading)
            .padding(.leading, 44)
            .onChange(of: description) { _, _ in scheduleAutosave(entry) }
            .onSubmit { save(entry) }
    }

    func historyTimeline(_ task: WeekTask) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(WeekflowPalette.border.opacity(0.72))
                .frame(height: 1)
                .padding(.bottom, 18)
            ForEach(historyItems(for: task)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(WeekflowPalette.border)
                        .frame(width: 5, height: 5)
                    Text(item.title).foregroundStyle(WeekflowPalette.secondaryText)
                    Spacer(minLength: 16)
                    Text(item.date.formatted(.dateTime.month().day().hour().minute()))
                        .foregroundStyle(WeekflowPalette.textMuted)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .padding(.vertical, 5)
            }
        }
    }

    func historyItems(for task: WeekTask) -> [TaskHistoryItem] {
        var items = task.changeRecords.map { record in
            TaskHistoryItem(
                id: "change-\(record.id.uuidString)",
                date: record.date,
                title: record.field == "任务详情"
                    ? "修改：\(record.newValue)"
                    : "\(historyFieldName(record.field))修改"
            )
        }
        items.append(TaskHistoryItem(id: "created", date: task.createdAt, title: "任务已创建"))
        return items.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id < $1.id
        }
    }

    func historyFieldName(_ field: String) -> String {
        switch field {
        case "安排日期": "开始日期"
        case "说明": "任务描述"
        default: field
        }
    }

    func scheduleAutosave(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            save(entry)
        }
    }

    func save(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        guard let initialTask,
              let (updated, _) = editedTaskSnapshot(entry) else { return }
        let records = store.saveEditedTask(
            updated,
            original: initialTask,
            goalID: entry.goal.id,
            recordChanges: false,
            // A debounced autosave must reach durable storage, not merely the
            // Store's in-memory model. The editing-session history remains
            // consolidated when the detail closes, but a crash while it is
            // open must not discard the latest quiet-period edit.
            persistImmediately: true
        )
        guard !records.isEmpty else { return }
        self.initialTask = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })
    }

    func editedTaskSnapshot(
        _ entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> (updated: WeekTask, current: WeekTask)? {
        guard let currentTask = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id }) else { return nil }
        var updated = currentTask
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = description
        updated.notes = notes
        updated.channelID = channelID
        updated.priority = priority
        let selectedPlannedDate = SystemBusinessCalendar.current.calendar.startOfDay(for: plannedDate)
        let preservesUnassignedPrimaryGoal = entry.goal.primaryTaskID == currentTask.id
            && currentTask.plannedDate == nil
            && SystemBusinessCalendar.current.calendar.isDate(selectedPlannedDate, inSameDayAs: entry.goal.startDate)
        updated.plannedDate = preservesUnassignedPrimaryGoal ? nil : selectedPlannedDate
        updated.dueDate = hasDueDate ? dueDate : nil
        updated.startTime = hasStartTime ? startTime : nil
        updated.estimatedMinutes = estimatedMinutes
        updated.actualMinutes = TaskActualMinutesPolicy.resolved(
            manual: actualMinutes,
            live: store.liveTaskActualMinutes(goalID: entry.goal.id, taskID: entry.task.id),
            timerIsRunning: isTimerRunning(entry)
        )
        return (updated, currentTask)
    }

    func finishEditingSession(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        autosaveTask?.cancel()
        if discardEmptyWeeklyGoalDraftIfNeeded(entry) {
            sessionCommitted = true
            return
        }
        save(entry)
        guard !sessionCommitted, let sessionOpeningTask else { return }
        _ = store.recordTaskEditingSession(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            original: sessionOpeningTask
        )
        sessionCommitted = true
    }

    func closeResponsively(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        guard !isClosing else { return }
        autosaveTask?.cancel()
        if discardEmptyWeeklyGoalDraftIfNeeded(entry) {
            isClosing = true
            sessionCommitted = true
            closeDetail()
            return
        }
        guard let sessionOpeningTask,
              let snapshot = editedTaskSnapshot(entry) else {
            isClosing = true
            closeDetail()
            return
        }

        isClosing = true
        sessionCommitted = true
        closeDetail()
        DispatchQueue.main.async {
            _ = store.saveEditedTask(
                snapshot.updated,
                original: snapshot.current,
                goalID: entry.goal.id,
                recordChanges: false,
                persistImmediately: false
            )
            _ = store.recordTaskEditingSession(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                original: sessionOpeningTask
            )
        }
    }

    @discardableResult
    func discardEmptyWeeklyGoalDraftIfNeeded(
        _ entry: (goal: WeeklyGoal, task: WeekTask)
    ) -> Bool {
        guard target.isNewWeeklyGoal,
              title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        store.discardGoalDraft(id: entry.goal.id)
        return true
    }

    func moveTaskResponsively(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        toGoalID: UUID
    ) {
        guard !isClosing,
              let sessionOpeningTask,
              let snapshot = editedTaskSnapshot(entry) else { return }
        autosaveTask?.cancel()
        activeMenu = nil
        isClosing = true
        sessionCommitted = true
        closeDetail()

        DispatchQueue.main.async {
            _ = store.saveEditedTask(
                snapshot.updated,
                original: snapshot.current,
                goalID: entry.goal.id,
                recordChanges: false,
                persistImmediately: false
            )
            _ = store.recordTaskEditingSession(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                original: sessionOpeningTask,
                persistImmediately: false
            )
            _ = store.moveTask(
                goalID: entry.goal.id,
                taskID: entry.task.id,
                toGoalID: toGoalID
            )
        }
    }

    func setActualMinutes(_ value: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        actualMinutes = value
        save(entry)
    }

    func setEstimatedMinutes(_ value: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        estimatedMinutes = value
        save(entry)
    }

    func subtask(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        id subtaskID: UUID
    ) -> TaskSubtask? {
        store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })?
            .subtasks.first(where: { $0.id == subtaskID })
    }

    func setSubtaskActualMinutes(
        _ value: Int,
        subtaskID: UUID,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) {
        store.updateSubtaskActualMinutes(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            subtaskID: subtaskID,
            minutes: value,
            persistImmediately: false
        )
    }

    func setSubtaskPlannedMinutes(
        _ value: Int,
        subtaskID: UUID,
        entry: (goal: WeeklyGoal, task: WeekTask)
    ) {
        store.updateSubtaskPlannedMinutes(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            subtaskID: subtaskID,
            minutes: value,
            persistImmediately: false
        )
    }

    func setStartTime(_ selection: Date?, entry: (goal: WeeklyGoal, task: WeekTask)) {
        hasStartTime = selection != nil
        if let selection { startTime = selection }
        save(entry)
    }

    func moveStartDate(by offset: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        guard let date = SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: offset, to: plannedDate) else { return }
        setStartDate(date, entry: entry)
    }

    func setStartDate(_ date: Date, entry: (goal: WeeklyGoal, task: WeekTask)) {
        plannedDate = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
        if hasDueDate, dueDate < plannedDate {
            dueDate = plannedDate
        }
        save(entry)
    }

    func moveDueDate(by offset: Int, entry: (goal: WeeklyGoal, task: WeekTask)) {
        let baseDate = hasDueDate ? dueDate : plannedDate
        guard let date = SystemBusinessCalendar.current.calendar.date(byAdding: .day, value: offset, to: baseDate) else { return }
        setDueDate(date, entry: entry)
    }

    func setDueDate(_ date: Date, entry: (goal: WeeklyGoal, task: WeekTask)) {
        dueDate = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
        hasDueDate = true
        save(entry)
    }

    func clearDueDate(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        hasDueDate = false
        save(entry)
    }

    func setRecurrence(_ rule: RecurringRule?, entry: (goal: WeeklyGoal, task: WeekTask)) {
        store.setTaskRecurrence(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            rule: rule,
            recordChanges: false,
            persistImmediately: false
        )
        initialTask = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })
    }

    func appendEmptySubtask(_ entry: (goal: WeeklyGoal, task: WeekTask)) {
        activeMenu = nil
        let subtaskID = store.addSubtask(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            title: "",
            persistImmediately: false
        )
        focusedSubtaskID = subtaskID
        subtaskRevealToken += 1
    }

    func deleteSubtaskAndRestoreFocus(
        _ entry: (goal: WeeklyGoal, task: WeekTask),
        subtaskID: UUID
    ) {
        guard let subtasks = store.goals
            .first(where: { $0.id == entry.goal.id })?
            .tasks.first(where: { $0.id == entry.task.id })?
            .subtasks,
            subtasks.contains(where: { $0.id == subtaskID }) else { return }

        let focusTarget = TaskDetailSubtaskFocusPolicy.targetAfterDeleting(
            subtaskID: subtaskID,
            from: subtasks
        )

        store.deleteSubtask(
            goalID: entry.goal.id,
            taskID: entry.task.id,
            subtaskID: subtaskID,
            persistImmediately: false
        )
        focusedSubtaskID = focusTarget
        if focusTarget != nil {
            subtaskRevealToken += 1
        }
    }

    func subtaskTitleBinding(
        entry: (goal: WeeklyGoal, task: WeekTask),
        subtask: TaskSubtask
    ) -> Binding<String> {
        Binding(
            get: {
                store.goals
                    .first(where: { $0.id == entry.goal.id })?
                    .tasks.first(where: { $0.id == entry.task.id })?
                    .subtasks.first(where: { $0.id == subtask.id })?
                    .title ?? subtask.title
            },
            set: {
                store.updateSubtaskTitle(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    subtaskID: subtask.id,
                    title: $0,
                    persistImmediately: false
                )
            }
        )
    }

    func detailActualTime(at date: Date) -> String {
        TaskTimeDisplay.actual(
            minutes: max(
                actualMinutes,
                store.liveTaskActualMinutes(goalID: target.goalID, taskID: target.taskID, at: date)
            ),
            estimatedMinutes: estimatedMinutes
        )
    }

    func isTimerRunning(_ entry: (goal: WeeklyGoal, task: WeekTask)) -> Bool {
        store.isTaskTimerRunning(goalID: entry.goal.id, taskID: entry.task.id)
    }

    func detailTimerMinuteBucket(_ entry: (goal: WeeklyGoal, task: WeekTask), at date: Date) -> Int {
        guard let startedAt = store.taskTimerStartedAt(goalID: entry.goal.id, taskID: entry.task.id) else { return -1 }
        return max(Int(date.timeIntervalSince(startedAt)) / 60, 0)
    }
}
