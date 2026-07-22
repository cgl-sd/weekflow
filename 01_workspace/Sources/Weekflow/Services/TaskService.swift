import Foundation

/// Task business logic service (P2-2 Store split).
///
/// Encapsulates task manipulation rules independent of persistence and UI.
/// The Store coordinates state and persistence; this service handles the
/// domain logic for task creation, mutation, and lifecycle.
struct TaskService {
    let businessCalendar: any BusinessCalendarProviding

    init(businessCalendar: any BusinessCalendarProviding = BusinessCalendar()) {
        self.businessCalendar = businessCalendar
    }

    // MARK: - Task Creation

    /// Creates a new task with computed sort order and inherited channel.
    func makeTask(
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
        channelID: String?,
        defaultChannelID: String?,
        contextID: String? = nil,
        priority: TaskPriority = .none,
        sourceType: TaskSourceType = .native,
        sourceURL: String? = nil,
        description: String = "",
        recurringRule: RecurringRule? = nil,
        existingTasks: [WeekTask]
    ) -> WeekTask {
        let inheritedChannel = channelID ?? defaultChannelID
        let sortOrder = existingTasks.filter { task in
            guard let taskDate = task.plannedDate, let plannedDate else { return false }
            return businessCalendar.calendar.isDate(taskDate, inSameDayAs: plannedDate)
        }.map(\.sortOrder).max().map { $0 + 1 } ?? 0

        var links: [TaskLink] = []
        if let sourceURL, let url = URL(string: sourceURL), url.scheme != nil {
            links = [TaskLink(title: url.host ?? sourceURL, url: sourceURL)]
        }

        return WeekTask(
            title: title,
            plannedDate: plannedDate.map { businessCalendar.calendar.startOfDay(for: $0) },
            startTime: startTime,
            dueDate: dueDate,
            executionWeekStart: executionWeekStart,
            estimatedMinutes: max(minutes, 0),
            notes: notes,
            description: description.isEmpty ? notes : description,
            milestoneID: milestoneID,
            parentTaskID: parentTaskID,
            subgoalID: subgoalID,
            channelID: inheritedChannel,
            contextID: contextID,
            priority: priority,
            sourceType: sourceType,
            sourceURL: sourceURL,
            links: links,
            recurringRule: recurringRule,
            sortOrder: sortOrder
        )
    }

    // MARK: - Task Toggle

    /// Applies toggle logic to a task, syncing subgoal state if linked.
    /// Returns the modified goal.
    func toggledGoal(_ goal: WeeklyGoal, taskID: UUID, goalService: GoalServicing) -> WeeklyGoal? {
        guard var mutableGoal = goal.tasks.first(where: { $0.id == taskID }).map({ _ in goal }) else { return nil }
        guard let index = mutableGoal.tasks.firstIndex(where: { $0.id == taskID }) else { return nil }

        let completesTask = mutableGoal.tasks[index].status != .completed
        mutableGoal.tasks[index].status = completesTask ? .completed : .planned
        mutableGoal.tasks[index].archivedAt = completesTask ? .now : nil
        mutableGoal.tasks[index].updatedAt = .now

        // Sync subgoal state if this task is linked to one
        if let subgoalID = mutableGoal.tasks[index].subgoalID,
           let subgoalIndex = mutableGoal.subgoals.firstIndex(where: { $0.id == subgoalID }) {
            mutableGoal.subgoals[subgoalIndex].isCompleted = mutableGoal.tasks[index].status == .completed
            let allSubgoalsCompleted = !mutableGoal.subgoals.isEmpty && mutableGoal.subgoals.allSatisfy(\.isCompleted)
            mutableGoal.completedAt = allSubgoalsCompleted ? (mutableGoal.completedAt ?? .now) : nil
        }

        if mutableGoal.tasks[index].status != .completed {
            mutableGoal.completedAt = nil
        }

        return goalService.applyPrimaryProjectionEdit(mutableGoal)
    }

    /// Checks if a completed task needs a recurring instance created.
    func needsRecurringInstance(_ task: WeekTask) -> Bool {
        task.status == .completed && task.recurringRule != nil
    }

    // MARK: - Task Status

    /// Applies status change to a task.
    func withStatus(_ task: WeekTask, status: TaskStatus) -> WeekTask {
        var mutableTask = task
        mutableTask.status = status
        mutableTask.archivedAt = status == .completed || status == .archived ? .now : nil
        mutableTask.updatedAt = .now
        return mutableTask
    }

    // MARK: - Task Assignment

    /// Assigns a task to a specific date.
    func assigned(_ task: WeekTask, to date: Date) -> WeekTask {
        var mutableTask = task
        let day = businessCalendar.day(containing: date)
        if !mutableTask.assignedDays.contains(day) {
            mutableTask.assignedDays.append(day)
        }
        mutableTask.plannedDay = day
        mutableTask.archivedAt = nil
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Removes task assignment from a specific date.
    func unassigned(_ task: WeekTask, from date: Date) -> WeekTask {
        var mutableTask = task
        let day = businessCalendar.day(containing: date)
        mutableTask.assignedDays.removeAll { $0 == day }
        if mutableTask.plannedDay == day {
            mutableTask.plannedDay = mutableTask.assignedDays.first
        }
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Removes all task assignments (moves to backlog).
    func unassigned(_ task: WeekTask) -> WeekTask {
        var mutableTask = task
        mutableTask.assignedDays = []
        mutableTask.plannedDay = nil
        mutableTask.archivedAt = nil
        mutableTask.updatedAt = .now
        return mutableTask
    }

    // MARK: - Task Scheduling

    /// Sets task schedule (date, start time, duration).
    func scheduled(_ task: WeekTask, date: Date, startTime: Date?, minutes: Int) -> WeekTask {
        var mutableTask = task
        mutableTask.plannedDay = businessCalendar.day(containing: date)
        mutableTask.startTime = startTime
        mutableTask.estimatedMinutes = max(minutes, 0)
        mutableTask.updatedAt = .now
        return mutableTask
    }

    // MARK: - Task Duplication

    /// Creates a duplicate of a task with a new ID.
    /// P1-5 fix: enhanced to cover Store's inline duplication logic.
    func duplicated(_ task: WeekTask, newTitle: String? = nil, sortOrder: Int? = nil) -> WeekTask {
        var copy = task
        copy.id = UUID()
        copy.title = newTitle ?? "\(task.title) 副本"
        copy.status = .planned
        copy.archivedAt = nil
        copy.actualMinutes = 0
        copy.actualSeconds = 0
        copy.completionCredits = []
        copy.changeRecords = []
        copy.recurrenceRootID = nil
        copy.createdAt = .now
        copy.updatedAt = .now
        if let sortOrder { copy.sortOrder = sortOrder }
        copy.subtasks = task.subtasks.map { subtask in
            TaskSubtask(title: subtask.title, plannedMinutes: subtask.plannedMinutes)
        }
        return copy
    }

    // MARK: - Change Records

    /// Computes comprehensive change records between original and updated task.
    /// P4-16 fix: this is the single source of truth for change-record diffing.
    /// - Parameters:
    ///   - channelTitle: closure to resolve channel display name from ID.
    func changeRecords(
        from original: WeekTask,
        to updated: WeekTask,
        date: Date,
        source: TaskChangeSource = .manual,
        channelTitle: (String?) -> String = { _ in "未分类" }
    ) -> [TaskChangeRecord] {
        var records: [TaskChangeRecord] = []

        func record(_ field: String, _ oldValue: String, _ newValue: String) {
            guard oldValue != newValue else { return }
            records.append(TaskChangeRecord(date: date, field: field, oldValue: oldValue, newValue: newValue, source: source))
        }

        func dateText(_ value: Date?) -> String {
            value?.formatted(.dateTime.year().month().day().hour().minute()) ?? "未设置"
        }

        func subtaskText(_ subtasks: [TaskSubtask]) -> String {
            subtasks.map {
                "\($0.completed ? "已完成" : "未完成"):\($0.title):\($0.actualMinutes ?? 0):\($0.plannedMinutes ?? 0)"
            }.joined(separator: "|")
        }

        record("标题", original.title, updated.title)
        record("说明", original.description, updated.description)
        record("备注", original.notes, updated.notes)
        record("分类", channelTitle(original.channelID), channelTitle(updated.channelID))
        record("优先级", original.priority.label, updated.priority.label)
        record("安排日期", dateText(original.plannedDate), dateText(updated.plannedDate))
        record("截止日期", dateText(original.dueDate), dateText(updated.dueDate))
        record("开始时间", dateText(original.startTime), dateText(updated.startTime))
        record("预计时间", original.estimatedMinutes.hourMinuteClockText, updated.estimatedMinutes.hourMinuteClockText)
        record("实际时间", original.actualMinutes.hourMinuteClockText, updated.actualMinutes.hourMinuteClockText)
        record("重复", original.recurringRule?.frequency.label ?? "不重复", updated.recurringRule?.frequency.label ?? "不重复")
        record("完成状态", original.status.rawValue, updated.status.rawValue)
        record("子任务", subtaskText(original.subtasks), subtaskText(updated.subtasks))

        return records
    }

    // MARK: - Subtask Operations

    /// Adds a subtask to a task.
    func withAddedSubtask(_ task: WeekTask, title: String) -> WeekTask {
        var mutableTask = task
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return task }
        mutableTask.subtasks.append(TaskSubtask(title: cleanTitle))
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Toggles a subtask's completion state.
    func withToggledSubtask(_ task: WeekTask, subtaskID: UUID) -> WeekTask {
        var mutableTask = task
        guard let index = mutableTask.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return task }
        mutableTask.subtasks[index].completed.toggle()
        mutableTask.subtasks[index].completedAt = mutableTask.subtasks[index].completed ? .now : nil
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Deletes a subtask.
    func withDeletedSubtask(_ task: WeekTask, subtaskID: UUID) -> WeekTask {
        var mutableTask = task
        mutableTask.subtasks.removeAll { $0.id == subtaskID }
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Moves a subtask to a new position.
    func withMovedSubtask(_ task: WeekTask, subtaskID: UUID, toIndex: Int) -> WeekTask {
        var mutableTask = task
        guard let fromIndex = mutableTask.subtasks.firstIndex(where: { $0.id == subtaskID }),
              toIndex >= 0, toIndex < mutableTask.subtasks.count else { return task }
        let subtask = mutableTask.subtasks.remove(at: fromIndex)
        mutableTask.subtasks.insert(subtask, at: toIndex)
        mutableTask.updatedAt = .now
        return mutableTask
    }
}
