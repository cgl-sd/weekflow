import Foundation
import Observation

private struct AutomaticDistributionChange: Equatable {
    let transactionID: UUID
    let goalID: WeeklyGoal.ID
    let taskID: WeekTask.ID
    let assignedDate: Date
}

@MainActor
@Observable
final class WeekflowStore {
    private let goalService = GoalService()
    /// Task business logic service (P2-2 Store split). Handles task creation,
    /// mutation, and lifecycle rules independent of persistence and UI.
    private let taskService: TaskService
    /// Archive/restore business logic service (P2-2 Store split). Handles
    /// lifecycle transitions for archive, trash, and restore operations.
    private let archiveService: ArchiveService
    /// Daily planning business logic service (P2-2 Store split). Handles
    /// cutoff/start time management and task scheduling rules.
    private let planningService: PlanningService
    var goals: [WeeklyGoal]
    var selectedGoalID: WeeklyGoal.ID?
    var channels: [TaskChannel]
    var calendarEvents: [CalendarEvent]
    var dailyPlanningStates: [DailyPlanningState]
    var focusRecords: [FocusRecord]
    var dailySummaries: [DailySummary]
    var highlightedTask: TaskReference?
    /// Extracted timer service (P2-2 Store split). Manages timer session state
    /// independently; the Store delegates timer operations and handles task
    /// mutation + persistence around the service calls.
    let taskTimerService = TaskTimerService()
    var activeTaskTimer: TaskTimerSession? {
        get { taskTimerService.activeSession }
        set { taskTimerService.restore(session: newValue) }
    }
    var pendingTimerRecovery: InterruptedTaskTimerRecovery? {
        get { taskTimerService.pendingRecovery }
        set { taskTimerService.setRecovery(newValue) }
    }
    var activeDay: Date
    private(set) var persistenceIssue: String?
    private let storage: LocalStorage
    private let developmentFixture: WeekflowDevelopmentFixture?
    private var persistenceEnabled: Bool
    /// Coordinates async writes to prevent out-of-order commits (P0-2 fix).
    private let persistenceCoordinator = PersistenceCoordinator()
    private let legacyPreferences: UserDefaults
    private let businessCalendar: any BusinessCalendarProviding
    private var taskClipboard: (reference: TaskReference, cutsSource: Bool)?
    private var goalClipboard: (goalID: UUID, cutsSource: Bool)?
    private var automaticDistributionChanges: [AutomaticDistributionChange] = []
    private var persistedGoals: [WeeklyGoal] = []
    private var persistedChannels: [TaskChannel] = []
    private var persistedCalendarEvents: [CalendarEvent] = []
    private var persistedDailyPlanningStates: [DailyPlanningState] = []
    private var persistedFocusRecords: [FocusRecord] = []
    private var persistedDailySummaries: [DailySummary] = []
    /// Debouncer for text-input persistence. Rapid keystrokes coalesce into a
    /// single write after a 300 ms quiet period (P1-7 requirement).
    @ObservationIgnored private let textInputDebouncer = PersistenceDebouncer()
    /// When true, `persist()` blocks synchronously. Tests set this so they can
    /// reload from disk immediately after mutations without awaiting async I/O.
    var synchronousPersistence = false
    var canUndoAutomaticDistribution: Bool { !automaticDistributionChanges.isEmpty }
    var hasTaskClipboard: Bool {
        guard let taskClipboard else { return false }
        return task(
            goalID: taskClipboard.reference.goalID,
            taskID: taskClipboard.reference.taskID
        ) != nil
    }
    var hasGoalClipboard: Bool {
        guard let goalClipboard else { return false }
        return goals.contains(where: { $0.id == goalClipboard.goalID })
    }

    init(
        storage: LocalStorage = LocalStorage(),
        developmentFixture: WeekflowDevelopmentFixture? = nil,
        legacyPreferences: UserDefaults = .standard,
        businessCalendar: any BusinessCalendarProviding = BusinessCalendar()
    ) {
        self.storage = storage
        self.developmentFixture = developmentFixture
        self.legacyPreferences = legacyPreferences
        self.businessCalendar = businessCalendar
        self.taskService = TaskService(businessCalendar: businessCalendar)
        self.archiveService = ArchiveService(businessCalendar: businessCalendar)
        self.planningService = PlanningService(businessCalendar: businessCalendar)
        activeDay = businessCalendar.date(for: businessCalendar.day(containing: .now))
        self.persistenceEnabled = false
        if let developmentFixture {
            self.goals = developmentFixture.goals
            self.channels = developmentFixture.channels
            self.calendarEvents = developmentFixture.calendarEvents
            self.dailyPlanningStates = []
            self.focusRecords = []
            self.dailySummaries = []
            self.activeDay = developmentFixture.referenceDate
            self.persistenceIssue = nil
            self.persistenceEnabled = false
        } else {
            var loadFailures: [String] = []
            func load<Value>(_ label: String, _ operation: () throws -> Value?) -> Value? {
                do {
                    return try operation()
                } catch {
                    loadFailures.append("\(label)：\(error.localizedDescription)")
                    return nil
                }
            }
            self.goals = load("周目标与任务", storage.load) ?? []
            self.channels = load("频道", storage.loadChannels) ?? TaskChannel.defaults
            self.calendarEvents = load("日历事件", storage.loadCalendarEvents) ?? []
            self.dailyPlanningStates = load("每日计划", storage.loadDailyPlanningStates) ?? []
            self.focusRecords = load("专注记录", storage.loadFocusRecords) ?? []
            self.dailySummaries = load("每日总结", storage.loadDailySummaries) ?? []
            let restoredTimer = load("活动计时", storage.loadActiveTimerSession) ?? nil
            if let restoredTimer,
               goals.contains(where: { goal in
                   goal.tasks.contains(where: { $0.id == restoredTimer.taskID && goal.id == restoredTimer.goalID })
               }) {
                let elapsed = max(Int(Date.now.timeIntervalSince(restoredTimer.startedAt)), 0)
                if elapsed > 24 * 60 * 60 {
                    self.activeTaskTimer = nil
                    self.pendingTimerRecovery = InterruptedTaskTimerRecovery(
                        session: restoredTimer,
                        elapsedSeconds: elapsed
                    )
                    for goalIndex in goals.indices {
                        for taskIndex in goals[goalIndex].tasks.indices
                        where goals[goalIndex].tasks[taskIndex].id == restoredTimer.taskID {
                            goals[goalIndex].tasks[taskIndex].status = .planned
                        }
                    }
                } else {
                    self.activeTaskTimer = restoredTimer
                    self.pendingTimerRecovery = nil
                }
            } else {
                self.activeTaskTimer = nil
                self.pendingTimerRecovery = nil
                if restoredTimer != nil {
                    do {
                        try storage.saveActiveTimerSession(nil)
                    } catch {
                        loadFailures.append("异常计时修复：\(error.localizedDescription)")
                    }
                }
                for goalIndex in goals.indices {
                    for taskIndex in goals[goalIndex].tasks.indices
                    where goals[goalIndex].tasks[taskIndex].status == .inProgress {
                        goals[goalIndex].tasks[taskIndex].status = .planned
                    }
                }
            }
            self.persistenceIssue = loadFailures.isEmpty
                ? nil
                : "本地数据读取失败，本次会话已暂停保存，以免覆盖原文件。\n\n\(loadFailures.joined(separator: "\n"))"
            self.persistenceEnabled = loadFailures.isEmpty
            if loadFailures.isEmpty {
                let pendingChanges: [PersistedAutomaticDistributionChange]
                do {
                    pendingChanges = try storage.pendingAutomaticDistributionChanges()
                } catch {
                    pendingChanges = []
                    self.persistenceIssue = "自动分配事务读取失败，本次会话已暂停保存，以免覆盖原文件。\n\n\(error.localizedDescription)"
                    self.persistenceEnabled = false
                }
                self.automaticDistributionChanges = pendingChanges.map {
                    AutomaticDistributionChange(
                        transactionID: $0.transactionID,
                        goalID: $0.goalID,
                        taskID: $0.taskID,
                        assignedDate: $0.assignedDate
                    )
                }
            }
        }
        self.selectedGoalID = goals.first?.id
        persistedGoals = goals
        persistedChannels = channels
        persistedCalendarEvents = calendarEvents
        persistedDailyPlanningStates = dailyPlanningStates
        persistedFocusRecords = focusRecords
        persistedDailySummaries = dailySummaries
        let synchronizedSubgoalTasks = synchronizeAllSubgoalTasksIfNeeded()
        if developmentFixture == nil, persistenceIssue == nil {
            var needsPersist = synchronizedSubgoalTasks
            needsPersist = migrateLegacyChannelPresentationIfNeeded() || needsPersist
            needsPersist = migrateLegacyDailyPlanningCutoffIfNeeded() || needsPersist
            needsPersist = migrateLegacyDailySummaryIfNeeded() || needsPersist
            performDailyMaintenance()
            // Single consolidated startup persist – avoids multiple independent
            // save calls that could partially commit (P1-3 requirement).
            if needsPersist { persistStartup() }
        }
    }

    @discardableResult
    private func migrateLegacyChannelPresentationIfNeeded() -> Bool {
        let migrationKey = "weekflow.channels.presentationMigration.v1"
        guard !legacyPreferences.bool(forKey: migrationKey) else { return false }
        let defaultsByID = Dictionary(uniqueKeysWithValues: TaskChannel.defaults.map { ($0.id, $0) })
        for index in channels.indices {
            guard let defaultChannel = defaultsByID[channels[index].id] else { continue }
            if channels[index].iconName == nil {
                channels[index].iconName = defaultChannel.iconName
            }
        }
        legacyPreferences.set(true, forKey: migrationKey)
        return true
    }

    var isUsingDevelopmentFixture: Bool { developmentFixture != nil }

    @discardableResult
    func resetDevelopmentFixture() -> Bool {
        guard let developmentFixture else { return false }
        goals = developmentFixture.goals
        channels = developmentFixture.channels
        calendarEvents = developmentFixture.calendarEvents
        dailyPlanningStates = []
        focusRecords = []
        dailySummaries = []
        selectedGoalID = goals.first?.id
        highlightedTask = nil
        activeTaskTimer = nil
        automaticDistributionChanges = []
        activeDay = developmentFixture.referenceDate
        return true
    }

    var selectedGoal: WeeklyGoal? { goals.first { $0.id == selectedGoalID } }
    var activeGoals: [WeeklyGoal] {
        goals.filter { !$0.isArchived && !$0.isDeleted }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.endDate < $1.endDate
        }
    }
    var archivedGoals: [WeeklyGoal] {
        goals.filter { $0.isArchived && !$0.isDeleted }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }
    var deletedGoals: [WeeklyGoal] {
        goals.filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }
    var todayTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        tasks(on: .now)
    }
    var activeTasks: [(goal: WeeklyGoal, task: WeekTask)] {
        activeGoals.flatMap { goal in
            goal.tasks
                .filter { !$0.isArchived && !$0.isDeleted }
                .map { (goal, $0) }
        }
    }
    var taskPool: [(goal: WeeklyGoal, task: WeekTask)] { activeTasks.filter { $0.task.isUnassigned } }
    var weeklyPlanningPoolEntries: [(goal: WeeklyGoal, task: WeekTask)] {
        activeGoals.flatMap { goal in
            if goal.subgoals.isEmpty {
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

            return goal.subgoals.compactMap { subgoal in
                guard let task = goal.tasks.first(where: {
                    $0.subgoalID == subgoal.id
                        && !$0.isArchived
                        && !$0.isDeleted
                }) else { return nil }
                return (goal, task)
            }
        }
    }
    func weeklyPlanningTasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        let allowedReferences = Set(
            weeklyPlanningPoolEntries.map {
                TaskReference(goalID: $0.goal.id, taskID: $0.task.id)
            }
        )
        return tasks(on: date).filter {
            allowedReferences.contains(TaskReference(goalID: $0.goal.id, taskID: $0.task.id))
        }
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
        activeTasks.filter { entry in
            let calendar = businessCalendar.calendar
            let directlyPlanned = entry.task.plannedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            return directlyPlanned || entry.task.isAssigned(on: date, calendar: calendar)
        }
        .sorted {
            if $0.task.sortOrder != $1.task.sortOrder { return $0.task.sortOrder < $1.task.sortOrder }
            return ($0.task.startTime ?? $0.task.plannedDate ?? .distantFuture) < ($1.task.startTime ?? $1.task.plannedDate ?? .distantFuture)
        }
    }

    func tasks(on date: Date, channelID: String) -> [(goal: WeeklyGoal, task: WeekTask)] {
        let entries = tasks(on: date)
        guard channelID != "all" else { return entries }
        return entries.filter { $0.task.channelID == channelID }
    }

    func completionCreditTasks(on date: Date) -> [(goal: WeeklyGoal, task: WeekTask)] {
        activeTasks.filter { entry in
            guard entry.task.plannedDate.map({ !businessCalendar.calendar.isDate($0, inSameDayAs: date) }) ?? true else { return false }
            return entry.task.completionCredits.contains { businessCalendar.calendar.isDate($0.date, inSameDayAs: date) }
        }
    }

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

    func sortTasksByPriority(on date: Date) {
        reorderTasksByPriority(on: date)
        persist()
    }

    func sortTasksByStartTime(on date: Date) {
        let currentEntries = tasks(on: date)
        let currentPositions = Dictionary(uniqueKeysWithValues: currentEntries.enumerated().map { index, entry in
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
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.archivedAt = .now
        goal.deletedAt = nil
        replace(goal)
        selectedGoalID = activeGoals.first?.id
        persist()
    }

    func discardGoalDraft(id: UUID) {
        guard goals.contains(where: { $0.id == id }) else { return }
        goals.removeAll { $0.id == id }
        if selectedGoalID == id {
            selectedGoalID = activeGoals.first?.id
        }
        if let highlightedTask,
           highlightedTask.goalID == id {
            self.highlightedTask = nil
        }
        persist()
    }

    func restoreGoal(id: UUID) {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.archivedAt = nil
        replace(goal)
        selectedGoalID = goal.id
        persist()
    }

    func deleteGoal(id: UUID) {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.deletedAt = .now
        goal.archivedAt = nil
        replace(goal)
        if selectedGoalID == id { selectedGoalID = activeGoals.first?.id }
        if highlightedTask?.goalID == id { highlightedTask = nil }
        persist()
    }

    func restoreDeletedGoal(id: UUID) {
        guard var goal = goals.first(where: { $0.id == id }) else { return }
        goal.deletedAt = nil
        goal.archivedAt = nil
        replace(goal)
        selectedGoalID = goal.id
        persist()
    }

    func permanentlyDeleteGoal(id: UUID) {
        guard goals.contains(where: { $0.id == id && $0.isDeleted }) else { return }
        goals.removeAll { $0.id == id }
        if selectedGoalID == id { selectedGoalID = activeGoals.first?.id }
        if highlightedTask?.goalID == id { highlightedTask = nil }
        persist()
    }

    @discardableResult
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
    private func persistDebounced() {
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

    func setTaskPriority(
        goalID: UUID,
        taskID: UUID,
        priority: TaskPriority,
        on date: Date
    ) {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
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
        guard var goal = goals.first(where: { $0.id == goalID }),
              let index = goal.tasks.firstIndex(where: { $0.id == updatedTask.id }) else { return [] }
        let current = goal.tasks[index]
        let records = manualChangeRecords(from: original, to: updatedTask, date: now)
        guard !records.isEmpty else { return [] }

        var task = updatedTask
        if task.startTime == nil { task.calendarPlacement = .suggested }
        task.changeRecords = recordChanges ? current.changeRecords + records : current.changeRecords
        task.updatedAt = now
        goal.tasks[index] = task
        goal = goalService.applyPrimaryProjectionEdit(goal)
        replace(goal)
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
        guard var goal = goals.first(where: { $0.id == goalID }),
              let index = goal.tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        let current = goal.tasks[index]
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
        goal.tasks[index].changeRecords.append(record)
        goal.tasks[index].updatedAt = now
        replace(goal)
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
        guard var goal = goals.first(where: { $0.id == goalID }) else { return }
        let restoredTask = goal.tasks.first(where: { $0.id == taskID })
        let restoredParentID = restoredTask?.parentTaskID
        if let restoredTask,
           let subgoalID = restoredTask.subgoalID,
           !goal.subgoals.contains(where: { $0.id == subgoalID }) {
            goal.subgoals.append(
                GoalSubgoal(
                    id: subgoalID,
                    title: restoredTask.title,
                    detail: restoredTask.description,
                    isCompleted: false
                )
            )
        }
        for index in goal.tasks.indices where goal.tasks[index].id == taskID || goal.tasks[index].parentTaskID == taskID {
            goal.tasks[index].status = .planned
            goal.tasks[index].archivedAt = nil
            goal.tasks[index].plannedDate = businessCalendar.calendar.startOfDay(for: .now)
            goal.tasks[index].assignedDates = []
            goal.tasks[index].startTime = nil
            goal.tasks[index].executionWeekStart = nil
            goal.tasks[index].updatedAt = .now
        }
        if let restoredParentID,
           let parentIndex = goal.tasks.firstIndex(where: { $0.id == restoredParentID && $0.status == .deleted }) {
            goal.tasks[parentIndex].status = .planned
            goal.tasks[parentIndex].archivedAt = nil
            goal.tasks[parentIndex].updatedAt = .now
        }
        goal = goalService.project(goal)
        replace(goal)
        persist()
    }

    func permanentlyDeleteTask(goalID: UUID, taskID: UUID) {
        guard var goal = goals.first(where: { $0.id == goalID }),
              goal.tasks.contains(where: { $0.id == taskID && $0.isDeleted }) else { return }
        goal.tasks.removeAll { $0.id == taskID || $0.parentTaskID == taskID }
        if goal.primaryTaskID == taskID { goal.primaryTaskID = nil }
        replace(goal)
        if highlightedTask?.goalID == goalID && highlightedTask?.taskID == taskID {
            highlightedTask = nil
        }
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
        var copy = original
        copy.id = UUID()
        copy.title = "\(original.title) 副本"
        copy.actualMinutes = 0
        copy.status = .planned
        copy.changeRecords = []
        copy.subtasks = original.subtasks.map {
            TaskSubtask(title: $0.title, plannedMinutes: $0.plannedMinutes)
        }
        copy.recurrenceRootID = nil
        copy.completionCredits = []
        copy.createdAt = now
        copy.updatedAt = now
        copy.sortOrder = original.sortOrder + 1
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

    private func placeTask(
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

    // MARK: - Task Timer (delegated to TaskTimerService – P2-2)

    func isTaskTimerRunning(goalID: UUID, taskID: UUID) -> Bool {
        taskTimerService.isRunning(goalID: goalID, taskID: taskID)
    }

    func taskTimerStartedAt(goalID: UUID, taskID: UUID) -> Date? {
        taskTimerService.startedAt(goalID: goalID, taskID: taskID)
    }

    func liveTaskActualMinutes(goalID: UUID, taskID: UUID, at date: Date = .now) -> Int {
        guard let current = task(goalID: goalID, taskID: taskID) else { return 0 }
        return taskTimerService.liveActualMinutes(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: current.actualSeconds, at: date
        )
    }

    func startTaskTimer(goalID: UUID, taskID: UUID) {
        startTaskTimer(goalID: goalID, taskID: taskID, now: .now, useMonotonicClock: true)
    }

    func startTaskTimer(goalID: UUID, taskID: UUID, now: Date) {
        startTaskTimer(goalID: goalID, taskID: taskID, now: now, useMonotonicClock: false)
    }

    private func startTaskTimer(
        goalID: UUID,
        taskID: UUID,
        now: Date,
        useMonotonicClock: Bool
    ) {
        guard let current = task(goalID: goalID, taskID: taskID) else { return }
        let rollbackSession = taskTimerService.activeSession
        let settled = taskTimerService.start(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: current.actualSeconds,
            now: now, useMonotonicClock: useMonotonicClock
        )
        if let settled {
            _ = settleTaskTimer(
                goalID: settled.settledGoalID,
                taskID: settled.settledTaskID,
                baseActualSeconds: rollbackSession?.baseActualSeconds ?? 0,
                elapsedSeconds: settled.settledSeconds,
                now: now,
                persistImmediately: false
            )
        }
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: false) { task in
            task.status = .inProgress
            task.archivedAt = nil
        }
        persistTaskAndActiveTimer(rollbackSession: rollbackSession)
    }

    @discardableResult
    func pauseTaskTimer(goalID: UUID, taskID: UUID) -> Int {
        guard let result = taskTimerService.pause(goalID: goalID, taskID: taskID) else { return 0 }
        return settleTaskTimer(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: result.session.baseActualSeconds,
            elapsedSeconds: result.elapsedSeconds,
            now: .now,
            rollbackSession: result.session
        )
    }

    @discardableResult
    func pauseTaskTimer(goalID: UUID, taskID: UUID, now: Date) -> Int {
        guard let result = taskTimerService.pause(
            goalID: goalID, taskID: taskID, now: now, useMonotonicClock: false
        ) else { return 0 }
        return settleTaskTimer(
            goalID: goalID, taskID: taskID,
            baseActualSeconds: result.session.baseActualSeconds,
            elapsedSeconds: result.elapsedSeconds,
            now: now,
            rollbackSession: result.session
        )
    }

    private func settleTaskTimer(
        goalID: UUID,
        taskID: UUID,
        baseActualSeconds: Int,
        elapsedSeconds: Int,
        now: Date,
        persistImmediately: Bool = true,
        rollbackSession: TaskTimerSession? = nil
    ) -> Int {
        guard let current = task(goalID: goalID, taskID: taskID) else { return 0 }
        let newActualSeconds = baseActualSeconds + elapsedSeconds
        let newActualMinutes = DurationDisplay.minutes(for: newActualSeconds)
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: false) { task in
            task.actualMinutes = max(current.actualMinutes, newActualMinutes)
            task.actualSeconds = max(current.actualSeconds, newActualSeconds)
            task.status = .planned
            task.changeRecords.append(TaskChangeRecord(
                date: now,
                field: "实际时间",
                oldValue: DurationDisplay.minutes(for: baseActualSeconds).hourMinuteClockText,
                newValue: max(current.actualMinutes, newActualMinutes).hourMinuteClockText,
                source: .timer
            ))
            if !task.completionCredits.contains(where: { $0.reason == .actualTimeLogged && businessCalendar.calendar.isDate($0.date, inSameDayAs: now) }) {
                task.completionCredits.append(CompletionCredit(
                    date: now,
                    reason: .actualTimeLogged,
                    minutes: DurationDisplay.minutes(for: elapsedSeconds),
                    seconds: elapsedSeconds
                ))
            }
        }
        if persistImmediately {
            persistTaskAndActiveTimer(rollbackSession: rollbackSession)
        }
        return DurationDisplay.minutes(for: elapsedSeconds)
    }

    func toggleTaskTimer(goalID: UUID, taskID: UUID) {
        if isTaskTimerRunning(goalID: goalID, taskID: taskID) {
            pauseTaskTimer(goalID: goalID, taskID: taskID)
        } else {
            startTaskTimer(goalID: goalID, taskID: taskID)
        }
    }

    func toggleTaskTimer(goalID: UUID, taskID: UUID, now: Date) {
        if isTaskTimerRunning(goalID: goalID, taskID: taskID) {
            pauseTaskTimer(goalID: goalID, taskID: taskID, now: now)
        } else {
            startTaskTimer(goalID: goalID, taskID: taskID, now: now)
        }
    }

    func resolveInterruptedTimer(includeElapsedTime: Bool, now: Date = .now) {
        guard let recovery = taskTimerService.pendingRecovery else { return }
        if includeElapsedTime {
            taskTimerService.setRecovery(nil)
            _ = settleTaskTimer(
                goalID: recovery.session.goalID,
                taskID: recovery.session.taskID,
                baseActualSeconds: recovery.session.baseActualSeconds,
                elapsedSeconds: recovery.elapsedSeconds,
                now: now
            )
        } else {
            taskTimerService.setRecovery(nil)
            taskTimerService.clear()
            updateTask(
                goalID: recovery.session.goalID,
                taskID: recovery.session.taskID,
                persistImmediately: false
            ) { task in
                if task.status == .inProgress { task.status = .planned }
            }
            persistTaskAndActiveTimer(rollbackSession: recovery.session)
        }
    }

    func synchronizeActiveTaskTimer(at date: Date = .now) {
        guard let session = taskTimerService.activeSession,
              let current = task(goalID: session.goalID, taskID: session.taskID) else { return }
        let liveMinutes = liveTaskActualMinutes(goalID: session.goalID, taskID: session.taskID, at: date)
        guard liveMinutes > current.actualMinutes else { return }
        updateTask(goalID: session.goalID, taskID: session.taskID) { task in
            task.actualMinutes = liveMinutes
            task.status = .inProgress
        }
    }

    func checkpointActiveTaskTimer(at date: Date = .now) {
        guard let result = taskTimerService.checkpoint(at: date) else { return }
        let checkpointSeconds = result.updated.baseActualSeconds
        updateTask(
            goalID: result.updated.goalID,
            taskID: result.updated.taskID,
            persistImmediately: false
        ) { task in
            task.actualSeconds = max(task.actualSeconds, checkpointSeconds)
            task.actualMinutes = DurationDisplay.minutes(for: task.actualSeconds)
            task.status = .inProgress
        }
        persistTaskAndActiveTimer(rollbackSession: result.previous)
    }

    func recordFocusMinutes(for reference: TaskReference, minutes: Int, now: Date = .now) {
        recordFocusSeconds(for: reference, seconds: minutes * 60, now: now)
    }

    func recordFocusSeconds(for reference: TaskReference, seconds: Int, now: Date = .now) {
        guard seconds > 0, let current = task(goalID: reference.goalID, taskID: reference.taskID) else { return }
        let newActualSeconds = current.actualSeconds + seconds
        let newActualMinutes = DurationDisplay.minutes(for: newActualSeconds)
        updateTask(goalID: reference.goalID, taskID: reference.taskID) { task in
            task.actualMinutes = newActualMinutes
            task.actualSeconds = newActualSeconds
            task.changeRecords.append(TaskChangeRecord(
                date: now,
                field: "实际时间",
                oldValue: current.actualMinutes.hourMinuteClockText,
                newValue: newActualMinutes.hourMinuteClockText,
                source: .timer
            ))
        }
    }

    func recordFocusSession(mode: FocusMode, minutes: Int, date: Date = .now) {
        recordFocusSession(mode: mode, seconds: minutes * 60, date: date)
    }

    func recordFocusSession(mode: FocusMode, seconds: Int, date: Date = .now) {
        guard seconds > 0 else { return }
        let calendar = businessCalendar.calendar
        if let index = focusRecords.firstIndex(where: {
            $0.mode == mode && calendar.isDate($0.date, inSameDayAs: date)
        }) {
            focusRecords[index].seconds += seconds
            focusRecords[index].sessionCount += 1
            focusRecords[index].date = date
        } else {
            focusRecords.append(FocusRecord(
                date: date,
                mode: mode,
                seconds: seconds
            ))
        }
        persistFocusRecords()
    }

    func focusMinutes(on date: Date) -> [FocusMode: Int] {
        Dictionary(grouping: focusRecords.filter {
            businessCalendar.calendar.isDate($0.date, inSameDayAs: date)
        }, by: \.mode)
        .mapValues { $0.reduce(0) { $0 + $1.minutes } }
    }

    func dailySummary(on date: Date) -> DailySummary? {
        dailySummaries.first { businessCalendar.calendar.isDate($0.date, inSameDayAs: date) }
    }

    func saveDailySummary(_ content: String, on date: Date = .now) {
        let day = businessCalendar.calendar.startOfDay(for: date)
        if let index = dailySummaries.firstIndex(where: {
            businessCalendar.calendar.isDate($0.date, inSameDayAs: day)
        }) {
            dailySummaries[index].content = content
            dailySummaries[index].updatedAt = .now
        } else {
            dailySummaries.append(DailySummary(date: day, content: content))
        }
        persistDailySummaries()
    }

    @discardableResult
    func addSubtask(
        goalID: UUID,
        taskID: UUID,
        title: String,
        persistImmediately: Bool = true
    ) -> UUID {
        let subtask = TaskSubtask(title: title)
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
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            task.subtasks.removeAll { $0.id == subtaskID }
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

    func events(on date: Date) -> [CalendarEvent] {
        calendarEvents.filter { businessCalendar.calendar.isDate($0.startDate, inSameDayAs: date) }
            .sorted { $0.startDate < $1.startDate }
    }

    func dailyPlanningCutoffMinutes(on date: Date) -> Int {
        // Delegate to PlanningService (P2-2)
        planningService.cutoffMinutes(for: date, in: dailyPlanningStates)
    }

    func dailyPlanningStartMinutes(on date: Date) -> Int {
        // Delegate to PlanningService (P2-2)
        planningService.startMinutes(for: date, in: dailyPlanningStates)
    }

    @discardableResult
    func setDailyPlanningStart(minutes: Int, on date: Date) -> Int {
        // Delegate computation to PlanningService (P2-2)
        let result = planningService.withStartMinutes(minutes, on: date, in: dailyPlanningStates)
        dailyPlanningStates = result.states
        if dailyPlanningCutoffEvent(on: date) != nil {
            _ = upsertDailyPlanningCutoffEvent(
                on: date,
                minutes: result.cutoff,
                persistImmediately: false
            )
            persistDailyPlanAndCalendarEvents()
        } else {
            persistDailyPlanningStates()
        }
        return result.start
    }

    @discardableResult
    func setDailyPlanningCutoff(minutes: Int, on date: Date) -> Int {
        // Delegate computation to PlanningService (P2-2)
        let result = planningService.withCutoffMinutes(minutes, on: date, in: dailyPlanningStates)
        dailyPlanningStates = result.states
        if dailyPlanningCutoffEvent(on: date) != nil {
            _ = upsertDailyPlanningCutoffEvent(
                on: date,
                minutes: result.cutoff,
                persistImmediately: false
            )
            persistDailyPlanAndCalendarEvents()
        } else {
            persistDailyPlanningStates()
        }
        return result.cutoff
    }

    /// Ensures every task in a daily plan has a concrete clock time. A newly
    /// assigned pool task receives a one-hour default and is inserted after
    /// the preceding task; overlapping following tasks are shifted forward.
    func ensureDailyPlanningTaskSchedule(
        on date: Date,
        newlyAssigned: TaskReference? = nil
    ) {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.date(
            byAdding: .minute,
            value: dailyPlanningStartMinutes(on: day),
            to: day
        ) ?? day
        var cascadesForward = false
        var changed = false

        for entry in tasks(on: day) {
            let reference = TaskReference(goalID: entry.goal.id, taskID: entry.task.id)
            let isNewlyAssigned = reference == newlyAssigned
            let duration = isNewlyAssigned
                ? 60
                : max(entry.task.estimatedMinutes, 1)
            let normalizedExplicitStart = entry.task.startTime.flatMap { startTime in
                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                return calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: day
                )
            }

            let resolvedStart: Date
            if isNewlyAssigned || normalizedExplicitStart == nil {
                resolvedStart = cursor
                cascadesForward = true
            } else if cascadesForward,
                      let normalizedExplicitStart,
                      normalizedExplicitStart < cursor {
                resolvedStart = cursor
            } else {
                resolvedStart = normalizedExplicitStart ?? cursor
            }

            if entry.task.startTime != resolvedStart
                || (isNewlyAssigned && entry.task.estimatedMinutes != duration) {
                updateTask(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    persistImmediately: false
                ) { task in
                    task.startTime = resolvedStart
                    if isNewlyAssigned {
                        task.estimatedMinutes = duration
                    }
                }
                changed = true
            }
            cursor = calendar.date(
                byAdding: .minute,
                value: duration,
                to: resolvedStart
            ) ?? resolvedStart
        }

        if changed { persist() }
    }

    func nextDailyPlanningTaskStart(on date: Date) -> Date {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        var cursor = calendar.date(
            byAdding: .minute,
            value: dailyPlanningStartMinutes(on: day),
            to: day
        ) ?? day
        for entry in tasks(on: day) {
            let explicit = entry.task.startTime.flatMap { startTime in
                let components = calendar.dateComponents([.hour, .minute], from: startTime)
                return calendar.date(
                    bySettingHour: components.hour ?? 0,
                    minute: components.minute ?? 0,
                    second: 0,
                    of: day
                )
            }
            let start = explicit ?? cursor
            cursor = calendar.date(
                byAdding: .minute,
                value: max(entry.task.estimatedMinutes, 1),
                to: start
            ) ?? start
        }
        return cursor
    }

    @discardableResult
    func addDailyPlanningCutoffToCalendar(on date: Date) -> UUID {
        upsertDailyPlanningCutoffEvent(
            on: date,
            minutes: dailyPlanningCutoffMinutes(on: date)
        )
    }

    func dailyPlanningCutoffEvent(on date: Date) -> CalendarEvent? {
        let sourceKey = dailyPlanningCutoffSourceKey(for: date)
        return calendarEvents.first { $0.sourceKey == sourceKey }
    }

    func rolloverTaskManually(
        goalID: UUID,
        taskID: UUID,
        from date: Date,
        to targetDate: Date? = nil
    ) {
        let calendar = businessCalendar.calendar
        let sourceDay = calendar.startOfDay(for: date)
        let destinationDay = calendar.startOfDay(
            for: targetDate
                ?? calendar.date(byAdding: .day, value: 1, to: sourceDay)
                ?? sourceDay
        )
        guard let task = task(goalID: goalID, taskID: taskID),
              task.status != .completed,
              !task.isArchived,
              !task.isDeleted,
              (task.plannedDate.map({ calendar.isDate($0, inSameDayAs: sourceDay) }) == true
                || task.isAssigned(on: sourceDay, calendar: calendar)) else { return }

        updateTask(goalID: goalID, taskID: taskID) { item in
            if item.hasExecutionProgress,
               !item.completionCredits.contains(where: {
                   calendar.isDate($0.date, inSameDayAs: sourceDay)
               }) {
                item.completionCredits.append(
                    CompletionCredit(
                        date: sourceDay,
                        reason: item.actualMinutes > 0 ? .actualTimeLogged : .subtaskCompleted,
                        minutes: item.actualMinutes > 0 ? item.actualMinutes : nil
                    )
                )
            }

            if item.plannedDate == nil || item.sourceType == .weeklyObjective {
                item.assignedDates.removeAll {
                    calendar.isDate($0, inSameDayAs: sourceDay)
                }
                if !item.isAssigned(on: destinationDay, calendar: calendar) {
                    item.assignedDates.append(destinationDay)
                }
            } else {
                item.plannedDate = destinationDay
            }
            item.rolloverCount += 1
            item.startTime = nil
            item.executionWeekStart = nil
        }
    }

    func autoScheduleHighlightedTask() {
        guard let highlightedTask, let task = task(goalID: highlightedTask.goalID, taskID: highlightedTask.taskID) else { return }
        let date = activeDay
        let calendar = businessCalendar.calendar
        let startHour = 14
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = startHour
        components.minute = 0
        setTaskSchedule(goalID: highlightedTask.goalID, taskID: highlightedTask.taskID, date: date, startTime: calendar.date(from: components), minutes: task.estimatedMinutes)
        setTaskCalendarPlacement(
            goalID: highlightedTask.goalID,
            taskID: highlightedTask.taskID,
            placement: .committed
        )
    }

    func performDailyMaintenance() {
        createMissingRecurringInstances()
    }

    private func createMissingRecurringInstances() {
        for goal in activeGoals {
            for task in goal.tasks where task.status == .completed {
                createNextRecurringInstanceIfNeeded(for: task, in: goal)
            }
        }
    }

    private func createNextRecurringInstanceIfNeeded(for task: WeekTask, in goal: WeeklyGoal) {
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

    private func createRecurringCopy(of task: WeekTask, in goal: WeeklyGoal, at date: Date) {
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
        if !persistSync(kind: .automaticDistribution(transactionID: transactionID)) {
            automaticDistributionChanges = previousDistributionChanges
        }
    }

    @discardableResult
    private func commitAutomaticDistribution() -> Bool {
        if let transactionID = automaticDistributionChanges.first?.transactionID {
            guard persistSafely("自动分配", operation: {
                try storage.commitAutomaticDistribution(transactionID: transactionID)
            }, commit: {}, rollback: {}) else { return false }
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
        if let transactionID {
            if persistSync(kind: .undoAutomaticDistribution(transactionID: transactionID)) {
                automaticDistributionChanges = []
            }
        } else {
            if persistSync() {
                automaticDistributionChanges = []
            }
        }
    }

    private func automaticDistributionOverride(
        goalID: UUID,
        taskID: UUID
    ) -> PersistenceMutationKind? {
        let matches = automaticDistributionChanges.filter {
            $0.goalID == goalID && $0.taskID == taskID
        }
        guard let transactionID = matches.first?.transactionID else { return nil }
        return .manualOverride(taskID: taskID, transactionID: transactionID)
    }

    private func removeAutomaticDistributionChange(goalID: UUID, taskID: UUID) {
        automaticDistributionChanges.removeAll {
            $0.goalID == goalID && $0.taskID == taskID
        }
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

    private func shiftGoal(id: UUID, byDays dayOffset: Int, now: Date) {
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

    private func weekStart(containing date: Date) -> Date {
        let calendar = businessCalendar.calendar
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    private func placeGoal(_ movingGoalID: UUID, after anchorGoalID: UUID?) {
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

    private func copyGoal(
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
        let subgoalIDs = Dictionary(uniqueKeysWithValues: source.subgoals.map { ($0.id, UUID()) })
        let milestoneIDs = Dictionary(uniqueKeysWithValues: source.milestones.map { ($0.id, UUID()) })
        let visibleTasks = source.tasks.filter { !$0.isArchived && !$0.isDeleted }
        let taskIDs = Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, UUID()) })

        let copiedSubgoals = source.subgoals.map { subgoal in
            GoalSubgoal(
                id: subgoalIDs[subgoal.id] ?? UUID(),
                title: subgoal.title,
                detail: subgoal.detail,
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

    private func replace(_ goal: WeeklyGoal) { guard let index = goals.firstIndex(where: { $0.id == goal.id }) else { return }; goals[index] = goal }

    /// One-time migration (P2-1): ensures tasks derived from subgoals are
    /// consistent with the goal-as-source-of-truth model. After this migration
    /// runs once, projections are regenerated on-demand via `project()` and
    /// never need full-store synchronization again.
    @discardableResult
    private func synchronizeAllSubgoalTasksIfNeeded() -> Bool {
        let migrationKey = "weekflow.goals.projectionSync.v1"
        guard !legacyPreferences.bool(forKey: migrationKey) else { return false }
        let synchronizedGoals = goals.map(goalService.project)
        legacyPreferences.set(true, forKey: migrationKey)
        guard synchronizedGoals != goals else { return false }
        goals = synchronizedGoals
        return true
    }

    private func upsertDailyPlanningCutoffEvent(
        on date: Date,
        minutes: Int,
        persistImmediately: Bool = true
    ) -> UUID {
        let sourceKey = dailyPlanningCutoffSourceKey(for: date)
        let startDate = cutoffDate(on: date, minutes: minutes)
        if let index = calendarEvents.firstIndex(where: { $0.sourceKey == sourceKey }) {
            calendarEvents[index].title = "工作截止时间"
            calendarEvents[index].startDate = startDate
            calendarEvents[index].durationMinutes = 30
            calendarEvents[index].colorName = "purple"
            if persistImmediately { persistCalendarEvents() }
            return calendarEvents[index].id
        }

        let event = CalendarEvent(
            title: "工作截止时间",
            startDate: startDate,
            durationMinutes: 30,
            colorName: "purple",
            sourceKey: sourceKey
        )
        calendarEvents.append(event)
        if persistImmediately { persistCalendarEvents() }
        return event.id
    }

    /// P1-7 Fix: Delegate to PlanningService for consistent cutoff date calculation.
    private func cutoffDate(on date: Date, minutes: Int) -> Date {
        planningService.cutoffDate(on: date, minutes: minutes)
    }

    /// P1-7 Fix: Delegate to PlanningService for consistent source key format.
    private func dailyPlanningCutoffSourceKey(for date: Date) -> String {
        planningService.cutoffSourceKey(for: date)
    }

    @discardableResult
    private func migrateLegacyDailyPlanningCutoffIfNeeded() -> Bool {
        let key = "weekflow.dailyPlanning.shutdownHour"
        guard dailyPlanningStates.isEmpty,
              let legacyHour = legacyPreferences.object(forKey: key) as? Int,
              (17...23).contains(legacyHour),
              let tomorrow = businessCalendar.calendar.date(byAdding: .day, value: 1, to: .now) else { return false }
        dailyPlanningStates = [
            DailyPlanningState(date: tomorrow, cutoffMinutes: legacyHour * 60)
        ]
        legacyPreferences.removeObject(forKey: key)
        return true
    }

    @discardableResult
    private func migrateLegacyDailySummaryIfNeeded() -> Bool {
        let summaryKey = "weekflow.dailyShutdownSummary"
        let dateKey = "weekflow.dailyShutdownSummaryDate"
        guard dailySummaries.isEmpty,
              let legacySummary = legacyPreferences.string(forKey: summaryKey),
              !legacySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        dailySummaries = [DailySummary(date: businessCalendar.calendar.startOfDay(for: .now), content: legacySummary)]
        legacyPreferences.removeObject(forKey: summaryKey)
        legacyPreferences.removeObject(forKey: dateKey)
        return true
    }

    private func manualChangeRecords(from original: WeekTask, to updated: WeekTask, date: Date) -> [TaskChangeRecord] {
        var records: [TaskChangeRecord] = []
        func record(_ field: String, _ oldValue: String, _ newValue: String) {
            guard oldValue != newValue else { return }
            records.append(TaskChangeRecord(date: date, field: field, oldValue: oldValue, newValue: newValue, source: .manual))
        }
        func dateText(_ value: Date?) -> String {
            value?.formatted(.dateTime.year().month().day().hour().minute()) ?? "未设置"
        }

        record("标题", original.title, updated.title)
        record("说明", original.description, updated.description)
        record("备注", original.notes, updated.notes)
        record("分类", channel(for: original.channelID)?.title ?? "未分类", channel(for: updated.channelID)?.title ?? "未分类")
        record("优先级", original.priority.label, updated.priority.label)
        record("安排日期", dateText(original.plannedDate), dateText(updated.plannedDate))
        record("截止日期", dateText(original.dueDate), dateText(updated.dueDate))
        record("开始时间", dateText(original.startTime), dateText(updated.startTime))
        record("预计时间", original.estimatedMinutes.hourMinuteClockText, updated.estimatedMinutes.hourMinuteClockText)
        record("实际时间", original.actualMinutes.hourMinuteClockText, updated.actualMinutes.hourMinuteClockText)
        record("重复", original.recurringRule?.frequency.label ?? "不重复", updated.recurringRule?.frequency.label ?? "不重复")
        record("完成状态", original.status.rawValue, updated.status.rawValue)
        func subtaskText(_ subtasks: [TaskSubtask]) -> String {
            subtasks.map {
                "\($0.completed ? "已完成" : "未完成"):\($0.title):\($0.actualMinutes ?? 0):\($0.plannedMinutes ?? 0)"
            }.joined(separator: "|")
        }
        record("子任务", subtaskText(original.subtasks), subtaskText(updated.subtasks))
        return records
    }

    @discardableResult
    private func updateTask(
        goalID: UUID,
        taskID: UUID,
        persistImmediately: Bool = true,
        persistenceKind: PersistenceMutationKind = .userEdit,
        change: (inout WeekTask) -> Void
    ) -> Bool {
        guard var goal = goals.first(where: { $0.id == goalID }), let index = goal.tasks.firstIndex(where: { $0.id == taskID }) else { return false }
        change(&goal.tasks[index])
        if goal.tasks[index].startTime == nil {
            goal.tasks[index].calendarPlacement = .suggested
        }
        goal.tasks[index].updatedAt = .now
        goal = goalService.applyPrimaryProjectionEdit(goal)
        replace(goal)
        if persistImmediately { persist(kind: persistenceKind) }
        return true
    }

    private func reorderTasksByPriority(
        on date: Date,
        promotedTask: TaskReference? = nil
    ) {
        let currentEntries = tasks(on: date)
        let currentPositions = Dictionary(uniqueKeysWithValues: currentEntries.enumerated().map { index, entry in
            (TaskReference(goalID: entry.goal.id, taskID: entry.task.id), index)
        })
        let orderedEntries: [(goal: WeeklyGoal, task: WeekTask)]
        if let promotedTask,
           let promotedEntry = currentEntries.first(where: {
               TaskReference(goalID: $0.goal.id, taskID: $0.task.id) == promotedTask
           }) {
            var remainingEntries = currentEntries.filter {
                TaskReference(goalID: $0.goal.id, taskID: $0.task.id) != promotedTask
            }
            let insertionIndex = remainingEntries.lastIndex(where: {
                $0.task.priority.sortRank < promotedEntry.task.priority.sortRank
            }).map { $0 + 1 } ?? 0
            remainingEntries.insert(promotedEntry, at: insertionIndex)
            orderedEntries = remainingEntries
        } else {
            orderedEntries = currentEntries.sorted { first, second in
                if first.task.priority.sortRank != second.task.priority.sortRank {
                    return first.task.priority.sortRank < second.task.priority.sortRank
                }

                let firstReference = TaskReference(goalID: first.goal.id, taskID: first.task.id)
                let secondReference = TaskReference(goalID: second.goal.id, taskID: second.task.id)
                return (currentPositions[firstReference] ?? .max) < (currentPositions[secondReference] ?? .max)
            }
        }

        applyTaskOrder(orderedEntries)
    }

    private func applyTaskOrder(_ orderedEntries: [(goal: WeeklyGoal, task: WeekTask)]) {
        for (sortOrder, entry) in orderedEntries.enumerated() {
            guard let goalIndex = goals.firstIndex(where: { $0.id == entry.goal.id }),
                  let taskIndex = goals[goalIndex].tasks.firstIndex(where: { $0.id == entry.task.id }) else { continue }
            goals[goalIndex].tasks[taskIndex].sortOrder = sortOrder
        }
    }
    private func task(goalID: UUID, taskID: UUID) -> WeekTask? { goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID }) }
    /// Non-blocking persist for interactive edits (P1-7). The diff is computed
    /// on the MainActor (fast in-memory scan of value types) and disk I/O is
    /// suspended via the PersistenceActor so the run loop stays responsive.
    /// In test mode (`synchronousPersistence == true`) this delegates to
    /// `persistSync` so assertions can read back from disk immediately.
    ///
    /// P0-2 Fix: Uses PersistenceCoordinator to serialize writes and prevent
    /// out-of-order commits and stale rollbacks.
    private func persist(kind: PersistenceMutationKind = .userEdit) {
        if synchronousPersistence {
            _ = persistSync(kind: kind)
            return
        }
        let changes = PersistenceGoalChangeSet.difference(
            before: persistedGoals,
            after: goals
        )
        guard !changes.isEmpty else { return }
        let snapshot = persistedGoals
        let currentGoals = goals
        // Use coordinator to serialize writes (P0-2 fix)
        Task {
            await persistenceCoordinator.enqueue(
                label: "周目标与任务",
                operation: { try await self.storage.applyGoalChangesAsync(changes, kind: kind) },
                commit: { self.persistedGoals = currentGoals },
                rollback: { self.goals = snapshot }
            )
        }
    }

    /// Synchronous persist – blocks the calling thread. Use ONLY when the
    /// return value is needed (automatic distribution rollback) or during
    /// startup/tests where blocking is acceptable.
    @discardableResult
    private func persistSync(kind: PersistenceMutationKind = .userEdit) -> Bool {
        let changes = PersistenceGoalChangeSet.difference(
            before: persistedGoals,
            after: goals
        )
        guard !changes.isEmpty else { return true }
        return persistSafely(
            "周目标与任务",
            operation: { try storage.applyGoalChanges(changes, kind: kind) },
            commit: { persistedGoals = goals },
            rollback: { goals = persistedGoals }
        )
    }

    /// Single-transaction startup persist. All startup migrations and
    /// synchronization are committed atomically so a crash during startup
    /// cannot leave partially committed state (P1-3 requirement).
    private func persistStartup() {
        let snapshot = WeekflowPersistenceSnapshot(
            goals: goals,
            channels: channels,
            calendarEvents: calendarEvents,
            dailyPlanningStates: dailyPlanningStates,
            focusRecords: focusRecords,
            dailySummaries: dailySummaries
        )
        persistSafely(
            "启动同步",
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
                channels = persistedChannels
                calendarEvents = persistedCalendarEvents
                dailyPlanningStates = persistedDailyPlanningStates
                focusRecords = persistedFocusRecords
                dailySummaries = persistedDailySummaries
            }
        )
    }

    private func persistChannels() {
        persistSafely(
            "频道",
            operation: { try storage.saveChannels(channels) },
            commit: { persistedChannels = channels },
            rollback: { channels = persistedChannels }
        )
    }

    private func persistCalendarEvents() {
        persistSafely(
            "日历事件",
            operation: { try storage.saveCalendarEvents(calendarEvents) },
            commit: { persistedCalendarEvents = calendarEvents },
            rollback: { calendarEvents = persistedCalendarEvents }
        )
    }

    private func persistDailyPlanningStates() {
        persistSafely(
            "每日计划",
            operation: { try storage.saveDailyPlanningStates(dailyPlanningStates) },
            commit: { persistedDailyPlanningStates = dailyPlanningStates },
            rollback: { dailyPlanningStates = persistedDailyPlanningStates }
        )
    }

    private func persistDailyPlanAndCalendarEvents() {
        persistSafely(
            "每日计划与日历事件",
            operation: {
                try storage.saveDailyPlanAndCalendarEvents(
                    states: dailyPlanningStates,
                    events: calendarEvents
                )
            },
            commit: {
                persistedDailyPlanningStates = dailyPlanningStates
                persistedCalendarEvents = calendarEvents
            },
            rollback: {
                dailyPlanningStates = persistedDailyPlanningStates
                calendarEvents = persistedCalendarEvents
            }
        )
    }

    private func persistFocusRecords() {
        if synchronousPersistence {
            persistSafely(
                "专注记录",
                operation: { try storage.saveFocusRecords(focusRecords) },
                commit: { persistedFocusRecords = focusRecords },
                rollback: { focusRecords = persistedFocusRecords }
            )
            return
        }
        // Non-blocking: focus records are append-only and don't need sync
        // confirmation for interactive responsiveness (P1-7).
        persistFocusRecordsAsync()
    }

    private func persistDailySummaries() {
        persistSafely(
            "每日总结",
            operation: { try storage.saveDailySummaries(dailySummaries) },
            commit: { persistedDailySummaries = dailySummaries },
            rollback: { dailySummaries = persistedDailySummaries }
        )
    }

    private func persistActiveTaskTimer() {
        let session = activeTaskTimer
        _ = persistSafely(
            "活动计时",
            operation: { try storage.saveActiveTimerSession(session) },
            commit: {},
            rollback: {
                if session != nil { activeTaskTimer = nil }
            }
        )
    }

    private func persistTaskAndActiveTimer(rollbackSession: TaskTimerSession?) {
        let changes = PersistenceGoalChangeSet.difference(
            before: persistedGoals,
            after: goals
        )
        let session = activeTaskTimer
        _ = persistSafely(
            "任务与活动计时",
            operation: {
                try storage.saveGoalChangesAndActiveTimer(
                    changes: changes,
                    session: session
                )
            },
            commit: { persistedGoals = goals },
            rollback: {
                goals = persistedGoals
                taskTimerService.restore(session: rollbackSession)
            }
        )
    }

    @discardableResult
    private func persistSafely(
        _ label: String,
        operation: () throws -> Void,
        commit: () -> Void,
        rollback: () -> Void
    ) -> Bool {
        // Regression fixtures intentionally run without disk writes, but their
        // in-memory command semantics should remain identical to production.
        guard persistenceEnabled else {
            if developmentFixture != nil { return true }
            rollback()
            return false
        }
        do {
            try operation()
            commit()
            return true
        } catch {
            rollback()
            persistenceEnabled = false
            persistenceIssue = "\(label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Async persistence (non-blocking on MainActor)

    /// Async variant of `persistSafely`. Suspends the calling task during disk
    /// I/O so the main thread remains responsive (satisfies P1-7 requirement).
    @discardableResult
    private func persistSafelyAsync(
        _ label: String,
        operation: @Sendable () async throws -> Void,
        commit: @MainActor () -> Void,
        rollback: @MainActor () -> Void
    ) async -> Bool {
        guard persistenceEnabled else {
            if developmentFixture != nil { return true }
            rollback()
            return false
        }
        do {
            try await operation()
            commit()
            return true
        } catch {
            rollback()
            persistenceEnabled = false
            persistenceIssue = "\(label)保存失败，本次会话已暂停后续保存。原有本地文件不会被主动删除。\n\n\(error.localizedDescription)"
            return false
        }
    }

    private func persistFocusRecordsAsync() {
        let records = focusRecords
        let snapshot = persistedFocusRecords
        // Use coordinator to serialize writes (P0-2 fix)
        Task {
            await persistenceCoordinator.enqueue(
                label: "专注记录",
                operation: { try await self.storage.saveFocusRecordsAsync(records) },
                commit: { self.persistedFocusRecords = records },
                rollback: { self.focusRecords = snapshot }
            )
        }
    }
}

struct TaskReference: Identifiable, Hashable {
    let goalID: UUID
    let taskID: UUID
    var id: UUID { taskID }
}
