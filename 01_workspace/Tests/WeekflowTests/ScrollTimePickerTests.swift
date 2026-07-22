import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func scrollClockPickerMapsEveryQuarterHourOntoTheAnchorDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let anchor = try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 7,
        day: 13,
        hour: 9,
        minute: 42
    )))

    let first = ScrollClockTimePopover.date(for: 0, anchorDate: anchor, calendar: calendar)
    let sample = ScrollClockTimePopover.date(for: 57, anchorDate: anchor, calendar: calendar)
    let last = ScrollClockTimePopover.date(for: 95, anchorDate: anchor, calendar: calendar)

    #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: first) == DateComponents(
        year: 2026, month: 7, day: 13, hour: 0, minute: 0
    ))
    #expect(calendar.component(.hour, from: sample) == 14)
    #expect(calendar.component(.minute, from: sample) == 15)
    #expect(calendar.component(.hour, from: last) == 23)
    #expect(calendar.component(.minute, from: last) == 45)
    #expect(ScrollClockTimePopover.slot(for: sample, calendar: calendar) == 57)
}

@MainActor
@Test func composerStartTimePickerUsesHalfHoursFromSixThroughMidnight() throws {
    let anchor = try #require(Calendar.current.date(
        from: DateComponents(year: 2026, month: 7, day: 13, hour: 12)
    ))
    let choices = ScrollClockTimePopover.minuteChoices(range: 360...1_440, step: 30)
    #expect(choices.first == 360)
    #expect(choices.last == 1_440)
    #expect(choices.count == 37)
    #expect(zip(choices, choices.dropFirst()).allSatisfy { pair in pair.1 - pair.0 == 30 })

    let picker = ScrollClockTimePopover(
        selection: nil,
        anchorDate: anchor,
        minuteRange: 360...1_440,
        minuteStep: 30
    ) { _ in }

    let host = NSHostingView(rootView: picker)
    #expect(host.fittingSize == NSSize(width: 176, height: 244))

    let midnight = try #require(Calendar.current.date(
        byAdding: .minute,
        value: 1_440,
        to: Calendar.current.startOfDay(for: anchor)
    ))
    let nextDay = try #require(Calendar.current.date(byAdding: .day, value: 1, to: anchor))
    #expect(Calendar.current.isDate(midnight, inSameDayAs: nextDay))
}

@MainActor
@Test func scrollingDurationChoicesRespectRangeStepClearAndCurrentValue() {
    let regular = ScrollDurationPopover.choices(
        range: 0...60,
        step: 15,
        allowsZero: true,
        including: 30
    )
    #expect(regular == [0, 15, 30, 45, 60])

    let focus = ScrollDurationPopover.choices(
        range: 5...20,
        step: 5,
        allowsZero: false,
        including: 12
    )
    #expect(focus == [5, 10, 12, 15, 20])
}

@Test func manualActualTimeCanDecreaseWhenTheTimerIsNotRunning() {
    #expect(TaskActualMinutesPolicy.resolved(manual: 15, live: 60, timerIsRunning: false) == 15)
    #expect(TaskActualMinutesPolicy.resolved(manual: 15, live: 60, timerIsRunning: true) == 60)
}

@MainActor
@Test func sharedTimePickersRenderAtCompactStableSizes() throws {
    let anchor = Date(timeIntervalSince1970: 1_784_028_600)
    let clock = ScrollClockTimePopover(selection: nil, anchorDate: anchor) { _ in }
    let clockHost = NSHostingView(rootView: clock)
    #expect(clockHost.fittingSize == NSSize(width: 176, height: 244))

    var duration = 45
    let durationPicker = ScrollDurationPopover(
        minutes: Binding(get: { duration }, set: { duration = $0 }),
        range: 0...240,
        step: 15
    )
    let durationHost = NSHostingView(rootView: durationPicker)
    #expect(durationHost.fittingSize == NSSize(width: 176, height: 244))
}

@Test func sourceContainsNoLegacyTimeInputControls() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let packageRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sources = packageRoot.appendingPathComponent("Sources/Weekflow", isDirectory: true)
    let enumerator = try #require(FileManager.default.enumerator(
        at: sources,
        includingPropertiesForKeys: nil
    ))
    let swiftFiles = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    let combined = try swiftFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

    #expect(!combined.contains("Slider("))
    #expect(!combined.contains("Stepper("))
    #expect(!combined.contains("displayedComponents: .hourAndMinute"))
}
