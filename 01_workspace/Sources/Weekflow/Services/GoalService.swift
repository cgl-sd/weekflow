import Foundation

struct WeeklyPlanningProjection: Equatable, Identifiable {
    let id: UUID
    let title: String
    let outcome: String
    let items: [DailyTaskProjection]
}

struct DailyTaskProjection: Equatable, Identifiable {
    let id: UUID
    let goalID: UUID
    let title: String
    let detail: String
    let completed: Bool
    let plannedDay: LocalDay?
    let assignedDays: [LocalDay]
    let channelID: String?
}

struct ReviewProjection: Equatable {
    let goalID: UUID
    let completedItemCount: Int
    let totalItemCount: Int
    let actualSeconds: Int
}

protocol GoalServicing {
    func project(_ goal: WeeklyGoal, now: Date) -> WeeklyGoal
    func applyPrimaryProjectionEdit(_ goal: WeeklyGoal, now: Date) -> WeeklyGoal
    func weeklyPlanningProjection(_ goal: WeeklyGoal) -> WeeklyPlanningProjection
    func reviewProjection(_ goal: WeeklyGoal) -> ReviewProjection
}

extension GoalServicing {
    /// Convenience wrapper that projects using the current wall-clock time.
    /// The core `project(_:now:)` is pure; this is the only place that reads
    /// the clock (P1-6 fix).
    func project(_ goal: WeeklyGoal) -> WeeklyGoal { project(goal, now: .now) }
    func applyPrimaryProjectionEdit(_ goal: WeeklyGoal) -> WeeklyGoal {
        applyPrimaryProjectionEdit(goal, now: .now)
    }
}

/// Unidirectional projection architecture (P2-1):
///
/// ```
/// WeeklyGoal (source of truth)
///     ├── subgoals: [GoalSubgoal]  ← canonical business data
///     └── tasks: [WeekTask]        ← derived projection (read-only)
/// ```
///
/// - `project(_:now:)` regenerates tasks from subgoals. This is the ONLY
///   direction of data flow during normal operation.
/// - `applyPrimaryProjectionEdit(_:now:)` is an **input translation layer**,
///   not bidirectional sync. When the user edits via the primary-task editor,
///   the edit is translated once into the goal (source of truth), then all
///   projections are regenerated. The task array is never independently
///   mutated and synced back.
/// - Views consume `WeeklyPlanningProjection`, `DailyTaskProjection`, and
///   `ReviewProjection` — all derived from the goal, never mutating it.
///
/// P1-6 fixes:
/// - `project` is a pure function: the timestamp is injected via `now`, it
///   never reads `Date.now` internally.
/// - Subgoal `channelID` is preserved (no longer forcibly cleared); a subgoal
///   task inherits its own subgoal channel, falling back to the goal channel.
/// - Projection no longer resets an in-progress task back to `.planned`; it
///   only marks completion, preserving the existing execution status.
struct GoalService: GoalServicing {
    func primarySubtasks(
        for subgoals: [GoalSubgoal],
        preserving existingSubtasks: [TaskSubtask]
    ) -> [TaskSubtask] {
        subgoals.map { subgoal in
            var subtask = existingSubtasks.first(where: { $0.id == subgoal.id })
                ?? TaskSubtask(id: subgoal.id, title: subgoal.title)
            subtask.title = subgoal.title
            subtask.completed = subgoal.isCompleted
            subtask.completedAt = subgoal.isCompleted ? (subtask.completedAt ?? .now) : nil
            return subtask
        }
    }

    func project(_ source: WeeklyGoal, now: Date) -> WeeklyGoal {
        var goal = source
        // P1-6 fix: do NOT clear subgoal channelID. Each subgoal may carry its
        // own channel; clearing it permanently destroyed user data.

        if let primaryTaskID = goal.primaryTaskID,
           let taskIndex = goal.tasks.firstIndex(where: { $0.id == primaryTaskID }) {
            var task = goal.tasks[taskIndex]
            task.title = goal.title
            task.description = goal.outcome
            task.notes = goal.outcome
            task.dueDate = goal.endDate
            task.channelID = goal.channelID
            task.sourceType = .weeklyObjective
            task.status = goal.completedAt == nil ? task.status : .completed
            task.subtasks = primarySubtasks(for: goal.subgoals, preserving: task.subtasks)
            if task != goal.tasks[taskIndex] { task.updatedAt = now; goal.tasks[taskIndex] = task }
        }

        var seen = Set<GoalSubgoal.ID>()
        for taskIndex in goal.tasks.indices {
            guard let subgoalID = goal.tasks[taskIndex].subgoalID else { continue }
            guard goal.tasks[taskIndex].status != .deleted,
                  goal.tasks[taskIndex].status != .archived else { continue }
            guard seen.insert(subgoalID).inserted else {
                goal.tasks[taskIndex].status = .deleted
                goal.tasks[taskIndex].plannedDay = nil
                goal.tasks[taskIndex].assignedDays = []
                goal.tasks[taskIndex].startLocalTime = nil
                goal.tasks[taskIndex].updatedAt = now
                continue
            }
            guard let item = goal.subgoals.first(where: { $0.id == subgoalID }) else {
                if goal.tasks[taskIndex].sourceType == .weeklyObjective {
                    goal.tasks[taskIndex].status = .deleted
                    goal.tasks[taskIndex].plannedDay = nil
                    goal.tasks[taskIndex].assignedDays = []
                    goal.tasks[taskIndex].startLocalTime = nil
                    goal.tasks[taskIndex].updatedAt = now
                }
                continue
            }
            var task = goal.tasks[taskIndex]
            task.title = item.title
            task.description = item.detail
            task.notes = item.detail
            task.dueDate = goal.endDate
            // P1-6 fix: prefer the subgoal's own channel, fall back to goal.
            task.channelID = item.channelID ?? goal.channelID
            task.sourceType = .weeklyObjective
            // P1-6 fix: only reflect completion; preserve in-progress/other
            // execution status instead of resetting to `.planned`.
            task.status = item.isCompleted ? .completed : task.status
            if task != goal.tasks[taskIndex] { task.updatedAt = now; goal.tasks[taskIndex] = task }
        }

        var nextOrder = (goal.tasks.map(\.sortOrder).max() ?? -1) + 1
        for item in goal.subgoals where !goal.tasks.contains(where: {
            $0.subgoalID == item.id && $0.status != .deleted
        }) {
            goal.tasks.append(WeekTask(
                title: item.title,
                dueDate: goal.endDate,
                estimatedMinutes: 60,
                status: item.isCompleted ? .completed : .planned,
                notes: item.detail,
                description: item.detail,
                subgoalID: item.id,
                channelID: item.channelID ?? goal.channelID,
                sourceType: .weeklyObjective,
                sortOrder: nextOrder
            ))
            nextOrder += 1
        }
        return goal
    }

    func applyPrimaryProjectionEdit(_ source: WeeklyGoal, now: Date) -> WeeklyGoal {
        var goal = source
        guard let primaryTaskID = goal.primaryTaskID,
              let task = goal.tasks.first(where: { $0.id == primaryTaskID }) else {
            return project(goal, now: now)
        }
        goal.title = task.title
        goal.outcome = task.description
        goal.startDate = task.plannedDate ?? goal.startDate
        goal.endDate = task.dueDate ?? goal.endDate
        goal.channelID = task.channelID
        goal.subgoals = task.subtasks.map { subtask in
            let existing = goal.subgoals.first(where: { $0.id == subtask.id })
            return GoalSubgoal(
                id: subtask.id,
                title: subtask.title,
                detail: existing?.detail ?? "",
                // P1-6 fix: preserve the subgoal's independent channel when
                // translating a primary-task edit back into the goal.
                channelID: existing?.channelID,
                isCompleted: subtask.completed
            )
        }
        let complete = !goal.subgoals.isEmpty && goal.subgoals.allSatisfy(\.isCompleted)
        goal.completedAt = task.status == .completed || complete ? (goal.completedAt ?? now) : nil
        return project(goal, now: now)
    }

    func weeklyPlanningProjection(_ goal: WeeklyGoal) -> WeeklyPlanningProjection {
        let projected = project(goal)
        return WeeklyPlanningProjection(
            id: goal.id,
            title: goal.title,
            outcome: goal.outcome,
            items: goal.subgoals.compactMap { item in
                guard let task = projected.tasks.first(where: { $0.subgoalID == item.id && !$0.isDeleted }) else { return nil }
                return DailyTaskProjection(
                    id: item.id,
                    goalID: goal.id,
                    title: item.title,
                    detail: item.detail,
                    completed: item.isCompleted,
                    plannedDay: task.plannedDay,
                    assignedDays: task.assignedDays,
                    channelID: goal.channelID
                )
            }
        )
    }

    func reviewProjection(_ goal: WeeklyGoal) -> ReviewProjection {
        ReviewProjection(
            goalID: goal.id,
            completedItemCount: goal.subgoals.filter(\.isCompleted).count,
            totalItemCount: goal.subgoals.count,
            actualSeconds: goal.tasks.reduce(0) { $0 + $1.actualSeconds }
        )
    }
}
