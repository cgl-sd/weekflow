import Foundation

/// Supplies the duration used by the daily-shutdown review without mutating
/// the task's recorded timer data. A completed task with no direct timer record
/// falls back to its estimate so completed work still appears in the review.
enum DailyShutdownTimeDistribution {
    static func reviewMinutes(for task: WeekTask) -> Int {
        if task.actualMinutes > 0 {
            return task.actualMinutes
        }
        guard task.status == .completed else { return 0 }
        return max(task.estimatedMinutes, 0)
    }
}
