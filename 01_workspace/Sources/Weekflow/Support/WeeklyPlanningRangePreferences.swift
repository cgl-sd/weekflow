import Foundation

enum WeeklyPlanningRangePreferences {
    static let storageKey = "weekflow.weeklyPlanning.ranges.v1"

    struct Range: Codable, Equatable {
        let start: Date
        let end: Date
    }

    static func range(
        for referenceDate: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) -> Range {
        let fallback = defaultRange(for: referenceDate, calendar: calendar)
        guard let data = defaults.data(forKey: storageKey),
              let ranges = try? JSONDecoder().decode([String: Range].self, from: data),
              let stored = ranges[rangeKey(for: referenceDate, calendar: calendar)] else {
            return fallback
        }
        let start = calendar.startOfDay(for: stored.start)
        let end = calendar.startOfDay(for: stored.end)
        let dayCount = (calendar.dateComponents([.day], from: start, to: end).day ?? -1) + 1
        guard end >= start, (1...31).contains(dayCount) else { return fallback }
        return Range(start: start, end: end)
    }

    static func save(
        start: Date,
        end: Date,
        for referenceDate: Date,
        calendar: Calendar = .current,
        defaults: UserDefaults = .standard
    ) {
        var ranges = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Range].self, from: $0) }
            ?? [:]
        ranges[rangeKey(for: referenceDate, calendar: calendar)] = Range(
            start: calendar.startOfDay(for: start),
            end: calendar.startOfDay(for: max(end, start))
        )
        guard let data = try? JSONEncoder().encode(ranges) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func defaultRange(
        for referenceDate: Date,
        calendar: Calendar = .current
    ) -> Range {
        let start = WeeklyDateNavigation.weekStart(for: referenceDate, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return Range(start: start, end: end)
    }

    private static func rangeKey(for date: Date, calendar: Calendar) -> String {
        String(Int(WeeklyDateNavigation.weekStart(for: date, calendar: calendar).timeIntervalSince1970))
    }
}
