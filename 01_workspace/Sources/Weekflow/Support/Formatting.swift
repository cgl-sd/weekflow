import Foundation
import SwiftUI

enum WeeklyDateNavigation {
    static func weekStart(
        for date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let day = calendar.startOfDay(for: date)
        let daysSinceMonday = (calendar.component(.weekday, from: day) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    static func weekEnd(
        for date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let start = weekStart(for: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: 6, to: start) ?? start
    }

    static func isCurrentWeek(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(
            weekStart(for: date, calendar: calendar),
            inSameDayAs: weekStart(for: now, calendar: calendar)
        )
    }
}

extension Int {
    var hourMinuteText: String {
        let hours = self / 60
        let minutes = self % 60
        if hours == 0 { return "\(minutes) 分钟" }
        return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分钟"
    }

    var hourMinuteClockText: String {
        String(format: "%02d:%02d", self / 60, self % 60)
    }
}

enum TaskTimeDisplay {
    static let unsetStart = "--:--"
    static let unsetEstimated = "--:--"

    static func estimated(minutes: Int) -> String {
        minutes > 0 ? minutes.hourMinuteClockText : unsetEstimated
    }

    static func actual(minutes: Int, estimatedMinutes: Int) -> String {
        if minutes > 0 { return minutes.hourMinuteClockText }
        return estimatedMinutes > 0 ? "00:00" : unsetStart
    }
}

extension Date {
    var dayLabel: String { formatted(.dateTime.month().day().weekday(.wide)) }
    static var weekRangeLabel: String { weekRangeLabel(for: .now) }
    static func weekRangeLabel(for date: Date) -> String {
        let calendar = SystemBusinessCalendar.current.calendar
        let start = WeeklyDateNavigation.weekStart(for: date, calendar: calendar)
        let end = WeeklyDateNavigation.weekEnd(for: date, calendar: calendar)
        return "\(start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
    }
}

extension Calendar {
    func daysOfCurrentWeek() -> [Date] {
        guard let start = dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { date(byAdding: .day, value: $0, to: start) }
    }
}

extension TaskStatus {
    var label: String {
        switch self { case .planned: "待执行"; case .inProgress: "进行中"; case .completed: "已完成"; case .archived: "已归档"; case .deleted: "垃圾桶" }
    }
}

extension WeekTask {
    var taskCardTimerText: String {
        let estimatedText = TaskTimeDisplay.estimated(minutes: estimatedMinutes)
        guard actualMinutes > 0 else { return estimatedText }
        return "\(actualMinutes.hourMinuteClockText) / \(estimatedText)"
    }
}

extension MilestoneType {
    var tint: Color {
        switch self {
        case .meeting: WeekflowPalette.channelBlue
        case .checkpoint: WeekflowPalette.warning
        case .delivery: WeekflowPalette.objective
        }
    }
}
