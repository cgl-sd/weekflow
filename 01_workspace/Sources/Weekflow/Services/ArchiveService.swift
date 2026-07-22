import Foundation

/// Archive and restore business logic service (P2-2 Store split).
///
/// Encapsulates task and goal lifecycle transitions for archive, trash,
/// and restore operations. The Store coordinates state and persistence;
/// this service handles the domain rules for lifecycle changes.
struct ArchiveService {
    let businessCalendar: any BusinessCalendarProviding

    init(businessCalendar: any BusinessCalendarProviding = BusinessCalendar()) {
        self.businessCalendar = businessCalendar
    }

    // MARK: - Task Archive

    /// Applies archive state to a task.
    func archived(_ task: WeekTask) -> WeekTask {
        var mutableTask = task
        mutableTask.archivedAt = .now
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Restores a task from archive/trash to planned state.
    func restored(_ task: WeekTask, to date: Date) -> WeekTask {
        var mutableTask = task
        mutableTask.status = .planned
        mutableTask.archivedAt = nil
        mutableTask.rolloverCount = 0
        mutableTask.plannedDay = businessCalendar.day(containing: date)
        mutableTask.assignedDays = []
        mutableTask.startTime = nil
        mutableTask.executionWeekStart = nil
        mutableTask.updatedAt = .now
        return mutableTask
    }

    // MARK: - Task Deletion

    /// Marks a task as deleted (soft delete).
    func deleted(_ task: WeekTask) -> WeekTask {
        var mutableTask = task
        mutableTask.status = .deleted
        mutableTask.archivedAt = .now
        mutableTask.plannedDay = nil
        mutableTask.assignedDays = []
        mutableTask.startTime = nil
        mutableTask.updatedAt = .now
        return mutableTask
    }

    /// Restores a deleted task to planned state.
    func restoredFromDeleted(_ task: WeekTask, to date: Date) -> WeekTask {
        var mutableTask = task
        mutableTask.status = .planned
        mutableTask.archivedAt = nil
        mutableTask.plannedDay = businessCalendar.day(containing: date)
        mutableTask.updatedAt = .now
        return mutableTask
    }

    // MARK: - Goal Archive

    /// Applies archive state to a goal and all its tasks.
    func archived(_ goal: WeeklyGoal) -> WeeklyGoal {
        var mutableGoal = goal
        mutableGoal.archivedAt = .now
        for index in mutableGoal.tasks.indices {
            mutableGoal.tasks[index].archivedAt = .now
            mutableGoal.tasks[index].updatedAt = .now
        }
        return mutableGoal
    }

    /// Restores a goal from archive.
    func restored(_ goal: WeeklyGoal) -> WeeklyGoal {
        var mutableGoal = goal
        mutableGoal.archivedAt = nil
        for index in mutableGoal.tasks.indices
        where mutableGoal.tasks[index].status != .deleted {
            mutableGoal.tasks[index].archivedAt = nil
            mutableGoal.tasks[index].updatedAt = .now
        }
        return mutableGoal
    }

    // MARK: - Goal Deletion

    /// Marks a goal as deleted (soft delete).
    func deleted(_ goal: WeeklyGoal) -> WeeklyGoal {
        var mutableGoal = goal
        mutableGoal.archivedAt = .now
        for index in mutableGoal.tasks.indices {
            mutableGoal.tasks[index].status = .deleted
            mutableGoal.tasks[index].archivedAt = .now
            mutableGoal.tasks[index].plannedDay = nil
            mutableGoal.tasks[index].assignedDays = []
            mutableGoal.tasks[index].updatedAt = .now
        }
        return mutableGoal
    }

    /// Restores a deleted goal.
    func restoredFromDeleted(_ goal: WeeklyGoal) -> WeeklyGoal {
        var mutableGoal = goal
        mutableGoal.archivedAt = nil
        for index in mutableGoal.tasks.indices
        where mutableGoal.tasks[index].status == .deleted {
            mutableGoal.tasks[index].status = .planned
            mutableGoal.tasks[index].archivedAt = nil
            mutableGoal.tasks[index].updatedAt = .now
        }
        return mutableGoal
    }

    // MARK: - Completion Archive

    /// Archives completed tasks in a goal.
    func archiveCompletedTasks(in goal: WeeklyGoal) -> WeeklyGoal {
        var mutableGoal = goal
        for index in mutableGoal.tasks.indices
        where mutableGoal.tasks[index].status == .completed && mutableGoal.tasks[index].archivedAt == nil {
            mutableGoal.tasks[index].archivedAt = .now
            mutableGoal.tasks[index].updatedAt = .now
        }
        return mutableGoal
    }

    // MARK: - Queries

    /// Checks if a task is archived.
    func isArchived(_ task: WeekTask) -> Bool {
        task.archivedAt != nil || task.status == .archived
    }

    /// Checks if a task is deleted.
    func isDeleted(_ task: WeekTask) -> Bool {
        task.status == .deleted
    }

    /// Checks if a goal is archived.
    func isArchived(_ goal: WeeklyGoal) -> Bool {
        goal.archivedAt != nil
    }
}
