import Foundation
import Observation

// Goal CRUD, lifecycle transitions, and week-level operations.

extension WeekflowStore {
    @discardableResult
    func addGoal(
        title: String,
        outcome: String,
        startDate: Date = .now,
        endDate: Date,
        channelID: String? = nil,
        subgoals: [GoalSubgoal] = [],
        persistImmediately: Bool = true
    ) -> UUID {
        var newGoal = WeeklyGoal(
            title: title,
            outcome: outcome,
            startDate: startDate,
            endDate: endDate,
            channelID: channelID,
            subgoals: subgoals
        )
        newGoal.sortOrder = (activeGoals.map(\.sortOrder).min() ?? 0) - 1
        if subgoals.isEmpty {
            let primaryTask = WeekTask(
                title: title,
                dueDate: endDate,
                estimatedMinutes: 60,
                notes: outcome,
                description: outcome,
                channelID: channelID,
                sourceType: .weeklyObjective
            )
            newGoal.primaryTaskID = primaryTask.id
            newGoal.tasks.append(primaryTask)
        }
        newGoal = goalService.project(newGoal)
        goals.insert(newGoal, at: 0)
        invalidateGoalIndex()
        selectedGoalID = newGoal.id
        if persistImmediately { persist() }
        return newGoal.id
    }

    @discardableResult
    func ensurePrimaryTask(forGoalID goalID: UUID) -> WeekTask.ID? {
        guard var goal = goals.first(where: { $0.id == goalID }) else { return nil }
        if let primaryTaskID = goal.primaryTaskID,
           let taskIndex = goal.tasks.firstIndex(where: { $0.id == primaryTaskID }) {
            var task = goal.tasks[taskIndex]
            task.title = goal.title
            task.description = goal.outcome
            task.notes = goal.outcome
            task.dueDate = goal.endDate
            task.channelID = goal.channelID
            task.sourceType = .weeklyObjective
            task.subtasks = goalService.primarySubtasks(for: goal.subgoals, preserving: task.subtasks)
            if task != goal.tasks[taskIndex] {
                task.updatedAt = .now
                goal.tasks[taskIndex] = task
                replace(goal)
                persist()
            }
            return primaryTaskID
        }
        let task = WeekTask(
            title: goal.title,
            dueDate: goal.endDate,
            estimatedMinutes: 60,
            notes: goal.outcome,
            description: goal.outcome,
            channelID: goal.channelID,
            sourceType: .weeklyObjective,
            subtasks: goalService.primarySubtasks(for: goal.subgoals, preserving: [])
        )
        goal.primaryTaskID = task.id
        goal.tasks.append(task)
        replace(goal)
        persist()
        return task.id
    }

    func updateGoal(_ goal: WeeklyGoal) {
        replace(goalService.project(goal))
        persist()
    }

    func setGoalCompleted(id: UUID, completed: Bool) {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.completedAt = completed ? .now : nil
        for taskIndex in goal.tasks.indices where !goal.tasks[taskIndex].isDeleted
            && (!goal.tasks[taskIndex].isArchived || goal.tasks[taskIndex].status == .completed) {
            goal.tasks[taskIndex].status = completed ? .completed : .planned
            goal.tasks[taskIndex].archivedAt = completed ? .now : nil
            goal.tasks[taskIndex].updatedAt = .now
        }
        for subgoalIndex in goal.subgoals.indices {
            goal.subgoals[subgoalIndex].isCompleted = completed
        }
        replace(goal)
        persist()
    }

    func archiveGoal(id: UUID) {
        guard let goal = goals.first(where: { $0.id == id }) else { return }
        let outcome = goalLifecycle.archive(goal)
        applyLifecycleOutcome(outcome, goalID: id)
    }

    func discardGoalDraft(id: UUID) {
        guard let goal = goals.first(where: { $0.id == id }) else { return }
        let outcome = goalLifecycle.discardDraft(goal)
        applyLifecycleOutcome(outcome, goalID: id)
    }

    func restoreGoal(id: UUID) {
        guard let goal = goals.first(where: { $0.id == id }) else { return }
        let outcome = goalLifecycle.restore(goal)
        applyLifecycleOutcome(outcome, goalID: id)
        selectedGoalID = id
    }

    func deleteGoal(id: UUID) {
        guard let goal = goals.first(where: { $0.id == id }) else { return }
        let outcome = goalLifecycle.trash(goal)
        applyLifecycleOutcome(outcome, goalID: id)
    }

    func restoreDeletedGoal(id: UUID) {
        guard let goal = goals.first(where: { $0.id == id }) else { return }
        let outcome = goalLifecycle.restoreFromTrash(goal)
        applyLifecycleOutcome(outcome, goalID: id)
        selectedGoalID = id
    }

    func permanentlyDeleteGoal(id: UUID) {
        guard let goal = goals.first(where: { $0.id == id }) else { return }
        guard let outcome = goalLifecycle.purge(goal) else { return }
        applyLifecycleOutcome(outcome, goalID: id)
    }

    func permanentlyDeleteAllDeletedGoals() {
        let targets = deletedGoals
        guard !targets.isEmpty else { return }
        for goal in targets {
            if let outcome = goalLifecycle.purge(goal) {
                applyLifecycleOutcome(outcome, goalID: goal.id)
            }
        }
    }

    /// P2-1: Applies a lifecycle outcome from the GoalLifecycleCoordinator.
    /// Centralizes state mutation + persistence so individual methods stay thin.
    func applyLifecycleOutcome(_ outcome: GoalLifecycleCoordinator.LifecycleOutcome, goalID: UUID) {
        if outcome.removed {
            goals.removeAll { $0.id == goalID }
            invalidateGoalIndex()
        } else if let updated = outcome.updatedGoal {
            replace(updated)
        }
        if outcome.selectionInvalidated, selectedGoalID == goalID {
            selectedGoalID = activeGoals.first?.id
        }
        if outcome.clearHighlight, highlightedTask?.goalID == goalID {
            highlightedTask = nil
        }
        persist()
    }

    @discardableResult

    func duplicateGoal(id: UUID, now: Date = .now) -> UUID? {
        copyGoal(id: id, titleSuffix: " 副本", dayOffset: 0, now: now)
    }

    @discardableResult
    func addGoalToNextWeek(id: UUID, now: Date = .now) -> UUID? {
        copyGoal(id: id, titleSuffix: "", dayOffset: 7, now: now)
    }

    func copyGoalToClipboard(id: UUID, cutsSource: Bool = false) {
        guard goals.contains(where: { $0.id == id }) else { return }
        goalClipboard = (id, cutsSource)
    }

    @discardableResult
    func pasteGoalClipboard(
        toWeekContaining date: Date,
        afterGoalID anchorGoalID: UUID? = nil,
        now: Date = .now
    ) -> UUID? {
        guard let clipboard = goalClipboard,
              let source = goals.first(where: { $0.id == clipboard.goalID }) else { return nil }
        let targetWeekStart = weekStart(containing: date)
        let sourceWeekStart = weekStart(containing: source.startDate)
        let dayOffset = businessCalendar.calendar.dateComponents(
            [.day],
            from: sourceWeekStart,
            to: targetWeekStart
        ).day ?? 0
        if clipboard.cutsSource {
            shiftGoal(id: source.id, byDays: dayOffset, now: now)
            goalClipboard = nil
            placeGoal(source.id, after: anchorGoalID)
            return source.id
        }
        guard let copiedID = copyGoal(
            id: source.id,
            titleSuffix: " 副本",
            dayOffset: dayOffset,
            now: now
        ) else { return nil }
        placeGoal(copiedID, after: anchorGoalID)
        return copiedID
    }

    func moveGoalToNextWeek(id: UUID, now: Date = .now) {
        shiftGoal(id: id, byDays: 7, now: now)
    }

    func shiftGoal(id: UUID, byDays dayOffset: Int, now: Date) {
        guard dayOffset != 0,
              var goal = goals.first(where: { $0.id == id }) else { return }
        let calendar = businessCalendar.calendar
        let shifted: (Date) -> Date = { date in
            calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }
        goal.startDate = shifted(goal.startDate)
        goal.endDate = shifted(goal.endDate)
        for index in goal.milestones.indices {
            goal.milestones[index].date = shifted(goal.milestones[index].date)
        }
        for index in goal.tasks.indices {
            goal.tasks[index].plannedDate = goal.tasks[index].plannedDate.map(shifted)
            goal.tasks[index].assignedDates = goal.tasks[index].assignedDates.map(shifted)
            goal.tasks[index].startTime = goal.tasks[index].startTime.map(shifted)
            goal.tasks[index].dueDate = goal.tasks[index].dueDate.map(shifted)
            goal.tasks[index].executionWeekStart = goal.tasks[index].executionWeekStart.map(shifted)
            goal.tasks[index].updatedAt = now
        }
        replace(goal)
        selectedGoalID = goal.id
        persist()
    }

    func weekStart(containing date: Date) -> Date {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    func placeGoal(_ movingGoalID: UUID, after anchorGoalID: UUID?) {
        guard let anchorGoalID, anchorGoalID != movingGoalID else { return }
        var ordered = activeGoals
        guard let movingIndex = ordered.firstIndex(where: { $0.id == movingGoalID }),
              let anchorIndexBeforeRemoval = ordered.firstIndex(where: { $0.id == anchorGoalID }) else { return }
        let moving = ordered.remove(at: movingIndex)
        let adjustedAnchorIndex = anchorIndexBeforeRemoval - (movingIndex < anchorIndexBeforeRemoval ? 1 : 0)
        ordered.insert(moving, at: min(adjustedAnchorIndex + 1, ordered.endIndex))
        for (sortOrder, goal) in ordered.enumerated() {
            guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { continue }
            goals[index].sortOrder = sortOrder
        }
        persist()
    }

    func copyGoal(
        id: UUID,
        titleSuffix: String,
        dayOffset: Int,
        now: Date
    ) -> UUID? {
        guard let source = goals.first(where: { $0.id == id }) else { return nil }
        let calendar = businessCalendar.calendar
        let shifted: (Date) -> Date = { date in
            calendar.date(byAdding: .day, value: dayOffset, to: date) ?? date
        }
        let subgoalIDs = Dictionary(keepingFirst: source.subgoals.map { ($0.id, UUID()) })
        let milestoneIDs = Dictionary(keepingFirst: source.milestones.map { ($0.id, UUID()) })
        let visibleTasks = source.tasks.filter { !$0.isArchived && !$0.isDeleted }
        let taskIDs = Dictionary(keepingFirst: visibleTasks.map { ($0.id, UUID()) })

        let copiedSubgoals = source.subgoals.map { subgoal in
            GoalSubgoal(
                id: subgoalIDs[subgoal.id] ?? UUID(),
                title: subgoal.title,
                detail: subgoal.detail,
                // P1-6 fix: preserve the subgoal's independent channel on copy.
                channelID: subgoal.channelID,
                isCompleted: false
            )
        }
        let copiedMilestones = source.milestones.map { milestone in
            Milestone(
                id: milestoneIDs[milestone.id] ?? UUID(),
                title: milestone.title,
                date: shifted(milestone.date),
                type: milestone.type
            )
        }
        let copiedTasks = visibleTasks.map { original in
            var copy = original
            copy.id = taskIDs[original.id] ?? UUID()
            copy.plannedDate = original.plannedDate.map(shifted)
            copy.assignedDates = original.assignedDates.map(shifted)
            copy.startTime = original.startTime.map(shifted)
            copy.dueDate = original.dueDate.map(shifted)
            copy.executionWeekStart = original.executionWeekStart.map(shifted)
            copy.actualMinutes = 0
            copy.status = .planned
            copy.milestoneID = original.milestoneID.flatMap { milestoneIDs[$0] }
            copy.parentTaskID = original.parentTaskID.flatMap { taskIDs[$0] }
            copy.subgoalID = original.subgoalID.flatMap { subgoalIDs[$0] }
            copy.changeRecords = []
            copy.subtasks = original.subtasks.map {
                TaskSubtask(title: $0.title, plannedMinutes: $0.plannedMinutes)
            }
            copy.recurrenceRootID = nil
            copy.completionCredits = []
            copy.createdAt = now
            copy.updatedAt = now
            return copy
        }
        let copy = WeeklyGoal(
            title: source.title + titleSuffix,
            outcome: source.outcome,
            startDate: shifted(source.startDate),
            endDate: shifted(source.endDate),
            channelID: source.channelID,
            subgoals: copiedSubgoals,
            carriedFromGoalID: dayOffset == 0 ? source.carriedFromGoalID : source.id,
            tasks: copiedTasks,
            milestones: copiedMilestones,
            isPinned: source.isPinned,
            primaryTaskID: source.primaryTaskID.flatMap { taskIDs[$0] },
            sortOrder: source.sortOrder + 1
        )
        goals.insert(copy, at: 0)
        invalidateGoalIndex()
        selectedGoalID = copy.id
        persist()
        return copy.id
    }

    @discardableResult
    func continueGoalToNextWeek(id: UUID, now: Date = .now) -> UUID? {
        guard var currentGoal = goals.first(where: { $0.id == id }) else { return nil }
        let incomplete = currentGoal.tasks.filter {
            $0.status != .completed && !$0.isArchived && !$0.isDeleted
        }
        guard !incomplete.isEmpty else { return nil }
        let calendar = businessCalendar.calendar
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
        let nextWeekEnd = calendar.date(byAdding: .day, value: 6, to: nextWeekStart) ?? nextWeekStart
        var movedTasks = incomplete
        for index in movedTasks.indices {
            if let plannedDate = movedTasks[index].plannedDate {
                movedTasks[index].plannedDate = calendar.date(byAdding: .day, value: 7, to: plannedDate)
            }
            if let startTime = movedTasks[index].startTime {
                movedTasks[index].startTime = calendar.date(byAdding: .day, value: 7, to: startTime)
            }
            movedTasks[index].status = .planned
            movedTasks[index].rolloverCount += 1
            movedTasks[index].updatedAt = now
        }

        let newGoal = WeeklyGoal(
            title: currentGoal.title,
            outcome: currentGoal.outcome,
            startDate: nextWeekStart,
            endDate: nextWeekEnd,
            channelID: currentGoal.channelID,
            subgoals: currentGoal.subgoals.map { subgoal in
                var copy = subgoal
                copy.isCompleted = false
                return copy
            },
            carriedFromGoalID: currentGoal.id,
            tasks: movedTasks,
            milestones: []
        )
        let movedIDs = Set(incomplete.map(\.id))
        currentGoal.tasks.removeAll { movedIDs.contains($0.id) }
        currentGoal.archivedAt = now
        replace(currentGoal)
        goals.insert(newGoal, at: 0)
        invalidateGoalIndex()
        selectedGoalID = newGoal.id
        persist()
        return newGoal.id
    }

    func moveIncompleteTasksToPool(goalID: UUID) {
        guard let goal = goals.first(where: { $0.id == goalID }) else { return }
        for task in goal.tasks where task.status != .completed && !task.isArchived && !task.isDeleted {
            unassignTask(goalID: goalID, taskID: task.id)
        }
    }

}
