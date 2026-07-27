import Foundation
import Testing
@testable import Weekflow

@Test func weeklyTaskGroupingKeepsGoalAndEntryOrderWithoutEmptyGroups() {
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let goalA = WeeklyGoal(title: "A", outcome: "", startDate: day, endDate: day)
    let goalB = WeeklyGoal(title: "B", outcome: "", startDate: day, endDate: day)
    let goalC = WeeklyGoal(title: "C", outcome: "", startDate: day, endDate: day)
    let taskA1 = WeekTask(title: "A1", estimatedMinutes: 30)
    let taskB1 = WeekTask(title: "B1", estimatedMinutes: 30)
    let taskA2 = WeekTask(title: "A2", estimatedMinutes: 30)
    let entries = [
        (goal: goalA, task: taskA1),
        (goal: goalB, task: taskB1),
        (goal: goalA, task: taskA2)
    ]

    let groups = WeeklyTaskGrouping.orderedGroups(
        activeGoals: [goalB, goalC, goalA],
        entries: entries
    )
    #expect(groups.map(\.goal.id) == [goalB.id, goalA.id])
    #expect(groups[0].entries.map(\.task.id) == [taskB1.id])
    #expect(groups[1].entries.map(\.task.id) == [taskA1.id, taskA2.id])

    let bounds = WeeklyTaskGrouping.indexBounds(for: entries)
    #expect(bounds[goalA.id] == 0...2)
    #expect(bounds[goalB.id] == 1...1)
    #expect(bounds[goalC.id] == nil)
}

@Test func weeklyTaskGroupingHandlesLargeCollectionsWithinLinearBudget() {
    let day = Date(timeIntervalSince1970: 1_700_000_000)
    let goals = (0..<500).map {
        WeeklyGoal(title: "G\($0)", outcome: "", startDate: day, endDate: day)
    }
    let entries = goals.flatMap { goal in
        (0..<40).map { offset in
            (goal: goal, task: WeekTask(title: "T\(offset)", estimatedMinutes: 30))
        }
    }
    let clock = ContinuousClock()
    let started = clock.now
    let groups = WeeklyTaskGrouping.orderedGroups(activeGoals: goals, entries: entries)
    let bounds = WeeklyTaskGrouping.indexBounds(for: entries)
    let elapsed = started.duration(to: clock.now)

    #expect(groups.count == 500)
    #expect(groups.allSatisfy { $0.entries.count == 40 })
    #expect(bounds.count == 500)
    #expect(elapsed < .seconds(1))
}
