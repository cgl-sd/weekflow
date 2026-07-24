import Foundation
import Observation

// Task duplication, clipboard, move, reorder, and archive operations.

extension WeekflowStore {
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
}
