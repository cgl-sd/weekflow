import CoreGraphics
import Foundation

/// Shared visible range for every hour-based calendar in Weekflow.
///
/// The day starts at 06:00 and ends at the 24:00 boundary. Keeping this in one
/// place prevents the home assistant and daily planning calendar from drifting.
enum CalendarTimelineLayout {
    static let firstHour = 6
    static let endHour = 24
    static let hourRange = firstHour...endHour

    static func contentHeight(hourHeight: CGFloat) -> CGFloat {
        CGFloat(endHour - firstHour) * hourHeight + 14
    }

    static func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= firstHour && hour < endHour
    }

    static func offset(
        for date: Date,
        hourHeight: CGFloat,
        calendar: Calendar = .current
    ) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? firstHour
        let minute = components.minute ?? 0
        let rawOffset = CGFloat(hour - firstHour) * hourHeight
            + CGFloat(minute) / 60 * hourHeight
        let maximumOffset = CGFloat(endHour - firstHour) * hourHeight
        return min(max(rawOffset, 0), maximumOffset)
    }
}
