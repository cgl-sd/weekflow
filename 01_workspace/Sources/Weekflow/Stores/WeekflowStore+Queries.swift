import Foundation
import Observation

// Computed properties, task queries, channel operations, and sorting.

extension WeekflowStore {
    /// The currently active (non-archived) plan, if any.
    var activePlan: WeeklyPlan? {
        plans.first(where: { $0.isActive })
    }

    /// All archived plans, sorted by archive date descending.
    var archivedPlans: [WeeklyPlan] {
        plans.filter(\.isArchived).sorted {
            ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast)
        }
    }

    /// All deleted (trashed) plans.
    var deletedPlans: [WeeklyPlan] {
        plans.filter(\.isDeleted).sorted {
            ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast)
        }
    }

    var selectedGoal: WeeklyGoal? {
        selectedGoalID.flatMap { id in goalIndex(for: id).map { goals[$0] } }
    }

    var activeGoals: [WeeklyGoal] {
        // Touch `goals` so @Observable registers the dependency even on a hit.
        let source = goals
        if let cached = activeGoalsCache { return cached }
        let computed = goalService.activeGoals(in: source)
        activeGoalsCache = computed
        return computed
    }
    var archivedGoals: [WeeklyGoal] {
        let source = goals
        if let cached = archivedGoalsCache { return cached }
        let computed = goalService.archivedGoals(in: source)
        archivedGoalsCache = computed
        return computed
    }
    var deletedGoals: [WeeklyGoal] {
        let source = goals
        if let cached = deletedGoalsCache { return cached }
        let computed = goalService.deletedGoals(in: source)
        deletedGoalsCache = computed
        return computed
    }
    var todayTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        tasks(on: .now)
    }
    var activeTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        if let cached = activeTasksCache {
            _ = goals   // register observation on cache hit
            return cached
        }
        let computed = goalService.activeTasks(in: goals)
        activeTasksCache = computed
        return computed
    }
    var taskPool: [(goal: WeeklyGoal, task: WeekTask)] {
        if let cached = taskPoolCache {
            _ = goals   // register observation on cache hit
            return cached
        }
        let computed = goalService.taskPool(in: goals)
        taskPoolCache = computed
        return computed
    }
    var weeklyPlanningPoolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        if let cached = weeklyPlanningPoolCache {
            _ = goals   // register observation on cache hit
            return cached
        }
        let computed = activeGoals.flatMap { goal -> [(goal: WeeklyGoal, task: WeekTask)] in
            let visibleSubgoals = goal.displayableSubgoals
            if visibleSubgoals.isEmpty {
                let primaryTask = goal.primaryTaskID.flatMap { primaryTaskID in
                    goal.tasks.first(where: {
                        $0.id == primaryTaskID
                            && !$0.isArchived
                            && !$0.isDeleted
                    })
                } ?? goal.tasks.first(where: {
                    $0.subgoalID == nil
                        && $0.sourceType == .weeklyObjective
                        && !$0.isArchived
                        && !$0.isDeleted
                })
                return primaryTask.map { [(goal, $0)] } ?? []
            }

            let taskPairs: [(UUID, WeekTask)] = goal.tasks.compactMap { task in
                guard let subgoalID = task.subgoalID,
                      !task.isArchived,
                      !task.isDeleted else { return nil }
                return (subgoalID, task)
            }
            let tasksBySubgoal = Dictionary(keepingFirst: taskPairs)
            return visibleSubgoals.compactMap { subgoal in
                tasksBySubgoal[subgoal.id].map { (goal, $0) }
            }
        }
        weeklyPlanningPoolCache = computed
        return computed
    }
    func weeklyPlanningTasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        let day = businessCalendar.day(containing: date)
        if let cached = weeklyPlanningTasksByDayCache[day] {
            _ = goals   // register observation on cache hit
            return cached
        }
        let allowedReferences = Set(
            weeklyPlanningPoolEntries.map {
                TaskReference(goalID: $0.goal.id, taskID: $0.task.id)
            }
        )
        let computed = activeTasks.filter {
            allowedReferences.contains(TaskReference(goalID: $0.goal.id, taskID: $0.task.id))
                && ($0.task.plannedDay == day || $0.task.assignedDays.contains(day))
        }
        weeklyPlanningTasksByDayCache[day] = computed
        return computed
    }
    var archivedTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        goals.filter { !$0.isDeleted }.flatMap { goal in
            goal.tasks
                .filter { $0.isArchived && !$0.isDeleted }
                .sorted { ($0.archivedAt ?? $0.updatedAt) > ($1.archivedAt ?? $1.updatedAt) }
                .map { (goal, $0) }
        }
    }
    var deletedTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        goals.filter { !$0.isDeleted }.flatMap { goal in
            goal.tasks
                .filter(\.isDeleted)
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { (goal, $0) }
        }
    }
    var activeChannels: [TaskChannel] { channels.filter { $0.archivedAt == nil } }

    var weeklyPlanningProjections: [WeeklyPlanningProjection] {
        activeGoals.map(goalService.weeklyPlanningProjection)
    }

    func reviewProjection(for goalID: UUID) -> ReviewProjection? {
        goals.first(where: { $0.id == goalID }).map(goalService.reviewProjection)
    }

    func dailyTaskProjections(on day: LocalDay) -> [DailyTaskProjection] {
        weeklyPlanningProjections.flatMap(\.items).filter {
            $0.plannedDay == day || $0.assignedDays.contains(day)
        }
    }

    /// Quick capture keeps goal selection optional in the composer while still
    /// storing the task in the app's goal-backed data model.
    func quickCaptureGoalID(preferred: WeeklyGoal.ID?) -> WeeklyGoal.ID? {
        if let preferred, activeGoals.contains(where: { $0.id == preferred }) {
            return preferred
        }
        if let selectedGoalID, activeGoals.contains(where: { $0.id == selectedGoalID }) {
            return selectedGoalID
        }
        return activeGoals.first?.id
    }

    func tasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        let day = businessCalendar.day(containing: date)
        if let cached = tasksByDayCache[day] {
            _ = goals
            return cached
        }
        let computed = activeTasks.filter { entry in
            let directlyPlanned = entry.task.plannedDay == day
            return (directlyPlanned || entry.task.assignedDays.contains(day))
                && !entry.task.homeHiddenDays.contains(day)
        }
        .sorted {
            if $0.task.sortOrder != $1.task.sortOrder { return $0.task.sortOrder < $1.task.sortOrder }
            return ($0.task.startTime ?? $0.task.plannedDate ?? .distantFuture)
                < ($1.task.startTime ?? $1.task.plannedDate ?? .distantFuture)
        }
        tasksByDayCache[day] = computed
        return computed
    }

    func tasks(on date: Date, channelID: String) -> [(goal: WeeklyGoal, task: WeekTask)] {
        let entries = tasks(on: date)
        guard channelID != "all" else { return entries }
        return entries.filter { $0.task.channelID == channelID }
    }

    func dailyPlanningTasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        let day = businessCalendar.day(containing: date)
        return activeTasks.filter {
            ($0.task.plannedDay == day || $0.task.assignedDays.contains(day))
                && !$0.task.dailyPlanningHiddenDays.contains(day)
        }
        .sorted {
            if $0.task.sortOrder != $1.task.sortOrder { return $0.task.sortOrder < $1.task.sortOrder }
            return ($0.task.startTime ?? $0.task.plannedDate ?? .distantFuture)
                < ($1.task.startTime ?? $1.task.plannedDate ?? .distantFuture)
        }
    }

    func completionCreditTasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        activeTasks.filter { entry in
            guard entry.task.plannedDate.map({ !businessCalendar.calendar.isDate($0, inSameDayAs: date) }) ?? true else { return false }
            return entry.task.completionCredits.contains { businessCalendar.calendar.isDate($0.date, inSameDayAs: date) }
        }
    }

    // MARK: - Channel Operations

    func channel(for id: String?) -> TaskChannel? {
        channels.first { $0.id == id }
    }

    func updateChannel(_ channel: TaskChannel) {
        guard let index = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        if channel.isDefault {
            for itemIndex in channels.indices { channels[itemIndex].isDefault = channels[itemIndex].id == channel.id }
        }
        channels[index] = channel
        persistChannels()
    }

    func addChannel(
        title: String,
        colorName: String = "gray",
        iconName: String? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let baseID = trimmed.lowercased().replacingOccurrences(of: " ", with: "-")
        let uniqueID = channels.contains(where: { $0.id == baseID }) ? "\(baseID)-\(UUID().uuidString.prefix(4))" : baseID
        channels.append(TaskChannel(
            id: uniqueID,
            title: trimmed,
            colorName: colorName,
            iconName: iconName
        ))
        persistChannels()
    }

    func deleteChannel(id: String) {
        guard let index = channels.firstIndex(where: { $0.id == id && $0.archivedAt == nil }) else { return }
        let wasDefault = channels[index].isDefault
        channels[index].archivedAt = .now
        channels[index].isDefault = false
        if wasDefault, let replacement = channels.indices.first(where: { channels[$0].archivedAt == nil }) {
            channels[replacement].isDefault = true
        }
        persistChannels()
    }

    // MARK: - Task Sorting

    func sortTasksByPriority(on date: Date) {
        reorderTasksByPriority(on: date)
        persist()
    }

    func sortTasksByStartTime(on date: Date) {
        let currentEntries = tasks(on: date)
        let currentPositions = Dictionary(keepingFirst: currentEntries.enumerated().map { index, entry in
            (TaskReference(goalID: entry.goal.id, taskID: entry.task.id), index)
        })
        var timedEntries = currentEntries
            .filter { $0.task.startTime != nil }
            .sorted { first, second in
                guard let firstTime = first.task.startTime,
                      let secondTime = second.task.startTime else { return false }
                if firstTime != secondTime { return firstTime < secondTime }

                let firstReference = TaskReference(goalID: first.goal.id, taskID: first.task.id)
                let secondReference = TaskReference(goalID: second.goal.id, taskID: second.task.id)
                return (currentPositions[firstReference] ?? .max)
                    < (currentPositions[secondReference] ?? .max)
            }
            .makeIterator()

        let orderedEntries = currentEntries.map { entry in
            guard entry.task.startTime != nil else { return entry }
            return timedEntries.next() ?? entry
        }
        applyTaskOrder(orderedEntries)
        persist()
    }
}
