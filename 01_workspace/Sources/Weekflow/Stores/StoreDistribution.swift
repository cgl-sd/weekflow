import Foundation
import Observation

// Automatic task distribution, recurring instances, and daily maintenance.

extension WeekflowStore {
    func performDailyMaintenance() {
        createMissingRecurringInstances()
    }

    func createMissingRecurringInstances() {
        for goal in activeGoals {
            for task in goal.tasks where task.status == .completed {
                createNextRecurringInstanceIfNeeded(for: task, in: goal)
            }
        }
    }

    func createNextRecurringInstanceIfNeeded(for task: WeekTask, in goal: WeeklyGoal) {
        guard let rule = task.recurringRule, let plannedDate = task.plannedDate else { return }
        let offset: Int
        switch rule.frequency {
        case .daily: offset = rule.interval
        case .weekly: offset = rule.interval * 7
        case .monthly:
            let next = businessCalendar.calendar.date(byAdding: .month, value: rule.interval, to: plannedDate) ?? plannedDate
            createRecurringCopy(of: task, in: goal, at: next)
            return
        case .custom: offset = max(rule.interval, 1)
        }
        let next = businessCalendar.calendar.date(byAdding: .day, value: offset, to: plannedDate) ?? plannedDate
        createRecurringCopy(of: task, in: goal, at: next)
    }

    func createRecurringCopy(of task: WeekTask, in goal: WeeklyGoal, at date: Date) {
        let rootID = task.recurrenceRootID ?? task.id
        guard !goal.tasks.contains(where: { ($0.recurrenceRootID ?? $0.id) == rootID && $0.plannedDate.map { businessCalendar.calendar.isDate($0, inSameDayAs: date) } == true }) else { return }
        var updatedGoal = goal
        var copy = task
        copy.id = UUID()
        copy.plannedDate = businessCalendar.calendar.startOfDay(for: date)
        copy.executionWeekStart = nil
        copy.startTime = nil
        copy.status = .planned
        copy.actualMinutes = 0
        copy.subtasks = copy.subtasks.map { TaskSubtask(title: $0.title, plannedMinutes: $0.plannedMinutes) }
        copy.completionCredits = []
        copy.recurrenceRootID = rootID
        copy.createdAt = .now
        copy.updatedAt = .now
        copy.sortOrder = (updatedGoal.tasks.map(\.sortOrder).max() ?? 0) + 1
        updatedGoal.tasks.append(copy)
        replace(updatedGoal)
    }

    func autoDistributeTaskPool(now: Date = .now) {
        // Starting another run commits the previous result. From this point
        // onward only assignments created by this run can be undone.
        guard commitAutomaticDistribution() else { return }
        let calendar = businessCalendar.calendar
        let start = calendar.startOfDay(for: now)
        let currentWeekStart = weekStart(containing: start)
        let nextWeekStart = calendar.date(
            byAdding: .day,
            value: 7,
            to: currentWeekStart
        ) ?? start
        let remainingDayCount = max(
            calendar.dateComponents(
                [.day],
                from: start,
                to: nextWeekStart
            ).day ?? 1,
            1
        )
        // Each pool entry is one subgoal-backed distribution unit. A weekly
        // goal without subgoals contributes its single fallback task instead.
        let subgoalUnits = weeklyPlanningPoolEntries.filter { entry in
            let hasArrangementThisWeek = (entry.task.plannedDate.map {
                let day = calendar.startOfDay(for: $0)
                return day >= currentWeekStart && day < nextWeekStart
            } ?? false) || entry.task.assignedDates.contains {
                let day = calendar.startOfDay(for: $0)
                return day >= currentWeekStart && day < nextWeekStart
            }
            let subgoalIsCompleted = entry.task.subgoalID.flatMap { subgoalID in
                entry.goal.subgoals.first(where: { $0.id == subgoalID })?.isCompleted
            } ?? (entry.task.status == .completed)
            return !subgoalIsCompleted
                && !hasArrangementThisWeek
                && entry.task.executionWeekStart == nil
        }
        guard !subgoalUnits.isEmpty else { return }
        let transactionID = UUID()
        var changedGoalIDs = Set<WeeklyGoal.ID>()
        for (offset, entry) in subgoalUnits.enumerated() {
            guard let goalIndex = goals.firstIndex(where: { $0.id == entry.goal.id }),
                  let taskIndex = goals[goalIndex].tasks.firstIndex(where: {
                      $0.id == entry.task.id
                  }),
                  let date = calendar.date(
                      byAdding: .day,
                      value: offset % remainingDayCount,
                      to: start
                  ) else { continue }
            let targetDay = calendar.startOfDay(for: date)
            guard !goals[goalIndex].tasks[taskIndex].isAssigned(
                on: targetDay,
                calendar: calendar
            ) else { continue }
            goals[goalIndex].tasks[taskIndex].assignedDates.append(targetDay)
            goals[goalIndex].tasks[taskIndex].executionWeekStart = nil
            goals[goalIndex].tasks[taskIndex].updatedAt = now
            automaticDistributionChanges.append(
                AutomaticDistributionChange(
                    transactionID: transactionID,
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    assignedDate: targetDay
                )
            )
            changedGoalIDs.insert(entry.goal.id)
        }
        guard !changedGoalIDs.isEmpty else { return }
        for goalID in changedGoalIDs {
            guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }) else { continue }
            goals[goalIndex] = goalService.project(goals[goalIndex])
        }
        // Snapshot distribution changes for rollback if persist fails (P1-3).
        let previousDistributionChanges = automaticDistributionChanges.filter {
            $0.transactionID != transactionID
        }
        if synchronousPersistence {
            if !persistSync(kind: .automaticDistribution(transactionID: transactionID)) {
                automaticDistributionChanges = previousDistributionChanges
            }
        } else {
            // Non-blocking: enqueue on the coordinator. The single writer queue
            // guarantees ordering after the preceding commit enqueue.
            let currentGoals = goals
            let baselineGoals = persistedGoals
            persistenceCoordinator.enqueue(
                domain: "goals",
                label: "自动分配",
                operation: { [weak self] in
                    guard let self else { return }
                    try PersistenceIdentityValidator.validate(goals: currentGoals)
                    let changes = PersistenceGoalChangeSet.difference(
                        before: baselineGoals,
                        after: currentGoals
                    )
                    guard !changes.isEmpty else { return }
                    try await self.storage.applyGoalChangesAsync(
                        changes,
                        kind: .automaticDistribution(transactionID: transactionID)
                    )
                },
                commit: { [weak self] in
                    self?.persistedGoals = currentGoals
                },
                rollback: { [weak self] in
                    guard let self else { return }
                    self.goals = self.persistedGoals
                    self.invalidateGoalIndex()
                    self.automaticDistributionChanges = previousDistributionChanges
                }
            )
        }
    }

    @discardableResult
    func commitAutomaticDistribution() -> Bool {
        if let transactionID = automaticDistributionChanges.first?.transactionID {
            if synchronousPersistence {
                guard persistSafely("自动分配", operation: {
                    try storage.commitAutomaticDistribution(transactionID: transactionID)
                }, commit: {}, rollback: {}) else { return false }
            } else {
                // Non-blocking: enqueue the metadata commit on the coordinator.
                // If it fails, protection mode activates and subsequent writes
                // are dropped automatically by the coordinator.
                persistenceCoordinator.enqueue(
                    domain: "distributionCommit",
                    label: "确认自动分配",
                    operation: { [weak self] in
                        try await self?.storage.commitAutomaticDistributionAsync(transactionID: transactionID)
                    },
                    commit: {},
                    rollback: {}
                )
            }
        }
        automaticDistributionChanges.removeAll(keepingCapacity: true)
        return true
    }

    func undoAutomaticDistribution() {
        guard !automaticDistributionChanges.isEmpty else { return }
        let calendar = businessCalendar.calendar
        var changedGoalIDs = Set<WeeklyGoal.ID>()
        for change in automaticDistributionChanges {
            guard let goalIndex = goals.firstIndex(where: { $0.id == change.goalID }),
                  let taskIndex = goals[goalIndex].tasks.firstIndex(where: {
                      $0.id == change.taskID
                  }) else { continue }
            let previousCount = goals[goalIndex].tasks[taskIndex].assignedDates.count
            goals[goalIndex].tasks[taskIndex].assignedDates.removeAll {
                calendar.isDate($0, inSameDayAs: change.assignedDate)
            }
            if goals[goalIndex].tasks[taskIndex].assignedDates.count != previousCount {
                goals[goalIndex].tasks[taskIndex].updatedAt = .now
                changedGoalIDs.insert(change.goalID)
            }
        }
        let transactionID = automaticDistributionChanges.first?.transactionID
        guard !changedGoalIDs.isEmpty else {
            automaticDistributionChanges = []
            return
        }
        for goalID in changedGoalIDs {
            guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }) else { continue }
            goals[goalIndex] = goalService.project(goals[goalIndex])
        }
        if synchronousPersistence {
            if let transactionID {
                if persistSync(kind: .undoAutomaticDistribution(transactionID: transactionID)) {
                    automaticDistributionChanges = []
                }
            } else {
                if persistSync() {
                    automaticDistributionChanges = []
                }
            }
        } else {
            // Non-blocking: enqueue on the coordinator with the appropriate kind.
            let kind: PersistenceMutationKind = transactionID.map {
                .undoAutomaticDistribution(transactionID: $0)
            } ?? .userEdit
            let currentGoals = goals
            let baselineGoals = persistedGoals
            persistenceCoordinator.enqueue(
                domain: "goals",
                label: "撤销自动分配",
                operation: { [weak self] in
                    guard let self else { return }
                    try PersistenceIdentityValidator.validate(goals: currentGoals)
                    let changes = PersistenceGoalChangeSet.difference(
                        before: baselineGoals,
                        after: currentGoals
                    )
                    guard !changes.isEmpty else { return }
                    try await self.storage.applyGoalChangesAsync(changes, kind: kind)
                },
                commit: { [weak self] in
                    guard let self else { return }
                    self.persistedGoals = currentGoals
                    self.automaticDistributionChanges = []
                },
                rollback: { [weak self] in
                    guard let self else { return }
                    self.goals = self.persistedGoals
                    self.invalidateGoalIndex()
                }
            )
        }
    }

    func automaticDistributionOverride(
        goalID: UUID,
        taskID: UUID
    ) -> PersistenceMutationKind? {
        let matches = automaticDistributionChanges.filter {
            $0.goalID == goalID && $0.taskID == taskID
        }
        guard let transactionID = matches.first?.transactionID else { return nil }
        return .manualOverride(taskID: taskID, transactionID: transactionID)
    }

    func removeAutomaticDistributionChange(goalID: UUID, taskID: UUID) {
        automaticDistributionChanges.removeAll {
            $0.goalID == goalID && $0.taskID == taskID
        }
    }

}
