import Foundation

struct WeekflowDataArchive: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let goals: [WeeklyGoal]
    let plans: [WeeklyPlan]
    let channels: [TaskChannel]
    let calendarEvents: [CalendarEvent]
    let dailyPlanningStates: [DailyPlanningState]
    let focusRecords: [FocusRecord]
    let dailySummaries: [DailySummary]
    let activeTimerSession: TaskTimerSession?

    init(snapshot: WeekflowPersistenceSnapshot, exportedAt: Date = .now) {
        formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        goals = snapshot.goals
        plans = snapshot.plans
        channels = snapshot.channels
        calendarEvents = snapshot.calendarEvents
        dailyPlanningStates = snapshot.dailyPlanningStates
        focusRecords = snapshot.focusRecords
        dailySummaries = snapshot.dailySummaries
        activeTimerSession = snapshot.activeTimerSession
    }

    var snapshot: WeekflowPersistenceSnapshot {
        WeekflowPersistenceSnapshot(
            goals: goals,
            plans: plans,
            channels: channels,
            calendarEvents: calendarEvents,
            dailyPlanningStates: dailyPlanningStates,
            focusRecords: focusRecords,
            dailySummaries: dailySummaries,
            activeTimerSession: activeTimerSession
        )
    }
}

struct FullDataArchiveService: Sendable {
    enum ArchiveError: LocalizedError {
        case invalidInputFile
        case oversizedFile(Int)
        case unsupportedFormat(Int)
        case excessiveRecordCount(String)
        case orphanedTimer

        var errorDescription: String? {
            switch self {
            case .invalidInputFile:
                "请选择一个本地普通 JSON 文件。"
            case let .oversizedFile(limit):
                "数据归档超过安全上限（\(limit / 1_048_576) MB）。"
            case let .unsupportedFormat(version):
                "不支持的数据归档版本：\(version)。"
            case let .excessiveRecordCount(name):
                "数据归档中的“\(name)”记录数超过安全上限。"
            case .orphanedTimer:
                "数据归档中的活动计时找不到对应任务。"
            }
        }
    }

    static let fileExtension = "weekflow.json"
    static let maximumFileBytes = 256 * 1_048_576
    static let maximumCollectionCount = 1_000_000

    func write(snapshot: WeekflowPersistenceSnapshot, to url: URL) throws {
        try validate(snapshot)
        let archive = WeekflowDataArchive(snapshot: snapshot)
        let data = try JSONEncoder.weekflow.encode(archive)
        guard data.count <= Self.maximumFileBytes else {
            throw ArchiveError.oversizedFile(Self.maximumFileBytes)
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    func read(from url: URL) throws -> WeekflowPersistenceSnapshot {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ArchiveError.invalidInputFile
        }
        let fileSize = values.fileSize ?? 0
        guard fileSize <= Self.maximumFileBytes else {
            throw ArchiveError.oversizedFile(Self.maximumFileBytes)
        }
        let archive = try JSONDecoder.weekflow.decode(
            WeekflowDataArchive.self,
            from: Data(contentsOf: url, options: .mappedIfSafe)
        )
        guard archive.formatVersion == WeekflowDataArchive.currentFormatVersion else {
            throw ArchiveError.unsupportedFormat(archive.formatVersion)
        }
        let snapshot = archive.snapshot
        try validate(snapshot)
        return snapshot
    }

    func validate(_ snapshot: WeekflowPersistenceSnapshot) throws {
        let collections: [(String, Int)] = [
            ("周目标", snapshot.goals.count),
            ("周规划", snapshot.plans.count),
            ("频道", snapshot.channels.count),
            ("日历事件", snapshot.calendarEvents.count),
            ("每日计划", snapshot.dailyPlanningStates.count),
            ("专注记录", snapshot.focusRecords.count),
            ("每日总结", snapshot.dailySummaries.count),
            ("任务", snapshot.goals.reduce(0) { $0 + $1.tasks.count })
        ]
        if let excessive = collections.first(where: { $0.1 > Self.maximumCollectionCount }) {
            throw ArchiveError.excessiveRecordCount(excessive.0)
        }

        try PersistenceIdentityValidator.validate(goals: snapshot.goals)
        try PersistenceIdentityValidator.validatePayloadIDs(snapshot.plans, entityType: "WeeklyPlan") {
            $0.id.uuidString
        }
        try PersistenceIdentityValidator.validatePayloadIDs(snapshot.channels, entityType: "TaskChannel", id: \.id)
        try PersistenceIdentityValidator.validatePayloadIDs(snapshot.calendarEvents, entityType: "CalendarEvent") {
            $0.id.uuidString
        }
        try PersistenceIdentityValidator.validatePayloadIDs(snapshot.dailyPlanningStates, entityType: "DailyPlanningState") {
            String(describing: $0.id)
        }
        try PersistenceIdentityValidator.validatePayloadIDs(snapshot.focusRecords, entityType: "FocusRecord") {
            $0.id.uuidString
        }
        try PersistenceIdentityValidator.validatePayloadIDs(snapshot.dailySummaries, entityType: "DailySummary") {
            String(describing: $0.id)
        }

        if let timer = snapshot.activeTimerSession {
            let exists = snapshot.goals.contains { goal in
                goal.id == timer.goalID && goal.tasks.contains(where: { $0.id == timer.taskID })
            }
            guard exists else { throw ArchiveError.orphanedTimer }
        }
    }
}
