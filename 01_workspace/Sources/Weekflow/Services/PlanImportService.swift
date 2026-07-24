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

        var errorDescription: String? {
            switch self {
            case .invalidFormat(let detail): "JSON 格式无效：\(detail)"
            case .dateParseFailed(let value): "日期解析失败：\(value)"
            case .noGoals: "JSON 中没有包含任何目标"
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

    /// Parses raw JSON data into a structured payload.
    static func parse(data: Data) -> Result<PlanImportPayload, PlanImportError> {
        do {
            let payload = try JSONDecoder().decode(PlanImportPayload.self, from: data)
            guard !payload.goals.isEmpty else { return .failure(.noGoals) }
            guard parseDate(payload.startDate) != nil else {
                return .failure(.dateParseFailed(payload.startDate))
            }
            guard parseDate(payload.endDate) != nil else {
                return .failure(.dateParseFailed(payload.endDate))
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

        // Archive existing plan if requested
        if archiveExisting, let existing = store.activePlan {
            store.archivePlan(id: existing.id)
        }

        let planTitle = payload.title ?? "导入规划"
        let planID = store.addPlan(title: planTitle, startDate: startDate, endDate: endDate)

        // Create goals under this plan
        for goalPayload in payload.goals {
            let goalID = store.addGoal(
                title: goalPayload.title,
                outcome: goalPayload.outcome ?? "",
                startDate: startDate,
                endDate: endDate,
                persistImmediately: false
            )
            // Associate goal with plan
            if let goalIndex = store.goals.firstIndex(where: { $0.id == goalID }) {
                store.goals[goalIndex].planID = planID
            }

            // Add subgoals
            if let subgoalTitles = goalPayload.subgoals {
                for title in subgoalTitles {
                    store.addSubgoal(to: goalID, title: title)
                }
            }

            // Add tasks
            if let tasks = goalPayload.tasks {
                for taskPayload in tasks {
                    let plannedDate = taskPayload.day.flatMap { parseShortDate($0, in: startDate) }
                    _ = store.addTask(
                        to: goalID,
                        title: taskPayload.title,
                        plannedDate: plannedDate,
                        dueDate: nil,
                        minutes: taskPayload.minutes ?? 60,
                        notes: "",
                        milestoneID: nil,
                        priority: .none
                    )
                }
            }
        }
        store.persist()
        return planID
    }

    private static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
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
