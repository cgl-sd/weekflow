import Foundation
import Testing
@testable import Weekflow

@Test func taskCardScheduleChainsUnsetTimesFromPreviousEstimatedDuration() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
    let nine = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day))
    let two = try #require(calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day))

    let first = WeekTask(title: "明确九点", startTime: nine, estimatedMinutes: 60)
    let second = WeekTask(title: "推算十点", estimatedMinutes: 30)
    let third = WeekTask(title: "推算十点半", estimatedMinutes: 45)
    let reset = WeekTask(title: "明确两点", startTime: two, estimatedMinutes: 20)
    let afterReset = WeekTask(title: "推算两点二十", estimatedMinutes: 30)

    let result = TaskCardSchedule.inferredStartTimes(
        for: [first, second, third, reset, afterReset]
    )

    #expect(result[first.id] == nil)
    #expect(result[second.id] == calendar.date(byAdding: .minute, value: 60, to: nine))
    #expect(result[third.id] == calendar.date(byAdding: .minute, value: 90, to: nine))
    #expect(result[reset.id] == nil)
    #expect(result[afterReset.id] == calendar.date(byAdding: .minute, value: 20, to: two))
}

@Test func taskCardScheduleLeavesLeadingUnsetTasksWithoutInventingAnAnchor() {
    let first = WeekTask(title: "没有锚点", estimatedMinutes: 30)
    let second = WeekTask(title: "仍没有锚点", estimatedMinutes: 30)

    #expect(TaskCardSchedule.inferredStartTimes(for: [first, second]).isEmpty)
}
