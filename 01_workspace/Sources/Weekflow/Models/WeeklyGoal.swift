import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case planned, inProgress, completed, archived, deleted
    var id: String { rawValue }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case none, must, should, later
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "普通"
        case .must: "紧急"
        case .should: "优先"
        case .later: "低优先级"
        }
    }

    static let displayOrder: [TaskPriority] = [.must, .should, .none, .later]

    var sortRank: Int {
        Self.displayOrder.firstIndex(of: self) ?? Self.displayOrder.count
    }

    func isHigher(than other: TaskPriority) -> Bool {
        sortRank < other.sortRank
    }
}

enum TaskSourceType: String, Codable, CaseIterable, Identifiable {
    case native, weeklyObjective, backlog, calendarEvent, url, integration
    var id: String { rawValue }

    var label: String {
        switch self {
        case .native: "本地任务"
        case .weeklyObjective: "周目标"
        case .backlog: "待办箱"
        case .calendarEvent: "日历事件"
        case .url: "链接"
        case .integration: "外部集成"
        }
    }
}

enum CompletionCreditReason: String, Codable {
    case subtaskCompleted, actualTimeLogged
}

struct CompletionCredit: Identifiable, Codable, Hashable {
    var id: UUID
    var day: LocalDay
    var reason: CompletionCreditReason
    var minutes: Int?
    var seconds: Int? = nil

    var date: Date {
        get { SystemBusinessCalendar.current.date(for: day) }
        set { day = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    init(
        id: UUID = UUID(),
        date: Date,
        reason: CompletionCreditReason,
        minutes: Int?,
        seconds: Int? = nil
    ) {
        self.id = id
        day = SystemBusinessCalendar.current.day(containing: date)
        self.reason = reason
        self.minutes = minutes
        self.seconds = seconds
    }

    private enum CodingKeys: String, CodingKey { case id, day, date, reason, minutes, seconds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let decodedDay = try container.decodeIfPresent(LocalDay.self, forKey: .day) {
            day = decodedDay
        } else {
            day = SystemBusinessCalendar.current.day(
                containing: try container.decode(Date.self, forKey: .date)
            )
        }
        reason = try container.decode(CompletionCreditReason.self, forKey: .reason)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        seconds = try container.decodeIfPresent(Int.self, forKey: .seconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(reason, forKey: .reason)
        try container.encodeIfPresent(minutes, forKey: .minutes)
        try container.encodeIfPresent(seconds, forKey: .seconds)
    }
}

struct TaskSubtask: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var completed = false
    var plannedMinutes: Int?
    var actualMinutes: Int?
    var completedAt: Date?
}

struct TaskLink: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var url: String
}

struct TaskComment: Identifiable, Codable, Hashable {
    var id = UUID()
    var body: String
    var createdAt = Date()
}

enum TaskChangeSource: String, Codable, Hashable {
    case manual
    case timer
}

struct TaskChangeRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var field: String
    var oldValue: String
    var newValue: String
    var source: TaskChangeSource
}

struct GoalSubgoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var detail = ""
    var channelID: String?
    var isCompleted = false
}

enum RecurringFrequency: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, monthly, custom
    var id: String { rawValue }
    var label: String {
        switch self { case .daily: "每天"; case .weekly: "每周"; case .monthly: "每月"; case .custom: "自定义" }
    }
}

struct RecurringRule: Codable, Hashable {
    var frequency: RecurringFrequency
    var interval = 1
}

struct TaskChannel: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var colorName: String
    var isPersonal = false
    var countsTowardWorkload = true
    var isDefault = false
    /// Optional values keep existing channel JSON backward compatible.
    var iconName: String? = nil
    var archivedAt: Date? = nil

    var resolvedIconName: String {
        iconName ?? (isPersonal ? "lock.fill" : "number")
    }

    static let defaults: [TaskChannel] = [
        .init(id: "work", title: "工作推进", colorName: "orange", isDefault: true, iconName: "briefcase"),
        .init(id: "presentations", title: "汇报材料", colorName: "purple", iconName: "doc.text"),
        .init(id: "research", title: "研究整理", colorName: "blue", iconName: "books.vertical"),
        .init(id: "study", title: "学习任务", colorName: "red", iconName: "graduationcap"),
        .init(id: "personal", title: "个人事务", colorName: "gray", isPersonal: true, countsTowardWorkload: false, iconName: "lock.fill"),
        .init(id: "leisure", title: "休闲安排", colorName: "purple", isPersonal: true, countsTowardWorkload: false, iconName: "star")
    ]
}

struct CalendarEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var startDate: Date
    var durationMinutes: Int
    var colorName = "gray"
    /// Stable application-owned identity. It is optional so existing local
    /// calendar event JSON remains decodable without migration loss.
    var sourceKey: String? = nil
}

enum TaskCalendarPlacement: String, Codable, Hashable {
    case suggested
    case committed
}

struct WeekTask: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    /// nil means the task still belongs to the weekly task pool / inbox.
    var plannedDay: LocalDay?
    /// Weekly task-pool sources can be referenced by multiple daily plans
    /// without being removed from the pool.
    var assignedDays: [LocalDay]
    var startLocalTime: LocalTime?
    /// Retains the civil day of an explicit time when a task is still in the
    /// weekly pool. Once planned, `plannedDay` is the authoritative anchor.
    var startTimeDay: LocalDay?
    var calendarPlacement: TaskCalendarPlacement
    var dueDay: LocalDay?
    /// Monday of a target execution week when the exact day is intentionally undecided.
    var executionWeekStartDay: LocalDay?
    var estimatedMinutes: Int
    /// P1-5 Fix: `actualMinutes` is now a computed property derived from
    /// `actualSeconds` (the single source of truth). Setting it updates
    /// `actualSeconds` accordingly.
    var actualMinutes: Int {
        get { DurationDisplay.minutes(for: actualSeconds) }
        set { actualSeconds = max(newValue, 0) * 60 }
    }
    /// Canonical accumulated duration in seconds. This is the single source
    /// of truth for task actual time.
    var actualSeconds: Int
    var status: TaskStatus
    /// Archiving is independent from completion so a completed task can retain
    /// its completion record while no longer appearing in active day lists.
    var archivedAt: Date?
    var notes: String
    var description: String
    var milestoneID: Milestone.ID?
    var parentTaskID: WeekTask.ID?
    var subgoalID: GoalSubgoal.ID?
    var channelID: String?
    var contextID: String?
    var priority: TaskPriority
    var sourceType: TaskSourceType
    var sourceURL: String?
    var links: [TaskLink]
    var comments: [TaskComment]
    var changeRecords: [TaskChangeRecord]
    var subtasks: [TaskSubtask]
    var recurringRule: RecurringRule?
    var recurrenceRootID: UUID?
    var rolloverCount: Int
    var completionCredits: [CompletionCredit]
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    var plannedDate: Date? {
        get { plannedDay.map(SystemBusinessCalendar.current.date(for:)) }
        set { plannedDay = newValue.map(SystemBusinessCalendar.current.day(containing:)) }
    }

    var assignedDates: [Date] {
        get { assignedDays.map(SystemBusinessCalendar.current.date(for:)) }
        set {
            assignedDays = Array(Set(newValue.map(SystemBusinessCalendar.current.day(containing:))))
                .sorted()
        }
    }

    var startTime: Date? {
        get {
            guard let startLocalTime else { return nil }
            let anchor = plannedDay ?? startTimeDay ?? SystemBusinessCalendar.current.day(containing: .now)
            return SystemBusinessCalendar.current.date(for: startLocalTime, on: anchor)
        }
        set {
            startLocalTime = newValue.map { LocalTime($0, calendar: SystemBusinessCalendar.current.calendar) }
            startTimeDay = newValue.map(SystemBusinessCalendar.current.day(containing:))
        }
    }

    var dueDate: Date? {
        get { dueDay.map(SystemBusinessCalendar.current.date(for:)) }
        set { dueDay = newValue.map(SystemBusinessCalendar.current.day(containing:)) }
    }

    var executionWeekStart: Date? {
        get { executionWeekStartDay.map(SystemBusinessCalendar.current.date(for:)) }
        set { executionWeekStartDay = newValue.map(SystemBusinessCalendar.current.day(containing:)) }
    }

    init(
        id: UUID = UUID(),
        title: String,
        plannedDate: Date? = nil,
        assignedDates: [Date] = [],
        startTime: Date? = nil,
        calendarPlacement: TaskCalendarPlacement = .suggested,
        dueDate: Date? = nil,
        executionWeekStart: Date? = nil,
        estimatedMinutes: Int,
        actualMinutes: Int = 0,
        actualSeconds: Int? = nil,
        status: TaskStatus = .planned,
        archivedAt: Date? = nil,
        notes: String = "",
        description: String = "",
        milestoneID: Milestone.ID? = nil,
        parentTaskID: WeekTask.ID? = nil,
        subgoalID: GoalSubgoal.ID? = nil,
        channelID: String? = nil,
        contextID: String? = nil,
        priority: TaskPriority = .none,
        sourceType: TaskSourceType = .native,
        sourceURL: String? = nil,
        links: [TaskLink] = [],
        comments: [TaskComment] = [],
        changeRecords: [TaskChangeRecord] = [],
        subtasks: [TaskSubtask] = [],
        recurringRule: RecurringRule? = nil,
        recurrenceRootID: UUID? = nil,
        rolloverCount: Int = 0,
        completionCredits: [CompletionCredit] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        plannedDay = plannedDate.map(SystemBusinessCalendar.current.day(containing:))
        assignedDays = Array(Set(assignedDates.map(SystemBusinessCalendar.current.day(containing:)))).sorted()
        startLocalTime = startTime.map { LocalTime($0, calendar: SystemBusinessCalendar.current.calendar) }
        startTimeDay = startTime.map(SystemBusinessCalendar.current.day(containing:))
        self.calendarPlacement = calendarPlacement
        dueDay = dueDate.map(SystemBusinessCalendar.current.day(containing:))
        executionWeekStartDay = executionWeekStart.map(SystemBusinessCalendar.current.day(containing:))
        self.estimatedMinutes = estimatedMinutes
        // P1-5 Fix: Initialize actualSeconds first (single source of truth).
        // actualMinutes is now a computed property.
        self.actualSeconds = max(actualSeconds ?? actualMinutes * 60, 0)
        self.status = status
        self.archivedAt = archivedAt
        self.notes = notes
        self.description = description
        self.milestoneID = milestoneID
        self.parentTaskID = parentTaskID
        self.subgoalID = subgoalID
        self.channelID = channelID
        self.contextID = contextID
        self.priority = priority
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.links = links
        self.comments = comments
        self.changeRecords = changeRecords
        self.subtasks = subtasks
        self.recurringRule = recurringRule
        self.recurrenceRootID = recurrenceRootID
        self.rolloverCount = rolloverCount
        self.completionCredits = completionCredits
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, plannedDay, plannedDate, assignedDays, assignedDates, startLocalTime, startTimeDay, startTime, calendarPlacement, dueDay, dueDate, executionWeekStartDay, executionWeekStart, estimatedMinutes, actualMinutes, actualSeconds, status, archivedAt, notes, description, milestoneID, parentTaskID, subgoalID, channelID, contextID, priority, sourceType, sourceURL, links, comments, changeRecords, subtasks, recurringRule, recurrenceRootID, rolloverCount, completionCredits, createdAt, updatedAt, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        plannedDay = try container.decodeIfPresent(LocalDay.self, forKey: .plannedDay)
            ?? container.decodeIfPresent(Date.self, forKey: .plannedDate)
                .map(SystemBusinessCalendar.current.day(containing:))
        assignedDays = try container.decodeIfPresent([LocalDay].self, forKey: .assignedDays)
            ?? container.decodeIfPresent([Date].self, forKey: .assignedDates)?
                .map(SystemBusinessCalendar.current.day(containing:))
            ?? []
        let legacyStartTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        startLocalTime = try container.decodeIfPresent(LocalTime.self, forKey: .startLocalTime)
            ?? legacyStartTime.map { LocalTime($0, calendar: SystemBusinessCalendar.current.calendar) }
        startTimeDay = try container.decodeIfPresent(LocalDay.self, forKey: .startTimeDay)
            ?? legacyStartTime.map(SystemBusinessCalendar.current.day(containing:))
        calendarPlacement = try container.decodeIfPresent(
            TaskCalendarPlacement.self,
            forKey: .calendarPlacement
        ) ?? .suggested
        dueDay = try container.decodeIfPresent(LocalDay.self, forKey: .dueDay)
            ?? container.decodeIfPresent(Date.self, forKey: .dueDate)
                .map(SystemBusinessCalendar.current.day(containing:))
        executionWeekStartDay = try container.decodeIfPresent(LocalDay.self, forKey: .executionWeekStartDay)
            ?? container.decodeIfPresent(Date.self, forKey: .executionWeekStart)
                .map(SystemBusinessCalendar.current.day(containing:))
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 60
        // P1-5 Fix: actualSeconds is the single source of truth.
        // Migrate from actualMinutes if actualSeconds is not present.
        let decodedActualMinutes = try container.decodeIfPresent(Int.self, forKey: .actualMinutes) ?? 0
        actualSeconds = try container.decodeIfPresent(Int.self, forKey: .actualSeconds)
            ?? decodedActualMinutes * 60
        status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .planned
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? notes
        milestoneID = try container.decodeIfPresent(UUID.self, forKey: .milestoneID)
        parentTaskID = try container.decodeIfPresent(UUID.self, forKey: .parentTaskID)
        subgoalID = try container.decodeIfPresent(UUID.self, forKey: .subgoalID)
        channelID = try container.decodeIfPresent(String.self, forKey: .channelID)
        contextID = try container.decodeIfPresent(String.self, forKey: .contextID)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .none
        sourceType = try container.decodeIfPresent(TaskSourceType.self, forKey: .sourceType) ?? .native
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        links = try container.decodeIfPresent([TaskLink].self, forKey: .links) ?? []
        comments = try container.decodeIfPresent([TaskComment].self, forKey: .comments) ?? []
        changeRecords = try container.decodeIfPresent([TaskChangeRecord].self, forKey: .changeRecords) ?? []
        subtasks = try container.decodeIfPresent([TaskSubtask].self, forKey: .subtasks) ?? []
        recurringRule = try container.decodeIfPresent(RecurringRule.self, forKey: .recurringRule)
        recurrenceRootID = try container.decodeIfPresent(UUID.self, forKey: .recurrenceRootID)
        rolloverCount = try container.decodeIfPresent(Int.self, forKey: .rolloverCount) ?? 0
        completionCredits = try container.decodeIfPresent([CompletionCredit].self, forKey: .completionCredits) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(plannedDay, forKey: .plannedDay)
        try container.encode(assignedDays, forKey: .assignedDays)
        try container.encodeIfPresent(startLocalTime, forKey: .startLocalTime)
        try container.encodeIfPresent(startTimeDay, forKey: .startTimeDay)
        try container.encode(calendarPlacement, forKey: .calendarPlacement)
        try container.encodeIfPresent(dueDay, forKey: .dueDay)
        try container.encodeIfPresent(executionWeekStartDay, forKey: .executionWeekStartDay)
        try container.encode(estimatedMinutes, forKey: .estimatedMinutes)
        // P2-10 fix: only encode actualSeconds (the single source of truth).
        // actualMinutes is a derived computed property; encoding both inflated
        // every task payload by ~20 bytes. The decoder already migrates from
        // actualMinutes when actualSeconds is absent.
        try container.encode(actualSeconds, forKey: .actualSeconds)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encode(notes, forKey: .notes)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(milestoneID, forKey: .milestoneID)
        try container.encodeIfPresent(parentTaskID, forKey: .parentTaskID)
        try container.encodeIfPresent(subgoalID, forKey: .subgoalID)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encodeIfPresent(contextID, forKey: .contextID)
        try container.encode(priority, forKey: .priority)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encode(links, forKey: .links)
        try container.encode(comments, forKey: .comments)
        try container.encode(changeRecords, forKey: .changeRecords)
        try container.encode(subtasks, forKey: .subtasks)
        try container.encodeIfPresent(recurringRule, forKey: .recurringRule)
        try container.encodeIfPresent(recurrenceRootID, forKey: .recurrenceRootID)
        try container.encode(rolloverCount, forKey: .rolloverCount)
        try container.encode(completionCredits, forKey: .completionCredits)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(sortOrder, forKey: .sortOrder)
    }

    var isOverdue: Bool {
        guard status != .completed && !isArchived && !isDeleted,
              let dueDay else { return false }
        return dueDay < SystemBusinessCalendar.current.day(containing: .now)
    }

    var isUnassigned: Bool {
        plannedDay == nil && !isArchived && !isDeleted
    }

    /// P1-4 fix: default to the shared business calendar instead of a raw
    /// `.current`, so this check honours the same calendar (and test override)
    /// used everywhere else rather than bypassing `BusinessCalendar`.
    func isAssigned(on date: Date, calendar: Calendar = SystemBusinessCalendar.current.calendar) -> Bool {
        assignedDays.contains(LocalDay(date, calendar: calendar))
    }
    var hasCompletionCredit: Bool { !completionCredits.isEmpty }
    var isArchived: Bool { archivedAt != nil || status == .archived }
    var isDeleted: Bool { status == .deleted }
}

extension WeekTask {
    var hasExecutionProgress: Bool {
        status == .completed || actualMinutes > 0 || subtasks.contains(where: \.completed)
    }
}

struct Milestone: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var day: LocalDay
    var type: MilestoneType = .meeting

    var date: Date {
        get { SystemBusinessCalendar.current.date(for: day) }
        set { day = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    init(id: UUID = UUID(), title: String, date: Date, type: MilestoneType = .meeting) {
        self.id = id
        self.title = title
        day = SystemBusinessCalendar.current.day(containing: date)
        self.type = type
    }

    private enum CodingKeys: String, CodingKey { case id, title, day, date, type }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        day = try container.decodeIfPresent(LocalDay.self, forKey: .day)
            ?? SystemBusinessCalendar.current.day(containing: container.decode(Date.self, forKey: .date))
        type = try container.decodeIfPresent(MilestoneType.self, forKey: .type) ?? .meeting
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(day, forKey: .day)
        try container.encode(type, forKey: .type)
    }
}

enum MilestoneType: String, Codable, CaseIterable, Identifiable {
    case meeting, checkpoint, delivery
    var id: String { rawValue }
    var label: String {
        switch self { case .meeting: "会议"; case .checkpoint: "检查点"; case .delivery: "交付" }
    }
    var symbol: String {
        switch self { case .meeting: "person.2"; case .checkpoint: "flag"; case .delivery: "shippingbox" }
    }

    var calendarColor: String {
        switch self { case .meeting: "blue"; case .checkpoint: "orange"; case .delivery: "purple" }
    }
}

struct WeeklyGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var outcome: String
    var startDay: LocalDay
    var endDay: LocalDay
    var channelID: String?
    var subgoals: [GoalSubgoal] = []
    var carriedFromGoalID: UUID?
    var tasks: [WeekTask] = []
    var milestones: [Milestone] = []
    var archivedAt: Date?
    /// Soft deletion is separate from archiving so goals remain recoverable.
    var deletedAt: Date?
    var isPinned: Bool = false
    var completedAt: Date?
    /// New flat weekly goals own one pool task without requiring a subgoal.
    var primaryTaskID: WeekTask.ID?
    /// Associates this goal with a planning period. Nil for legacy/standalone goals.
    var planID: UUID?
    var sortOrder: Int

    var startDate: Date {
        get { SystemBusinessCalendar.current.date(for: startDay) }
        set { startDay = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    var endDate: Date {
        get { SystemBusinessCalendar.current.date(for: endDay) }
        set { endDay = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    private var visibleTasks: [WeekTask] {
        tasks.filter { !$0.isArchived && !$0.isDeleted }
    }
    var completedTaskCount: Int { visibleTasks.filter { $0.status == .completed }.count }
    var progress: Double {
        if completedAt != nil { return 1 }
        guard !subgoals.isEmpty else { return 0 }
        return Double(subgoals.filter(\.isCompleted).count) / Double(subgoals.count)
    }
    var overdueTasks: [WeekTask] { tasks.filter(\.isOverdue) }
    var plannedMinutes: Int {
        tasks
            .filter { !$0.isArchived && !$0.isDeleted }
            .reduce(0) { $0 + $1.estimatedMinutes }
    }
    var isArchived: Bool { archivedAt != nil }
    var isDeleted: Bool { deletedAt != nil }

    init(
        id: UUID = UUID(),
        title: String,
        outcome: String,
        startDate: Date,
        endDate: Date,
        channelID: String? = nil,
        subgoals: [GoalSubgoal] = [],
        carriedFromGoalID: UUID? = nil,
        tasks: [WeekTask] = [],
        milestones: [Milestone] = [],
        archivedAt: Date? = nil,
        deletedAt: Date? = nil,
        isPinned: Bool = false,
        completedAt: Date? = nil,
        primaryTaskID: WeekTask.ID? = nil,
        planID: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.outcome = outcome
        startDay = SystemBusinessCalendar.current.day(containing: startDate)
        endDay = SystemBusinessCalendar.current.day(containing: endDate)
        self.channelID = channelID
        self.subgoals = subgoals
        self.carriedFromGoalID = carriedFromGoalID
        self.tasks = tasks
        self.milestones = milestones
        self.archivedAt = archivedAt
        self.deletedAt = deletedAt
        self.isPinned = isPinned
        self.completedAt = completedAt
        self.primaryTaskID = primaryTaskID
        self.planID = planID
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, outcome, startDay, startDate, endDay, endDate, channelID, subgoals, carriedFromGoalID, tasks, milestones, archivedAt, deletedAt, isPinned, completedAt, primaryTaskID, planID, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        startDay = try container.decodeIfPresent(LocalDay.self, forKey: .startDay)
            ?? SystemBusinessCalendar.current.day(
                containing: container.decodeIfPresent(Date.self, forKey: .startDate) ?? .now
            )
        endDay = try container.decodeIfPresent(LocalDay.self, forKey: .endDay)
            ?? container.decodeIfPresent(Date.self, forKey: .endDate)
                .map(SystemBusinessCalendar.current.day(containing:))
            ?? startDay
        channelID = try container.decodeIfPresent(String.self, forKey: .channelID)
        subgoals = try container.decodeIfPresent([GoalSubgoal].self, forKey: .subgoals) ?? []
        carriedFromGoalID = try container.decodeIfPresent(UUID.self, forKey: .carriedFromGoalID)
        tasks = try container.decodeIfPresent([WeekTask].self, forKey: .tasks) ?? []
        milestones = try container.decodeIfPresent([Milestone].self, forKey: .milestones) ?? []
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        primaryTaskID = try container.decodeIfPresent(WeekTask.ID.self, forKey: .primaryTaskID)
        planID = try container.decodeIfPresent(UUID.self, forKey: .planID)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(startDay, forKey: .startDay)
        try container.encode(endDay, forKey: .endDay)
        try container.encodeIfPresent(channelID, forKey: .channelID)
        try container.encode(subgoals, forKey: .subgoals)
        try container.encodeIfPresent(carriedFromGoalID, forKey: .carriedFromGoalID)
        try container.encode(tasks, forKey: .tasks)
        try container.encode(milestones, forKey: .milestones)
        try container.encodeIfPresent(archivedAt, forKey: .archivedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encodeIfPresent(primaryTaskID, forKey: .primaryTaskID)
        try container.encodeIfPresent(planID, forKey: .planID)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}
