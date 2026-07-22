import Foundation
import Observation

struct AutomaticDistributionChange: Equatable {
    let transactionID: UUID
    let goalID: WeeklyGoal.ID
    let taskID: WeekTask.ID
    let assignedDate: Date
}

@MainActor
@Observable
final class WeekflowStore {
    let goalService = GoalService()
    /// Task business logic service (P2-2 Store split). Handles task creation,
    /// mutation, and lifecycle rules independent of persistence and UI.
    let taskService: TaskService
    /// Archive/restore business logic service (P2-2 Store split). Handles
    /// lifecycle transitions for archive, trash, and restore operations.
    let archiveService: ArchiveService
    /// Daily planning business logic service (P2-2 Store split). Handles
    /// cutoff/start time management and task scheduling rules.
    let planningService: PlanningService
    /// P2-1: Feature-boundary coordinator for goal lifecycle operations.
    /// Owns archive/trash/restore/purge domain rules and navigation side-effects.
    let goalLifecycle: GoalLifecycleCoordinator
    /// P1-3 fix: encapsulates timer settlement domain logic (actual time
    /// computation, change records, completion credits).
    let timerCoordinator: TimerCoordinator
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
    var persistenceIssue: String?
    let storage: LocalStorage
    let developmentFixture: WeekflowDevelopmentFixture?
    var persistenceEnabled: Bool
    /// Coordinates async writes to prevent out-of-order commits (P0-2 fix).
    let persistenceCoordinator = PersistenceCoordinator()
    let legacyPreferences: UserDefaults
    let businessCalendar: any BusinessCalendarProviding
    var taskClipboard: (reference: TaskReference, cutsSource: Bool)?
    var goalClipboard: (goalID: UUID, cutsSource: Bool)?
    var automaticDistributionChanges: [AutomaticDistributionChange] = []
    var persistedGoals: [WeeklyGoal] = []
    var persistedChannels: [TaskChannel] = []
    var persistedCalendarEvents: [CalendarEvent] = []
    var persistedDailyPlanningStates: [DailyPlanningState] = []
    var persistedFocusRecords: [FocusRecord] = []
    var persistedDailySummaries: [DailySummary] = []
    /// Debouncer for text-input persistence. Rapid keystrokes coalesce into a
    /// single write after a 300 ms quiet period (P1-7 requirement).
    @ObservationIgnored let textInputDebouncer = PersistenceDebouncer()
    /// P2-7 fix: O(1) goal lookup index. Rebuilt lazily after any mutation to
    /// the goals array via `invalidateGoalIndex()`.
    @ObservationIgnored var goalIndexCache: [UUID: Int]?
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
        // P1-4 fix: share the same ArchiveService instance with the lifecycle
        // coordinator to express a single source of business rules.
        self.goalLifecycle = GoalLifecycleCoordinator(archiveService: archiveService)
        // P1-3 fix: timer settlement domain logic.
        self.timerCoordinator = TimerCoordinator(businessCalendar: businessCalendar)
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
            // P1-1: Eagerly normalize all persisted payloads to current format
            // so the database never contains mixed old/new encoding formats.
            normalizePersistedPayloadsIfNeeded()
            performDailyMaintenance()
            // Single consolidated startup persist – avoids multiple independent
            // save calls that could partially commit (P1-3 requirement).
            if needsPersist { persistStartup() }
        }
    }

    @discardableResult
    func migrateLegacyChannelPresentationIfNeeded() -> Bool {
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
        invalidateGoalIndex()
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

    var selectedGoal: WeeklyGoal? {
        selectedGoalID.flatMap { id in goalIndex(for: id).map { goals[$0] } }
    }
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


    func replace(_ goal: WeeklyGoal) {
        // P2-7: O(1) lookup via index cache. In-place replacement does not
        // change the ID→index mapping, so no invalidation is needed.
        guard let index = goalIndex(for: goal.id) else { return }
        goals[index] = goal
    }

    // MARK: - Goal Index (P2-7 fix)

    /// Invalidates the O(1) goal lookup cache. Call after any direct mutation
    /// of the `goals` array that does not go through `replace(_:)`.
    func invalidateGoalIndex() { goalIndexCache = nil }

    /// Returns the index of a goal by ID in O(1) amortized time.
    func goalIndex(for id: UUID) -> Int? {
        if let cache = goalIndexCache { return cache[id] }
        let cache = Dictionary(uniqueKeysWithValues: goals.enumerated().map { ($1.id, $0) })
        goalIndexCache = cache
        return cache[id]
    }

    /// One-time migration (P2-1): ensures tasks derived from subgoals are
    /// consistent with the goal-as-source-of-truth model. After this migration
    /// runs once, projections are regenerated on-demand via `project()` and
    /// never need full-store synchronization again.
    @discardableResult

    func manualChangeRecords(from original: WeekTask, to updated: WeekTask, date: Date) -> [TaskChangeRecord] {
        taskService.changeRecords(
            from: original,
            to: updated,
            date: date,
            channelTitle: { [weak self] id in self?.channel(for: id)?.title ?? "未分类" }
        )
    }

    @discardableResult
    func updateTask(
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

    func reorderTasksByPriority(
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

    func applyTaskOrder(_ orderedEntries: [(goal: WeeklyGoal, task: WeekTask)]) {
        for (sortOrder, entry) in orderedEntries.enumerated() {
            guard let goalIndex = goals.firstIndex(where: { $0.id == entry.goal.id }),
                  let taskIndex = goals[goalIndex].tasks.firstIndex(where: { $0.id == entry.task.id }) else { continue }
            goals[goalIndex].tasks[taskIndex].sortOrder = sortOrder
        }
    }
    func task(goalID: UUID, taskID: UUID) -> WeekTask? { goals.first(where: { $0.id == goalID })?.tasks.first(where: { $0.id == taskID }) }
    /// Non-blocking persist for interactive edits (P1-7). The diff is computed
    /// on the MainActor (fast in-memory scan of value types) and disk I/O is
    /// suspended via the PersistenceActor so the run loop stays responsive.
    /// In test mode (`synchronousPersistence == true`) this delegates to
    /// `persistSync` so assertions can read back from disk immediately.
    ///
    /// P0-2 Fix: Uses PersistenceCoordinator to serialize writes and prevent
    /// out-of-order commits and stale rollbacks.
}
