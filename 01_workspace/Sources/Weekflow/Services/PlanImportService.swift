import Foundation

/// Service for parsing and importing weekly plan JSON files.
/// JSON format:
/// {
///   "title": "第30周",
///   "startDate": "2026-07-22",
///   "endDate": "2026-07-25",
///   "goals": [
///     {
///       "title": "完成代码审查",
///       "outcome": "P0/P1归零",
///       "subgoals": ["审查A模块"],
///       "tasks": [{ "title": "修复A-2", "day": "07-22", "minutes": 60 }]
///     }
///   ]
/// }
struct PlanImportService {
    static let maximumFileSize = 2 * 1024 * 1024
    static let maximumGoalCount = 100
    static let maximumTaskCount = 5_000
    static let maximumTitleLength = 200
    static let maximumOutcomeLength = 2_000
    static let maximumTaskMinutes = 24 * 60

    struct PlanImportPayload: Codable {
        let title: String?
        let startDate: String
        let endDate: String
        let goals: [GoalPayload]

        struct GoalPayload: Codable {
            let title: String
            let outcome: String?
            let subgoals: [String]?
            let tasks: [TaskPayload]?

            struct TaskPayload: Codable {
                let title: String
                let day: String?
                let minutes: Int?
            }
        }
    }

    enum PlanImportError: LocalizedError {
        case invalidFormat(String)
        case dateParseFailed(String)
        case noGoals
        case invalidDateRange
        case limitExceeded(String)
        case invalidValue(String)
        case invalidFile(String)

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let detail): "JSON 格式无效：\(detail)"
            case .dateParseFailed(let value): "日期解析失败：\(value)"
            case .noGoals: "JSON 中没有包含任何目标"
            case .invalidDateRange: "开始日期不能晚于结束日期"
            case .limitExceeded(let detail): "导入内容超过限制：\(detail)"
            case .invalidValue(let detail): "导入内容无效：\(detail)"
            case .invalidFile(let detail): "导入文件无效：\(detail)"
            }
        }
    }

    enum DateConflict {
        case none
        case partialOverlap(planTitle: String)
        case fullOverlap(planTitle: String)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Rejects non-files and oversized input from metadata before mapping any
    /// bytes into the process. `parse(data:)` repeats the size check to protect
    /// against a file changing between preflight and read.
    static func readData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw PlanImportError.invalidFile("请选择普通 JSON 文件")
        }
        guard let fileSize = values.fileSize else {
            throw PlanImportError.invalidFile("无法确定文件大小")
        }
        guard fileSize <= maximumFileSize else {
            throw PlanImportError.limitExceeded("文件不能超过 2 MB")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count <= maximumFileSize else {
            throw PlanImportError.limitExceeded("文件不能超过 2 MB")
        }
        return data
    }

    /// Parses raw JSON data into a structured payload.
    static func parse(data: Data) -> Result<PlanImportPayload, PlanImportError> {
        guard data.count <= maximumFileSize else {
            return .failure(.limitExceeded("文件不能超过 2 MB"))
        }
        do {
            let payload = try JSONDecoder().decode(PlanImportPayload.self, from: data)
            guard !payload.goals.isEmpty else { return .failure(.noGoals) }
            guard let startDate = parseDate(payload.startDate) else {
                return .failure(.dateParseFailed(payload.startDate))
            }
            guard let endDate = parseDate(payload.endDate) else {
                return .failure(.dateParseFailed(payload.endDate))
            }
            guard startDate <= endDate else { return .failure(.invalidDateRange) }
            guard payload.goals.count <= maximumGoalCount else {
                return .failure(.limitExceeded("目标最多 \(maximumGoalCount) 个"))
            }
            let taskCount = payload.goals.reduce(0) { $0 + ($1.tasks?.count ?? 0) }
            guard taskCount <= maximumTaskCount else {
                return .failure(.limitExceeded("任务最多 \(maximumTaskCount) 个"))
            }
            if let title = payload.title,
               !isValidText(title, maximumLength: maximumTitleLength) {
                return .failure(.invalidValue("规划标题为空或过长"))
            }
            for goal in payload.goals {
                guard isValidText(goal.title, maximumLength: maximumTitleLength) else {
                    return .failure(.invalidValue("目标标题为空或过长"))
                }
                if let outcome = goal.outcome, outcome.count > maximumOutcomeLength {
                    return .failure(.invalidValue("目标结果描述过长"))
                }
                if let subgoals = goal.subgoals,
                   subgoals.contains(where: { !isValidText($0, maximumLength: maximumTitleLength) }) {
                    return .failure(.invalidValue("子目标标题为空或过长"))
                }
                for task in goal.tasks ?? [] {
                    guard isValidText(task.title, maximumLength: maximumTitleLength) else {
                        return .failure(.invalidValue("任务标题为空或过长"))
                    }
                    guard (1...maximumTaskMinutes).contains(task.minutes ?? 60) else {
                        return .failure(.invalidValue("任务时长必须在 1 到 \(maximumTaskMinutes) 分钟之间"))
                    }
                    if let day = task.day {
                        guard let taskDate = parseShortDate(day, in: startDate) else {
                            return .failure(.dateParseFailed(day))
                        }
                        guard taskDate >= startDate && taskDate <= endDate else {
                            return .failure(.invalidValue("任务日期 \(day) 不在规划日期范围内"))
                        }
                    }
                }
            }
            return .success(payload)
        } catch {
            return .failure(.invalidFormat(error.localizedDescription))
        }
    }

    /// Detects date conflicts between a new plan and existing active plans.
    static func detectConflict(
        startDate: Date,
        endDate: Date,
        activePlan: WeeklyPlan?
    ) -> DateConflict {
        guard let plan = activePlan else { return .none }
        let planStart = plan.startDate
        let planEnd = plan.endDate
        // No overlap
        if endDate < planStart || startDate > planEnd { return .none }
        // Full overlap (new covers old entirely)
        if startDate <= planStart && endDate >= planEnd {
            return .fullOverlap(planTitle: plan.title)
        }
        return .partialOverlap(planTitle: plan.title)
    }

    /// Imports a parsed payload into the store, creating a plan and goals.
    @MainActor
    static func importIntoStore(
        _ payload: PlanImportPayload,
        store: WeekflowStore,
        archiveExisting: Bool
    ) -> UUID? {
        guard let startDate = parseDate(payload.startDate),
              let endDate = parseDate(payload.endDate) else { return nil }

        // Build the complete in-memory result first. No persistence occurs until
        // the final application snapshot, so the import is one database transaction.
        if archiveExisting, let existing = store.activePlan {
            if let planIndex = store.plans.firstIndex(where: { $0.id == existing.id }) {
                store.plans[planIndex].archivedAt = .now
            }
            for goalIndex in store.goals.indices {
                let belongsToPlan = store.goals[goalIndex].planID == existing.id
                let isOrphan = store.goals[goalIndex].planID == nil
                if (belongsToPlan || isOrphan)
                    && store.goals[goalIndex].archivedAt == nil
                    && store.goals[goalIndex].deletedAt == nil {
                    store.goals[goalIndex].archivedAt = .now
                    if isOrphan { store.goals[goalIndex].planID = existing.id }
                }
            }
        }

        let plan = WeeklyPlan(
            title: trimmed(payload.title ?? "导入规划"),
            startDate: startDate,
            endDate: endDate,
            sortOrder: (store.plans.map(\.sortOrder).min() ?? 0) - 1
        )
        store.plans.insert(plan, at: 0)

        let importedGoals = payload.goals.enumerated().map { goalOffset, goalPayload in
            let tasks = (goalPayload.tasks ?? []).enumerated().map { taskOffset, taskPayload in
                WeekTask(
                    title: trimmed(taskPayload.title),
                    plannedDate: taskPayload.day.flatMap { parseShortDate($0, in: startDate) },
                    estimatedMinutes: taskPayload.minutes ?? 60,
                    sortOrder: taskOffset
                )
            }
            return WeeklyGoal(
                title: trimmed(goalPayload.title),
                outcome: trimmed(goalPayload.outcome ?? ""),
                startDate: startDate,
                endDate: endDate,
                subgoals: (goalPayload.subgoals ?? []).map { GoalSubgoal(title: trimmed($0)) },
                tasks: tasks,
                planID: plan.id,
                sortOrder: goalOffset
            )
        }
        store.goals.append(contentsOf: importedGoals)
        store.selectedGoalID = importedGoals.first?.id
        store.invalidateGoalIndex()
        store.persistenceCoordinator.cancelAllPending()
        store.persistStartup()
        return plan.id
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isValidText(_ value: String, maximumLength: Int) -> Bool {
        let value = trimmed(value)
        return !value.isEmpty && value.count <= maximumLength
    }

    /// Public accessor for date parsing (used by conflict detection in views).
    static func parseDatePublic(_ string: String) -> Date? {
        parseDate(string)
    }

    /// Parses "MM-dd" format relative to the plan's start year.
    private static func parseShortDate(_ string: String, in referenceDate: Date) -> Date? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: referenceDate)
        if let date = shortDateFormatter.date(from: string) {
            var components = calendar.dateComponents([.month, .day], from: date)
            components.year = year
            return calendar.date(from: components)
        }
        // Try full format as fallback
        return dateFormatter.date(from: string)
    }

    // MARK: - Export

    /// Exports a plan and its goals to JSON data matching the import format.
    static func exportPlan(_ plan: WeeklyPlan, goals: [WeeklyGoal]) -> Data? {
        let calendar = Calendar.current
        let goalsPayload: [[String: Any]] = goals.map { goal in
            var dict: [String: Any] = [
                "title": goal.title
            ]
            if !goal.outcome.isEmpty { dict["outcome"] = goal.outcome }
            if !goal.subgoals.isEmpty {
                dict["subgoals"] = goal.subgoals.map(\.title)
            }
            let tasks: [[String: Any]] = goal.tasks
                .filter { !$0.isDeleted && !$0.isArchived }
                .compactMap { task in
                    var t: [String: Any] = ["title": task.title]
                    if let planned = task.plannedDate {
                        t["day"] = String(format: "%02d-%02d",
                            calendar.component(.month, from: planned),
                            calendar.component(.day, from: planned))
                    }
                    if task.estimatedMinutes > 0 {
                        t["minutes"] = task.estimatedMinutes
                    }
                    return t
                }
            if !tasks.isEmpty { dict["tasks"] = tasks }
            return dict
        }

        let payload: [String: Any] = [
            "title": plan.title,
            "startDate": dateFormatter.string(from: plan.startDate),
            "endDate": dateFormatter.string(from: plan.endDate),
            "goals": goalsPayload
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
