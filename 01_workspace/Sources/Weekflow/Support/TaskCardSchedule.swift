import Foundation

enum TaskCardSchedule {
    /// Produces display-only start times without mutating task data. An explicit
    /// start time resets the chain; otherwise the previous displayed start plus
    /// its estimated duration becomes the next task's inferred start.
    static func inferredStartTimes(for tasks: [WeekTask]) -> [UUID: Date] {
        var inferred: [UUID: Date] = [:]
        var nextStart: Date?

        for task in tasks {
            let displayedStart = task.startTime ?? nextStart
            if task.startTime == nil, let displayedStart {
                inferred[task.id] = displayedStart
            }

            nextStart = displayedStart.flatMap {
                Calendar.current.date(byAdding: .minute, value: task.estimatedMinutes, to: $0)
            }
        }

        return inferred
    }
}
