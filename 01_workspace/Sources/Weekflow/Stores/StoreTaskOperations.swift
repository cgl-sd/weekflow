import Foundation
import Observation

// Task CRUD, mutation, assignment, clipboard, and reorder operations.

extension WeekflowStore {
    func addTask(
        to goalID: UUID,
        title: String,
        plannedDate: Date?,
        dueDate: Date?,
        minutes: Int,
        notes: String,
        milestoneID: Milestone.ID?,
        parentTaskID: WeekTask.ID? = nil,
        subgoalID: GoalSubgoal.ID? = nil,
        startTime: Date? = nil,
        executionWeekStart: Date? = nil,
        channelID: String? = nil,
        contextID: String? = nil,
        priority: TaskPriority = .none,
        sourceType: TaskSourceType = .native,
        sourceURL: String? = nil,
        description: String = "",
        recurringRule: RecurringRule? = nil
    ) -> UUID? {
        guard var goal = goals.first(where: { $0.id == goalID }) else { return nil }
        // Delegate task creation to TaskService (P2-2)
        let task = taskService.makeTask(
            title: title,
            plannedDate: plannedDate,
            dueDate: dueDate,
            minutes: minutes,
            notes: notes,
            milestoneID: milestoneID,
            parentTaskID: parentTaskID,
            subgoalID: subgoalID,
            startTime: startTime,
            executionWeekStart: executionWeekStart,
            channelID: channelID,
            defaultChannelID: channels.first(where: \.isDefault)?.id,
            contextID: contextID,
            priority: priority,
            sourceType: sourceType,
            sourceURL: sourceURL,
            description: description,
            recurringRule: recurringRule,
            existingTasks: goal.tasks
        )
        goal.tasks.append(task)
        replace(goal)
        if let plannedDate {
            reorderTasksByPriority(
                on: plannedDate,
                promotedTask: TaskReference(goalID: goalID, taskID: task.id)
            )
        }
        persist()
        return task.id
    }

    @discardableResult
    func addSubgoal(
        to goalID: UUID,
        title: String,
        detail: String = "",
        createTask: Bool = true
    ) -> UUID? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, var goal = goals.first(where: { $0.id == goalID }) else { return nil }
        let subgoal = GoalSubgoal(title: cleanTitle, detail: detail)
        goal.subgoals.append(subgoal)
        replace(goal)
        persist()
        if createTask {
            _ = addTask(
                to: goalID,
                title: cleanTitle,
                plannedDate: nil,
                dueDate: goal.endDate,
                minutes: 60,
                notes: detail,
                milestoneID: nil,
                subgoalID: subgoal.id,
                channelID: goal.channelID,
                sourceType: .weeklyObjective
            )
        }
        return subgoal.id
    }

    func toggleSubgoal(goalID: UUID, subgoalID: UUID) {
        guard var goal = goals.first(where: { $0.id == goalID }),
              let index = goal.subgoals.firstIndex(where: { $0.id == subgoalID }) else { return }
        goal.subgoals[index].isCompleted.toggle()
        if let taskIndex = goal.tasks.firstIndex(where: { $0.subgoalID == subgoalID }) {
            goal.tasks[taskIndex].status = goal.subgoals[index].isCompleted ? .completed : .planned
            goal.tasks[taskIndex].archivedAt = goal.subgoals[index].isCompleted ? .now : nil
            goal.tasks[taskIndex].updatedAt = .now
        }
        let allSubgoalsCompleted = !goal.subgoals.isEmpty && goal.subgoals.allSatisfy(\.isCompleted)
        goal.completedAt = allSubgoalsCompleted ? (goal.completedAt ?? .now) : nil
        replace(goal)
        persist()
    }

    func toggleTask(goalID: UUID, taskID: UUID, persistImmediately: Bool = true) {
        guard var goal = goals.first(where: { $0.id == goalID }), let index = goal.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let completesTask = goal.tasks[index].status != .completed
        goal.tasks[index].status = completesTask ? .completed : .planned
        goal.tasks[index].archivedAt = completesTask ? .now : nil
        goal.tasks[index].updatedAt = .now
        if let subgoalID = goal.tasks[index].subgoalID,
           let subgoalIndex = goal.subgoals.firstIndex(where: { $0.id == subgoalID }) {
            goal.subgoals[subgoalIndex].isCompleted = goal.tasks[index].status == .completed
            let allSubgoalsCompleted = !goal.subgoals.isEmpty && goal.subgoals.allSatisfy(\.isCompleted)
            goal.completedAt = allSubgoalsCompleted ? (goal.completedAt ?? .now) : nil
        }
        if goal.tasks[index].status != .completed { goal.completedAt = nil }
        goal = goalService.applyPrimaryProjectionEdit(goal)
        replace(goal)
        if goal.tasks[index].status == .completed { createNextRecurringInstanceIfNeeded(for: goal.tasks[index], in: goal) }
        if persistImmediately { persist() }
    }

    func setTaskStatus(goalID: UUID, taskID: UUID, status: TaskStatus) {
        updateTask(goalID: goalID, taskID: taskID) { task in
            task.status = status
            task.archivedAt = status == .completed || status == .archived ? .now : nil
        }
        if status == .completed, let updated = task(goalID: goalID, taskID: taskID), let goal = goals.first(where: { $0.id == goalID }) {
            createNextRecurringInstanceIfNeeded(for: updated, in: goal)
        }
    }

    func assignTask(goalID: UUID, taskID: UUID, to date: Date) {
        relocateTask(goalID: goalID, taskID: taskID, from: nil, to: date)
    }

    /// Places a task on a day while preserving the weekly task pool as the
    /// source of truth. A drag that originates from a daily assignment moves
    /// that assignment; a drag directly from the pool adds a new assignment.
    func relocateTask(
        goalID: UUID,
        taskID: UUID,
        from sourceDate: Date?,
        to date: Date,
        persistImmediately: Bool = true
    ) {
        let override = automaticDistributionOverride(goalID: goalID, taskID: taskID)
        let saved = updateTask(
            goalID: goalID,
            taskID: taskID,
            persistImmediately: persistImmediately,
            persistenceKind: override ?? .userEdit
        ) { task in
            let calendar = businessCalendar.calendar
            let targetDay = calendar.startOfDay(for: date)
            task.executionWeekStart = nil
            if task.plannedDate == nil || task.sourceType == .weeklyObjective {
                if let sourceDate,
                   !calendar.isDate(sourceDate, inSameDayAs: targetDay) {
                    task.assignedDates.removeAll {
                        calendar.isDate($0, inSameDayAs: sourceDate)
                    }
                }
                if !task.isAssigned(on: targetDay, calendar: calendar) {
                    task.assignedDates.append(targetDay)
                }
            } else {
                task.plannedDate = targetDay
                if let oldStartTime = task.startTime {
                    let time = calendar.dateComponents([.hour, .minute, .second], from: oldStartTime)
                    task.startTime = calendar.date(
                        bySettingHour: time.hour ?? 0,
                        minute: time.minute ?? 0,
                        second: time.second ?? 0,
                        of: targetDay
                    )
                }
            }
            if task.isArchived {
                task.status = task.status == .archived ? .planned : task.status
                task.archivedAt = nil
            }
        }
        if saved, override != nil { removeAutomaticDistributionChange(goalID: goalID, taskID: taskID) }
    }

    func removeTaskAssignment(goalID: UUID, taskID: UUID, from date: Date) {
        let override = automaticDistributionOverride(goalID: goalID, taskID: taskID)
        let saved = updateTask(goalID: goalID, taskID: taskID, persistenceKind: override ?? .userEdit) { task in
            task.assignedDates.removeAll { businessCalendar.calendar.isDate($0, inSameDayAs: date) }
        }
        if saved, override != nil { removeAutomaticDistributionChange(goalID: goalID, taskID: taskID) }
    }

    func unassignTask(goalID: UUID, taskID: UUID) {
        moveTaskToBacklog(goalID: goalID, taskID: taskID, atTop: false)
    }

    func moveTaskToBacklog(goalID: UUID, taskID: UUID, atTop: Bool) {
        let override = automaticDistributionOverride(goalID: goalID, taskID: taskID)
        let topOrder = taskPool
            .filter { $0.task.id != taskID }
            .map(\.task.sortOrder)
            .min()
        let saved = updateTask(goalID: goalID, taskID: taskID, persistenceKind: override ?? .userEdit) { task in
            task.plannedDate = nil
            task.assignedDates.removeAll()
            task.startTime = nil
            task.executionWeekStart = nil
            task.calendarPlacement = .suggested
            if atTop {
                task.sortOrder = (topOrder ?? 0) - 1
            }
        }
        if saved, override != nil { removeAutomaticDistributionChange(goalID: goalID, taskID: taskID) }
    }

    func setTaskSchedule(goalID: UUID, taskID: UUID, date: Date, startTime: Date?, minutes: Int) {
        updateTask(goalID: goalID, taskID: taskID) { task in
            task.plannedDate = businessCalendar.calendar.startOfDay(for: date)
            task.startTime = startTime
            task.estimatedMinutes = minutes
            task.executionWeekStart = nil
        }
    }

    func setTaskCalendarPlacement(
        goalID: UUID,
        taskID: UUID,
        placement: TaskCalendarPlacement
    ) {
        updateTask(goalID: goalID, taskID: taskID) { task in
            guard task.startTime != nil else { return }
            task.calendarPlacement = placement
        }
    }

    func commitTaskToCalendar(
        goalID: UUID,
        taskID: UUID,
        startTime: Date? = nil
    ) {
        updateTask(goalID: goalID, taskID: taskID) { task in
            if let startTime {
                task.startTime = startTime
                task.plannedDate = businessCalendar.calendar.startOfDay(for: startTime)
            }
            guard task.startTime != nil else { return }
            task.calendarPlacement = .committed
        }
    }

    func toggleTaskCalendarCommitment(goalID: UUID, taskID: UUID) {
        guard let entry = activeTasks.first(where: {
            $0.goal.id == goalID && $0.task.id == taskID
        }), entry.task.startTime != nil else { return }
        setTaskCalendarPlacement(
            goalID: goalID,
            taskID: taskID,
            placement: entry.task.calendarPlacement == .committed ? .suggested : .committed
        )
    }

    func updateTaskEstimatedMinutes(goalID: UUID, taskID: UUID, minutes: Int) {
        updateTask(goalID: goalID, taskID: taskID) { task in
            task.estimatedMinutes = min(max(minutes, 15), 18 * 60)
        }
    }

    func updateTask(_ updatedTask: WeekTask, goalID: UUID) {
        guard var goal = goals.first(where: { $0.id == goalID }), let index = goal.tasks.firstIndex(where: { $0.id == updatedTask.id }) else { return }
        var task = updatedTask
        if task.startTime == nil { task.calendarPlacement = .suggested }
        task.updatedAt = .now
        goal.tasks[index] = task
        goal = goalService.applyPrimaryProjectionEdit(goal)
        replace(goal)
        persistDebounced()
    }

    /// Debounced persist for text-input edits. Coalesces rapid keystrokes into
    /// a single disk write after a quiet period (P1-7 requirement).
    func persistDebounced() {
        textInputDebouncer.schedule { [weak self] in
            self?.persist()
        }
    }

    /// Flushes any pending debounced persist. Call when the edit session ends
    /// (view disappears, user presses Return, etc.).
    func flushPendingPersistence() {
        textInputDebouncer.flush()
        persist()
    }

    /// P0-2/P2-3 fix: awaits completion of all in-flight asynchronous writes.
    /// Call before app termination and in tests that exercise the production
    /// async persistence path, so the final edited value is guaranteed to be
    /// committed to disk before assertions or shutdown.
    func flushPersistence() async {
        textInputDebouncer.flush()
        // Always enqueue; the background diff handles the empty-change case.
        enqueueGoalPersist(kind: .userEdit)
        await persistenceCoordinator.flush()
    }

    /// Synchronous termination guard. Performs a final synchronous persist of ALL
    /// data in a single transaction so no pending async writes are lost when the
    /// process exits. Called from `applicationWillTerminate` where async is not available.
    ///
    /// Uses `saveApplicationSnapshot` (one atomic transaction) instead of multiple
    /// separate saves, ensuring cross-entity consistency even if disk fails mid-write.
    /// Does NOT call `persistSync()` to avoid nested begin/endSyncWrite issues.
    func persistForTermination() {
        textInputDebouncer.cancelPending()
        // Cancel ALL pending async writes and raise the sync barrier so in-flight
        // async writers skip their disk write. Nesting-safe counter.
        persistenceCoordinator.cancelAllPending()
        persistenceCoordinator.beginSyncWrite()
        // Single atomic snapshot persist (goals + channels + calendar + planning +
        // focus records + daily summaries in one transaction).
        let snapshot = WeekflowPersistenceSnapshot(
            goals: goals,
            channels: channels,
            calendarEvents: calendarEvents,
            dailyPlanningStates: dailyPlanningStates,
            focusRecords: focusRecords,
            dailySummaries: dailySummaries
        )
        _ = persistSafely(
            "退出保存",
            operation: { try storage.saveApplicationSnapshot(snapshot) },
            commit: {
                persistedGoals = goals
                persistedChannels = channels
                persistedCalendarEvents = calendarEvents
                persistedDailyPlanningStates = dailyPlanningStates
                persistedFocusRecords = focusRecords
                persistedDailySummaries = dailySummaries
            },
            rollback: {
                goals = persistedGoals
                invalidateGoalIndex()
                channels = persistedChannels
                calendarEvents = persistedCalendarEvents
                dailyPlanningStates = persistedDailyPlanningStates
                focusRecords = persistedFocusRecords
                dailySummaries = persistedDailySummaries
            }
        )
        // Persist active timer session separately (not part of the snapshot).
        let session = activeTaskTimer
        _ = persistSafely(
            "活动计时",
            operation: { try storage.saveActiveTimerSession(session) },
            commit: {},
            rollback: { if session != nil { activeTaskTimer = nil } }
        )
        persistenceCoordinator.endSyncWrite()
    }

    func setTaskPriority(
        goalID: UUID,
        taskID: UUID,
        priority: TaskPriority,
        on date: Date
    ) {
        // P2-7: O(1) goal lookup.
        guard let goalIndex = goalIndex(for: goalID),
              let taskIndex = goals[goalIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let previousPriority = goals[goalIndex].tasks[taskIndex].priority
        goals[goalIndex].tasks[taskIndex].priority = priority
        goals[goalIndex].tasks[taskIndex].updatedAt = .now
        if priority.isHigher(than: previousPriority) {
            reorderTasksByPriority(
                on: date,
                promotedTask: TaskReference(goalID: goalID, taskID: taskID)
            )
        }
        persist()
    }

    @discardableResult
    func saveEditedTask(
        _ updatedTask: WeekTask,
        original: WeekTask,
        goalID: UUID,
        now: Date = .now,
        recordChanges: Bool = true,
        persistImmediately: Bool = true
    ) -> [TaskChangeRecord] {
        // P2-7: O(1) goal lookup.
        guard let gIdx = goalIndex(for: goalID),
              let index = goals[gIdx].tasks.firstIndex(where: { $0.id == updatedTask.id }) else { return [] }
        let current = goals[gIdx].tasks[index]
        let records = manualChangeRecords(from: original, to: updatedTask, date: now)
        guard !records.isEmpty else { return [] }

        var task = updatedTask
        if task.startTime == nil { task.calendarPlacement = .suggested }
        task.changeRecords = recordChanges ? current.changeRecords + records : current.changeRecords
        task.updatedAt = now
        // P1-6 fix: direct indexed mutation avoids copying the entire goal
        // struct before the task array COW is triggered.
        goals[gIdx].tasks[index] = task
        var goal = goals[gIdx]
        goal = goalService.applyPrimaryProjectionEdit(goal)
        goals[gIdx] = goal
        if updatedTask.priority.isHigher(than: original.priority),
           let plannedDate = updatedTask.plannedDate {
            reorderTasksByPriority(
                on: plannedDate,
                promotedTask: TaskReference(goalID: goalID, taskID: updatedTask.id)
            )
        }
        if persistImmediately { persist() }
        return records
    }

    @discardableResult
    func recordTaskEditingSession(
        goalID: UUID,
        taskID: UUID,
        original: WeekTask,
        now: Date = .now,
        persistImmediately: Bool = true
    ) -> TaskChangeRecord? {
        // P2-7: O(1) goal lookup.
        guard let gIdx = goalIndex(for: goalID),
              let index = goals[gIdx].tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        let current = goals[gIdx].tasks[index]
        let changes = manualChangeRecords(from: original, to: current, date: now)
        guard !changes.isEmpty else {
            if persistImmediately { persist() }
            return nil
        }

        var seenFields = Set<String>()
        let fields = changes.compactMap { change -> String? in
            let field = change.field == "说明" ? "任务描述" : change.field
            return seenFields.insert(field).inserted ? field : nil
        }
        let record = TaskChangeRecord(
            date: now,
            field: "任务详情",
            oldValue: "",
            newValue: fields.joined(separator: "、"),
            source: .manual
        )
        // P1-6 fix: direct indexed mutation.
        goals[gIdx].tasks[index].changeRecords.append(record)
        goals[gIdx].tasks[index].updatedAt = now
        if persistImmediately { persist() }
        return record
    }

    func deleteTask(goalID: UUID, taskID: UUID) {
        guard var goal = goals.first(where: { $0.id == goalID }) else { return }
        let now = Date.now
        if goal.primaryTaskID == taskID {
            goal.deletedAt = now
            goal.archivedAt = nil
            replace(goal)
            if selectedGoalID == goalID { selectedGoalID = activeGoals.first?.id }
            if highlightedTask?.goalID == goalID { highlightedTask = nil }
            persist()
            return
        }
        let linkedSubgoalID = goal.tasks.first(where: { $0.id == taskID })?.subgoalID
        if let linkedSubgoalID {
            goal.subgoals.removeAll { $0.id == linkedSubgoalID }
            if let primaryTaskID = goal.primaryTaskID,
               let primaryTaskIndex = goal.tasks.firstIndex(where: { $0.id == primaryTaskID }) {
                goal.tasks[primaryTaskIndex].subtasks.removeAll { $0.id == linkedSubgoalID }
                goal.tasks[primaryTaskIndex].updatedAt = now
            }
            let allSubgoalsCompleted = !goal.subgoals.isEmpty
                && goal.subgoals.allSatisfy(\.isCompleted)
            goal.completedAt = allSubgoalsCompleted ? (goal.completedAt ?? now) : nil
        }
        for index in goal.tasks.indices where goal.tasks[index].id == taskID || goal.tasks[index].parentTaskID == taskID {
            goal.tasks[index].status = .deleted
            goal.tasks[index].archivedAt = nil
            goal.tasks[index].updatedAt = now
        }
        goal = goalService.project(goal)
        replace(goal)
        if highlightedTask?.taskID == taskID { highlightedTask = nil }
        persist()
    }

    func restoreDeletedTask(goalID: UUID, taskID: UUID) {
        guard let goal = goals.first(where: { $0.id == goalID }) else { return }
        var updated = goalLifecycle.restoreDeletedTask(
            in: goal,
            taskID: taskID,
            now: .now,
            calendar: businessCalendar.calendar
        )
        updated = goalService.project(updated)
        replace(updated)
        persist()
    }

    func permanentlyDeleteTask(goalID: UUID, taskID: UUID) {
        guard let goal = goals.first(where: { $0.id == goalID }) else { return }
        guard let updated = goalLifecycle.purgeTask(in: goal, taskID: taskID) else { return }
        replace(updated)
        if highlightedTask?.goalID == goalID && highlightedTask?.taskID == taskID {
            highlightedTask = nil
        }
        persist()
    }

    func permanentlyDeleteAllDeletedTasks() {
        let entries = deletedTasks
        guard !entries.isEmpty else { return }
        for entry in entries {
            if let goal = goals.first(where: { $0.id == entry.goal.id }),
               let updated = goalLifecycle.purgeTask(in: goal, taskID: entry.task.id) {
                replace(updated)
            }
        }
        highlightedTask = nil
        persist()
    }

    @discardableResult
    func duplicateTask(
        goalID: UUID,
        taskID: UUID,
        now: Date = .now,
        persistImmediately: Bool = true
    ) -> UUID? {
        guard var goal = goals.first(where: { $0.id == goalID }),
              let original = goal.tasks.first(where: { $0.id == taskID }) else { return nil }
        goal.tasks = goal.tasks.map { task in
            guard task.sortOrder > original.sortOrder else { return task }
            var shifted = task
            shifted.sortOrder += 1
            return shifted
        }
        // P1-5 fix: delegate duplication logic to TaskService.
        let copy = taskService.duplicated(original, sortOrder: original.sortOrder + 1)
        goal.tasks.append(copy)
        replace(goal)
        if persistImmediately { persist() }
        return copy.id
    }

    func copyHighlightedTask(cutsSource: Bool = false) {
        guard let highlightedTask,
              task(goalID: highlightedTask.goalID, taskID: highlightedTask.taskID) != nil else {
            return
        }
        taskClipboard = (highlightedTask, cutsSource)
    }

    @discardableResult
    func pasteTaskClipboard(
        on date: Date? = nil,
        after anchor: TaskReference? = nil
    ) -> UUID? {
        guard let clipboard = taskClipboard,
              let source = task(
                goalID: clipboard.reference.goalID,
                taskID: clipboard.reference.taskID
              ) else { return nil }
        let targetDate = businessCalendar.calendar.startOfDay(for: date ?? activeDay)
        if clipboard.cutsSource {
            moveTask(
                goalID: clipboard.reference.goalID,
                taskID: clipboard.reference.taskID,
                to: targetDate
            )
            taskClipboard = nil
            highlightedTask = clipboard.reference
            placeTask(clipboard.reference, after: anchor, on: targetDate)
            return clipboard.reference.taskID
        }
        guard let copiedID = duplicateTask(
            goalID: clipboard.reference.goalID,
            taskID: clipboard.reference.taskID
        ) else { return nil }
        updateTask(goalID: clipboard.reference.goalID, taskID: copiedID) { copy in
            copy.title = "\(source.title) 副本"
            copy.plannedDate = targetDate
            copy.assignedDates = []
            copy.executionWeekStart = nil
            if let start = source.startTime {
                let time = businessCalendar.calendar.dateComponents([.hour, .minute], from: start)
                copy.startTime = businessCalendar.calendar.date(
                    bySettingHour: time.hour ?? 6,
                    minute: time.minute ?? 0,
                    second: 0,
                    of: targetDate
                )
            }
        }
        highlightedTask = TaskReference(goalID: clipboard.reference.goalID, taskID: copiedID)
        placeTask(
            TaskReference(goalID: clipboard.reference.goalID, taskID: copiedID),
            after: anchor,
            on: targetDate
        )
        return copiedID
    }

    func placeTask(
        _ moving: TaskReference,
        after anchor: TaskReference?,
        on date: Date
    ) {
        guard let anchor, anchor != moving else { return }
        var entries = tasks(on: date)
        guard let movingIndex = entries.firstIndex(where: {
            $0.goal.id == moving.goalID && $0.task.id == moving.taskID
        }), let anchorIndexBeforeRemoval = entries.firstIndex(where: {
            $0.goal.id == anchor.goalID && $0.task.id == anchor.taskID
        }) else { return }
        let movingEntry = entries.remove(at: movingIndex)
        let adjustedAnchorIndex = anchorIndexBeforeRemoval - (movingIndex < anchorIndexBeforeRemoval ? 1 : 0)
        entries.insert(movingEntry, at: min(adjustedAnchorIndex + 1, entries.endIndex))
        applyTaskOrder(entries)
        persist()
    }

    @discardableResult
    func moveTask(
        goalID: UUID,
        taskID: UUID,
        toGoalID: UUID,
        persistImmediately: Bool = true
    ) -> Bool {
        guard goalID != toGoalID,
              var sourceGoal = goals.first(where: { $0.id == goalID }),
              var destinationGoal = goals.first(where: { $0.id == toGoalID }),
              let taskIndex = sourceGoal.tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        var task = sourceGoal.tasks.remove(at: taskIndex)
        task.sortOrder = (destinationGoal.tasks.map(\.sortOrder).max() ?? -1) + 1
        task.updatedAt = .now
        destinationGoal.tasks.append(task)
        replace(sourceGoal)
        replace(destinationGoal)
        if persistImmediately { persist() }
        return true
    }

    func setTaskRecurrence(
        goalID: UUID,
        taskID: UUID,
        rule: RecurringRule?,
        recordChanges: Bool = true,
        persistImmediately: Bool = true
    ) {
        guard let current = goals
            .first(where: { $0.id == goalID })?
            .tasks.first(where: { $0.id == taskID }) else { return }
        var updated = current
        updated.recurringRule = rule
        if rule == nil { updated.recurrenceRootID = nil }
        _ = saveEditedTask(
            updated,
            original: current,
            goalID: goalID,
            recordChanges: recordChanges,
            persistImmediately: persistImmediately
        )
    }

    func archiveTask(goalID: UUID, taskID: UUID) {
        // Delegate archive logic to ArchiveService (P2-2)
        updateTask(goalID: goalID, taskID: taskID) { task in
            task = self.archiveService.archived(task)
        }
    }

    func moveTask(goalID: UUID, taskID: UUID, to date: Date?) {
        let override = automaticDistributionOverride(goalID: goalID, taskID: taskID)
        let saved = updateTask(goalID: goalID, taskID: taskID, persistenceKind: override ?? .userEdit) { task in
            let calendar = businessCalendar.calendar
            task.plannedDate = date.map { calendar.startOfDay(for: $0) }
            task.executionWeekStart = nil
            if let date, let oldStartTime = task.startTime {
                let time = calendar.dateComponents([.hour, .minute, .second], from: oldStartTime)
                task.startTime = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: date)
            } else if date == nil {
                task.startTime = nil
            }
        }
        if saved, override != nil { removeAutomaticDistributionChange(goalID: goalID, taskID: taskID) }
    }

    func moveTaskToTop(goalID: UUID, taskID: UUID, on date: Date) {
        let tasksForDay = tasks(on: date)
        let lowest = tasksForDay.map(\.task.sortOrder).min() ?? 0
        updateTask(goalID: goalID, taskID: taskID) { $0.sortOrder = lowest - 1 }
    }

    func moveTaskToBottom(goalID: UUID, taskID: UUID, on date: Date) {
        let tasksForDay = tasks(on: date)
        let highest = tasksForDay.map(\.task.sortOrder).max() ?? 0
        updateTask(goalID: goalID, taskID: taskID) { $0.sortOrder = highest + 1 }
    }

    func moveTask(goalID: UUID, taskID: UUID, before targetGoalID: UUID, targetTaskID: UUID) {
        guard let target = task(goalID: targetGoalID, taskID: targetTaskID) else { return }
        updateTask(goalID: goalID, taskID: taskID) { task in
            task.plannedDate = target.plannedDate
            task.sortOrder = target.sortOrder - 1
        }
    }

    func reorderTask(
        goalID: UUID,
        taskID: UUID,
        before targetGoalID: UUID,
        targetTaskID: UUID,
        on date: Date,
        persistImmediately: Bool = true
    ) {
        reorderTask(
            goalID: goalID,
            taskID: taskID,
            before: TaskReference(goalID: targetGoalID, taskID: targetTaskID),
            on: date,
            persistImmediately: persistImmediately
        )
    }

    /// Reorders a task at an exact insertion point. A nil target appends it to
    /// the end, which lets a whole day column respond to drops in empty space.
    func reorderTask(
        goalID: UUID,
        taskID: UUID,
        before target: TaskReference?,
        on date: Date,
        persistImmediately: Bool = true
    ) {
        let orderedEntries = tasks(on: date)
        guard let sourceEntry = orderedEntries.first(where: {
            $0.goal.id == goalID && $0.task.id == taskID
        }) else { return }

        var reordered = orderedEntries.filter {
            !($0.goal.id == goalID && $0.task.id == taskID)
        }
        if let target,
           let targetIndex = reordered.firstIndex(where: {
               $0.goal.id == target.goalID && $0.task.id == target.taskID
           }) {
            reordered.insert(sourceEntry, at: targetIndex)
        } else {
            reordered.append(sourceEntry)
        }

        let currentOrder = orderedEntries.map { TaskReference(goalID: $0.goal.id, taskID: $0.task.id) }
        let nextOrder = reordered.map { TaskReference(goalID: $0.goal.id, taskID: $0.task.id) }
        guard currentOrder != nextOrder else {
            if persistImmediately { persist() }
            return
        }

        for (sortOrder, entry) in reordered.enumerated() {
            guard let goalIndex = goals.firstIndex(where: { $0.id == entry.goal.id }),
                  let taskIndex = goals[goalIndex].tasks.firstIndex(where: {
                      $0.id == entry.task.id
                  }) else { continue }
            goals[goalIndex].tasks[taskIndex].sortOrder = sortOrder
            goals[goalIndex].tasks[taskIndex].updatedAt = .now
        }
        if persistImmediately { persist() }
    }

    func restoreTask(goalID: UUID, taskID: UUID) {
        guard var goal = goals.first(where: { $0.id == goalID }),
              let index = goal.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        // Delegate restore logic to ArchiveService (P2-2)
        goal.tasks[index] = archiveService.restored(goal.tasks[index], to: .now)
        goal.archivedAt = nil
        replace(goal)
        selectedGoalID = goal.id
        persist()
    }


    func addSubtask(
        goalID: UUID,
        taskID: UUID,
        title: String,
        persistImmediately: Bool = true
    ) -> UUID {
        // P1-5 fix: delegate to TaskService for title trimming + creation.
        let subtask = TaskSubtask(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !subtask.title.isEmpty else { return subtask.id }
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) {
            $0.subtasks.append(subtask)
        }
        return subtask.id
    }

    func updateSubtaskTitle(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        title: String,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].title = title
        }
    }

    func updateSubtaskActualMinutes(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        minutes: Int,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].actualMinutes = max(minutes, 0)
        }
    }

    func updateSubtaskPlannedMinutes(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        minutes: Int,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].plannedMinutes = max(minutes, 0)
        }
    }

    func deleteSubtask(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        persistImmediately: Bool = true
    ) {
        // P1-5 fix: delegate to TaskService.
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            task = taskService.withDeletedSubtask(task, subtaskID: subtaskID)
        }
    }

    func moveSubtask(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        to targetSubtaskID: UUID?,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let sourceIndex = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            guard let targetSubtaskID else {
                let subtask = task.subtasks.remove(at: sourceIndex)
                task.subtasks.append(subtask)
                return
            }
            guard subtaskID != targetSubtaskID,
                  let targetIndex = task.subtasks.firstIndex(where: { $0.id == targetSubtaskID }) else { return }
            let subtask = task.subtasks.remove(at: sourceIndex)
            task.subtasks.insert(subtask, at: min(targetIndex, task.subtasks.endIndex))
        }
    }

    func toggleSubtask(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].completed.toggle()
            task.subtasks[index].completedAt = task.subtasks[index].completed ? .now : nil
            if task.subtasks[index].completed && !task.completionCredits.contains(where: { $0.reason == .subtaskCompleted && businessCalendar.calendar.isDateInToday($0.date) }) {
                task.completionCredits.append(CompletionCredit(date: .now, reason: .subtaskCompleted, minutes: nil))
            }
        }
    }

}
