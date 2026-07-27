import Foundation

struct WeeklyGoalTaskGroup {
    let goal: WeeklyGoal
    let entries: [(goal: WeeklyGoal, task: WeekTask)]
}

/// Shared linear-time grouping for weekly planning surfaces. Keeping this out
/// of SwiftUI views avoids repeated goal × task scans during body evaluation.
enum WeeklyTaskGrouping {
    static func orderedGroups(
        activeGoals: [WeeklyGoal],
        entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> [WeeklyGoalTaskGroup] {
        let entriesByGoalID = Dictionary(grouping: entries) { $0.goal.id }
        return activeGoals.compactMap { goal in
            guard let goalEntries = entriesByGoalID[goal.id], !goalEntries.isEmpty else {
                return nil
            }
            return WeeklyGoalTaskGroup(goal: goal, entries: goalEntries)
        }
    }

    static func indexBounds(
        for entries: [(goal: WeeklyGoal, task: WeekTask)]
    ) -> [WeeklyGoal.ID: ClosedRange<Int>] {
        var firstIndexByGoalID: [WeeklyGoal.ID: Int] = [:]
        var lastIndexByGoalID: [WeeklyGoal.ID: Int] = [:]
        firstIndexByGoalID.reserveCapacity(entries.count)
        lastIndexByGoalID.reserveCapacity(entries.count)
        for index in entries.indices {
            let goalID = entries[index].goal.id
            if firstIndexByGoalID[goalID] == nil {
                firstIndexByGoalID[goalID] = index
            }
            lastIndexByGoalID[goalID] = index
        }
        return firstIndexByGoalID.reduce(into: [:]) { result, pair in
            if let last = lastIndexByGoalID[pair.key] {
                result[pair.key] = pair.value...last
            }
        }
    }
}
