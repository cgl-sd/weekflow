import Foundation
import Observation

// Task CRUD, mutation, assignment, and persistence operations.

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
        // D-6 fix: O(1) goal lookup.
        guard let goalIdx = goalIndex(for: goalID) else { return nil }
        var goal = goals[goalIdx]
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
        // D-6 fix: O(1) goal lookup.
        guard let goalIdx = goalIndex(for: goalID) else { return }
        var goal = goals[goalIdx]
        guard let index = goal.tasks.firstIndex(where: { $0.id == taskID }) else { return }
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
        ) { [taskService] task in
            task = taskService.relocated(task, from: sourceDate, to: date)
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
    @discardableResult
    func persistForTermination() async -> Bool {
        textInputDebouncer.cancelPending()
        persistenceCoordinator.cancelAllPending()
        persistenceCoordinator.beginSyncWrite()
        // Keep the barrier raised until every already-claimed write has finished
        // its disk operation. Otherwise a delayed stale operation could land after
        // the authoritative exit snapshot.
        await persistenceCoordinator.flush()
        defer { persistenceCoordinator.endSyncWrite() }

        let snapshot = makeApplicationSnapshot()
        return await persistSafelyAsync(
            "退出保存",
            operation: { [storage] in
                try await storage.saveApplicationSnapshotAsync(snapshot)
            },
            commit: {
                persistedGoals = snapshot.goals
                persistedPlans = snapshot.plans
                persistedChannels = snapshot.channels
                persistedCalendarEvents = snapshot.calendarEvents
                persistedDailyPlanningStates = snapshot.dailyPlanningStates
                persistedFocusRecords = snapshot.focusRecords
                persistedDailySummaries = snapshot.dailySummaries
            },
            // The repository transaction has already rolled back on failure. Keep
            // the current in-memory edits so cancelling termination does not erase
            // the user's latest work.
            rollback: {}
        )
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
        // D-6 fix: O(1) goal lookup.
        guard let goalIdx = goalIndex(for: goalID) else { return }
        var goal = goals[goalIdx]
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
}
