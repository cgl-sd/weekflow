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
    var id = UUID()
    var date: Date
    var reason: CompletionCreditReason
    var minutes: Int?
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
    var plannedDate: Date?
    /// Weekly task-pool sources can be referenced by multiple daily plans
    /// without being removed from the pool.
    var assignedDates: [Date]
    var startTime: Date?
    var calendarPlacement: TaskCalendarPlacement
    var dueDate: Date?
    /// Monday of a target execution week when the exact day is intentionally undecided.
    var executionWeekStart: Date?
    var estimatedMinutes: Int
    var actualMinutes: Int
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
        self.plannedDate = plannedDate
        self.assignedDates = assignedDates
        self.startTime = startTime
        self.calendarPlacement = calendarPlacement
        self.dueDate = dueDate
        self.executionWeekStart = executionWeekStart
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
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
        case id, title, plannedDate, assignedDates, startTime, calendarPlacement, dueDate, executionWeekStart, estimatedMinutes, actualMinutes, status, archivedAt, notes, description, milestoneID, parentTaskID, subgoalID, channelID, contextID, priority, sourceType, sourceURL, links, comments, changeRecords, subtasks, recurringRule, recurrenceRootID, rolloverCount, completionCredits, createdAt, updatedAt, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        plannedDate = try container.decodeIfPresent(Date.self, forKey: .plannedDate)
        assignedDates = try container.decodeIfPresent([Date].self, forKey: .assignedDates) ?? []
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime)
        calendarPlacement = try container.decodeIfPresent(
            TaskCalendarPlacement.self,
            forKey: .calendarPlacement
        ) ?? .suggested
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        executionWeekStart = try container.decodeIfPresent(Date.self, forKey: .executionWeekStart)
        estimatedMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 60
        actualMinutes = try container.decodeIfPresent(Int.self, forKey: .actualMinutes) ?? 0
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

    var isOverdue: Bool {
        guard status != .completed && !isArchived && !isDeleted,
              let dueDate else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isUnassigned: Bool {
        plannedDate == nil && !isArchived && !isDeleted
    }

    func isAssigned(on date: Date, calendar: Calendar = .current) -> Bool {
        assignedDates.contains { calendar.isDate($0, inSameDayAs: date) }
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
    var id = UUID()
    var title: String
    var date: Date
    var type: MilestoneType = .meeting
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
    var startDate: Date
    var endDate: Date
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
    var sortOrder: Int

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
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.outcome = outcome
        self.startDate = startDate
        self.endDate = endDate
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
        self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, outcome, startDate, endDate, channelID, subgoals, carriedFromGoalID, tasks, milestones, archivedAt, deletedAt, isPinned, completedAt, primaryTaskID, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        outcome = try container.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate) ?? .now
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate) ?? startDate
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
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}
