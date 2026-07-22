import Foundation

/// P2-1 Fix: Feature-boundary coordinator for goal lifecycle operations.
///
/// Encapsulates the complete lifecycle flow for goals (archive, trash, restore,
/// purge, copy) including state side-effects (selection updates, highlighted task
/// clearing). The Store delegates lifecycle decisions here; this coordinator
/// owns the domain rules and returns a `LifecycleOutcome` describing what
/// the Store must persist and how to update navigation state.
///
/// This establishes a true feature boundary: the Store no longer contains
/// lifecycle domain logic—it only routes actions and applies results.
struct GoalLifecycleCoordinator {
    let archiveService: ArchiveService

    init(archiveService: ArchiveService) {
        self.archiveService = archiveService
    }

    // MARK: - Outcome

    /// Describes the result of a lifecycle operation for the Store to apply.
    struct LifecycleOutcome {
        /// The mutated goal (nil if the goal was permanently deleted).
        let updatedGoal: WeeklyGoal?
        /// Whether the goal was removed from the array entirely (purge/discard).
        let removed: Bool
        /// Whether the Store should reassign selectedGoalID (goal is no longer active).
        let selectionInvalidated: Bool
        /// Whether highlightedTask should be cleared.
        let clearHighlight: Bool

        static func mutated(_ goal: WeeklyGoal, selectionInvalidated: Bool = false, clearHighlight: Bool = false) -> Self {
            Self(updatedGoal: goal, removed: false, selectionInvalidated: selectionInvalidated, clearHighlight: clearHighlight)
        }

        static func removed(selectionInvalidated: Bool = true, clearHighlight: Bool = true) -> Self {
            Self(updatedGoal: nil, removed: true, selectionInvalidated: selectionInvalidated, clearHighlight: clearHighlight)
        }
    }

    // MARK: - Goal Lifecycle Actions

    /// Archive a goal. Sets archivedAt and clears deletedAt.
    func archive(_ goal: WeeklyGoal) -> LifecycleOutcome {
        var updated = goal
        updated.archivedAt = .now
        updated.deletedAt = nil
        return .mutated(updated, selectionInvalidated: true)
    }

    /// Restore a goal from archive.
    func restore(_ goal: WeeklyGoal) -> LifecycleOutcome {
        let updated = archiveService.restored(goal)
        return .mutated(updated)
    }

    /// Soft-delete a goal (move to trash).
    func trash(_ goal: WeeklyGoal) -> LifecycleOutcome {
        var updated = goal
        updated.deletedAt = .now
        updated.archivedAt = nil
        return .mutated(updated, selectionInvalidated: true, clearHighlight: true)
    }

    /// Restore a goal from trash.
    func restoreFromTrash(_ goal: WeeklyGoal) -> LifecycleOutcome {
        var updated = goal
        updated.deletedAt = nil
        updated.archivedAt = nil
        return .mutated(updated)
    }

    /// Permanently delete a goal. Only valid if already in trash.
    func purge(_ goal: WeeklyGoal) -> LifecycleOutcome? {
        guard goal.isDeleted else { return nil }
        return .removed()
    }

    /// Discard a draft goal (remove without trash).
    func discardDraft(_ goal: WeeklyGoal) -> LifecycleOutcome {
        .removed()
    }

    // MARK: - Task Lifecycle Actions

    /// Restore a deleted task within a goal, recreating its subgoal if needed.
    func restoreDeletedTask(in goal: WeeklyGoal, taskID: UUID, now: Date, calendar: Calendar) -> WeeklyGoal {
        var updated = goal
        let restoredTask = updated.tasks.first(where: { $0.id == taskID })
        let restoredParentID = restoredTask?.parentTaskID

        // Recreate subgoal if the task was projected from one that no longer exists.
        if let restoredTask,
           let subgoalID = restoredTask.subgoalID,
           !updated.subgoals.contains(where: { $0.id == subgoalID }) {
            updated.subgoals.append(
                GoalSubgoal(
                    id: subgoalID,
                    title: restoredTask.title,
                    detail: restoredTask.description,
                    channelID: restoredTask.channelID,
                    isCompleted: false
                )
            )
        }

        // Restore the task and its children.
        for index in updated.tasks.indices
        where updated.tasks[index].id == taskID || updated.tasks[index].parentTaskID == taskID {
            updated.tasks[index].status = .planned
            updated.tasks[index].archivedAt = nil
            updated.tasks[index].plannedDate = calendar.startOfDay(for: now)
            updated.tasks[index].assignedDates = []
            updated.tasks[index].startTime = nil
            updated.tasks[index].executionWeekStart = nil
            updated.tasks[index].updatedAt = now
        }

        // Restore parent if it was also deleted.
        if let restoredParentID,
           let parentIndex = updated.tasks.firstIndex(where: { $0.id == restoredParentID && $0.status == .deleted }) {
            updated.tasks[parentIndex].status = .planned
            updated.tasks[parentIndex].archivedAt = nil
            updated.tasks[parentIndex].updatedAt = now
        }

        return updated
    }

    /// Permanently remove a task from a goal.
    func purgeTask(in goal: WeeklyGoal, taskID: UUID) -> WeeklyGoal? {
        guard goal.tasks.contains(where: { $0.id == taskID && $0.isDeleted }) else { return nil }
        var updated = goal
        updated.tasks.removeAll { $0.id == taskID || $0.parentTaskID == taskID }
        if updated.primaryTaskID == taskID { updated.primaryTaskID = nil }
        return updated
    }
}
