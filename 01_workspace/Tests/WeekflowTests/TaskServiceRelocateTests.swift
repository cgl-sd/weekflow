import Foundation
import Testing
@testable import Weekflow

/// R08: task relocation domain rule lives in TaskService and uses the injected
/// calendar (LocalDay-based), so it is parallel-safe and directly testable.
@Test func taskServiceRelocatedMovesWeeklyObjectiveAssignmentToTargetDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let service = TaskService(businessCalendar: BusinessCalendar(calendar: calendar))
    let source = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))!
    let target = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
    var task = WeekTask(title: "周目标任务", estimatedMinutes: 30, sourceType: .weeklyObjective)
    task.assignedDays = [LocalDay(source, calendar: calendar)]

    let moved = service.relocated(task, from: source, to: target)
    #expect(moved.assignedDays.contains(LocalDay(target, calendar: calendar)))
    #expect(!moved.assignedDays.contains(LocalDay(source, calendar: calendar)))
}

@Test func taskServiceRelocatedMovesPlannedTaskKeepsStartTimeOfDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let service = TaskService(businessCalendar: BusinessCalendar(calendar: calendar))
    let source = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 9, minute: 30))!
    let target = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))!
    var task = WeekTask(title: "已排期任务", plannedDate: source, startTime: source, estimatedMinutes: 30)

    let moved = service.relocated(task, from: source, to: target)
    #expect(moved.plannedDay == LocalDay(target, calendar: calendar))
    let comps = calendar.dateComponents([.hour, .minute], from: moved.startTime!)
    #expect(comps.hour == 9 && comps.minute == 30)
}
