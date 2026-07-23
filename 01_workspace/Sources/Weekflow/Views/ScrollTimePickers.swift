import SwiftUI

/// A compact, scrollable clock picker shared by task cards and task editors.
/// It deliberately avoids the platform stepper-style time field so every time
/// input in Weekflow follows the same direct-selection interaction.
struct ScrollClockTimePopover: View {
    let selection: Date?
    let anchorDate: Date
    let minuteRange: ClosedRange<Int>
    let minuteStep: Int
    let allowsUnset: Bool
    let title: String
    let select: (Date?) -> Void

    @Environment(\.businessCalendar) private var businessCalendar
    private var calendar: Calendar { businessCalendar.calendar }
    private let rowHeight: CGFloat = 30

    init(
        selection: Date?,
        anchorDate: Date,
        minuteRange: ClosedRange<Int> = 360...1_440,
        minuteStep: Int = 15,
        allowsUnset: Bool = true,
        title: String = "选择开始时间",
        select: @escaping (Date?) -> Void
    ) {
        self.selection = selection
        self.anchorDate = anchorDate
        self.minuteRange = minuteRange
        self.minuteStep = max(minuteStep, 1)
        self.allowsUnset = allowsUnset
        self.title = title
        self.select = select
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pickerHeader(title)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(minuteChoices, id: \.self) { minute in
                            WeekflowButton {
                                select(date(for: minute))
                            } label: {
                                selectionRow(
                                    title: clockText(for: minute),
                                    selected: selectedMinute == minute
                                )
                            }
                            .buttonStyle(.plain)
                            .modifier(ScrollTimeChoiceHighlight(selected: selectedMinute == minute))
                            .id(minute)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .onAppear {
                    proxy.scrollTo(nearestChoice(to: selectedMinute ?? currentAnchorMinute), anchor: .center)
                }
            }
            if allowsUnset {
                Divider()
                WeekflowButton {
                    select(nil)
                } label: {
                    selectionRow(title: "不设置", selected: selection == nil)
                }
                .buttonStyle(.plain)
                .modifier(ScrollTimeChoiceHighlight(selected: selection == nil))
                .padding(.horizontal, 4)
            }
        }
        .frame(width: 176, height: 244, alignment: .topLeading)
        .background(WeekflowPalette.surface)
    }

    private var minuteChoices: [Int] {
        Self.minuteChoices(range: minuteRange, step: minuteStep)
    }

    private var selectedMinute: Int? {
        guard let selection else { return nil }
        let anchorDay = calendar.startOfDay(for: anchorDate)
        let selectionDay = calendar.startOfDay(for: selection)
        if selectionDay > anchorDay,
           calendar.component(.hour, from: selection) == 0,
           calendar.component(.minute, from: selection) == 0 {
            return 1_440
        }
        let parts = calendar.dateComponents([.hour, .minute], from: selection)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private var currentAnchorMinute: Int {
        let parts = calendar.dateComponents([.hour, .minute], from: selection ?? anchorDate)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func date(for minute: Int) -> Date {
        let day = calendar.startOfDay(for: anchorDate)
        return calendar.date(byAdding: .minute, value: minute, to: day) ?? day
    }

    private func clockText(for minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private func nearestChoice(to minute: Int) -> Int {
        minuteChoices.min { abs($0 - minute) < abs($1 - minute) } ?? minuteRange.lowerBound
    }

    private func selectionRow(title: String, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .monospacedDigit()
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.objective)
            }
        }
        .foregroundStyle(WeekflowPalette.primaryText)
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    static func slot(for date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return min(max((parts.hour ?? 0) * 4 + (parts.minute ?? 0) / 15, 0), 95)
    }

    static func minuteChoices(range: ClosedRange<Int>, step: Int) -> [Int] {
        Array(stride(from: range.lowerBound, through: range.upperBound, by: max(step, 1)))
    }

    static func clockText(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func date(for slot: Int, anchorDate: Date, calendar: Calendar = .current) -> Date {
        let boundedSlot = min(max(slot, 0), 95)
        let hour = boundedSlot / 4
        let minute = (boundedSlot % 4) * 15
        let day = calendar.startOfDay(for: anchorDate)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

struct ScrollTimeChoiceHighlight: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                hovering || selected ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .pointingHandCursor()
            .onHover { hovering = $0 }
    }
}

/// A reusable scrolling duration list. Callers choose the valid range and step,
/// while presentation and selection feedback stay consistent across the app.
struct ScrollDurationPopover: View {
    @Binding var minutes: Int
    let range: ClosedRange<Int>
    let step: Int
    let allowsZero: Bool
    let title: String
    let width: CGFloat
    let height: CGFloat
    let presetChoices: [Int]?

    init(
        minutes: Binding<Int>,
        range: ClosedRange<Int> = 0...480,
        step: Int = 15,
        allowsZero: Bool = true,
        title: String = "设置时长",
        width: CGFloat = 176,
        height: CGFloat = 244,
        presetChoices: [Int]? = nil
    ) {
        _minutes = minutes
        self.range = range
        self.step = max(step, 1)
        self.allowsZero = allowsZero
        self.title = title
        self.width = width
        self.height = height
        self.presetChoices = presetChoices
    }

    var choices: [Int] {
        if let presetChoices {
            var values = presetChoices.filter { range.contains($0) && $0 != 0 }
            if range.contains(minutes), minutes != 0, !values.contains(minutes) { values.append(minutes) }
            return Array(Set(values)).sorted()
        }
        return Self.choices(range: range, step: step, allowsZero: false, including: minutes)
    }

    static func choices(
        range: ClosedRange<Int>,
        step: Int,
        allowsZero: Bool,
        including minutes: Int
    ) -> [Int] {
        let step = max(step, 1)
        let lower = allowsZero ? range.lowerBound : max(range.lowerBound, step)
        guard lower <= range.upperBound else { return [] }
        var values = Array(stride(from: lower, through: range.upperBound, by: step))
        if range.contains(minutes), !values.contains(minutes) {
            values.append(minutes)
            values.sort()
        }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pickerHeader(title)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(choices, id: \.self) { choice in
                            DurationChoiceButton(
                                selected: minutes == choice,
                                title: durationText(choice)
                            ) {
                                minutes = choice
                            }
                            .id(choice)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .onAppear {
                    proxy.scrollTo(nearestChoice, anchor: .center)
                }
            }
            if allowsZero {
                Divider()
                DurationChoiceButton(
                    selected: minutes == 0,
                    title: "不设置"
                ) {
                    minutes = 0
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(WeekflowPalette.surface)
    }

    private var nearestChoice: Int {
        choices.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? range.lowerBound
    }

    private func durationText(_ value: Int) -> String {
        if value == 0 { return "不设置" }
        return value.hourMinuteClockText
    }
}

struct DurationChoiceButton: View {
    let selected: Bool
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12))
                    .monospacedDigit()
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.objective)
                }
            }
            .foregroundStyle(WeekflowPalette.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                hovering || selected ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

private func pickerHeader(_ title: String) -> some View {
    Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(WeekflowPalette.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 32)
}
