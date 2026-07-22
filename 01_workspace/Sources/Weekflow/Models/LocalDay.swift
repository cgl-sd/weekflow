import Foundation

enum LocalDayError: LocalizedError, Equatable {
    case invalidComponents(year: Int, month: Int, day: Int)
    case invalidPersistenceKey(String)

    var errorDescription: String? {
        switch self {
        case let .invalidComponents(year, month, day):
            "无效的业务日期：\(year)-\(month)-\(day)"
        case let .invalidPersistenceKey(key):
            "无效的业务日期键：\(key)"
        }
    }
}

/// A Gregorian calendar date with no time-zone or instant semantics.
struct LocalDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// P1-4 fix: validating failable initializer. Rejects impossible dates
    /// such as `LocalDay(year: 2026, month: 99, day: -10)` instead of storing
    /// garbage components that later surface as `.distantPast` dates.
    init?(validatingYear year: Int, month: Int, day: Int) {
        guard Self.isValid(year: year, month: month, day: day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1
        month = components.month ?? 1
        day = components.day ?? 1
    }

    init(persistenceKey: String) throws {
        let pieces = persistenceKey.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]),
              Self.isValid(year: year, month: month, day: day) else {
            throw LocalDayError.invalidPersistenceKey(persistenceKey)
        }
        self.init(year: year, month: month, day: day)
    }

    var persistenceKey: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var description: String { persistenceKey }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    static func < (lhs: LocalDay, rhs: LocalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == components
    }
}

extension LocalDay: Codable {
    private enum CodingKeys: String, CodingKey { case year, month, day }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let year = try container.decode(Int.self, forKey: .year)
        let month = try container.decode(Int.self, forKey: .month)
        let day = try container.decode(Int.self, forKey: .day)
        guard Self.isValid(year: year, month: month, day: day) else {
            throw LocalDayError.invalidComponents(year: year, month: month, day: day)
        }
        self.init(year: year, month: month, day: day)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(day, forKey: .day)
    }
}

/// A wall-clock time used by planning features, independent of any date.
struct LocalTime: Codable, Hashable, Comparable, Sendable {
    let minutesSinceMidnight: Int

    /// Clamping initializer for trusted internal conversions (e.g. deriving a
    /// time from a valid `Date`). Kept for backward compatibility.
    init(minutesSinceMidnight: Int) {
        self.minutesSinceMidnight = min(max(minutesSinceMidnight, 0), 23 * 60 + 59)
    }

    /// P1-4 fix: strict failable initializer. Returns `nil` for out-of-range
    /// values instead of silently clamping, so upstream logic errors surface
    /// rather than being masked (e.g. `-100 -> 00:00`, `100000 -> 23:59`).
    init?(validatingMinutesSinceMidnight minutes: Int) {
        guard (0...(23 * 60 + 59)).contains(minutes) else { return nil }
        self.minutesSinceMidnight = minutes
    }

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        self.init(minutesSinceMidnight: (components.hour ?? 0) * 60 + (components.minute ?? 0))
    }

    func date(on day: LocalDay, calendar: Calendar) -> Date? {
        var components = DateComponents(year: day.year, month: day.month, day: day.day)
        components.hour = minutesSinceMidnight / 60
        components.minute = minutesSinceMidnight % 60
        return calendar.date(from: components)
    }

    static func < (lhs: LocalTime, rhs: LocalTime) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

protocol BusinessCalendarProviding: Sendable {
    var calendar: Calendar { get }
    func day(containing date: Date) -> LocalDay
    func date(for day: LocalDay) -> Date
    func date(for time: LocalTime, on day: LocalDay) -> Date
    func addingDays(_ value: Int, to day: LocalDay) -> LocalDay
    func addingMonths(_ value: Int, to day: LocalDay) -> LocalDay
    func startOfWeek(containing day: LocalDay) -> LocalDay
}

/// The single conversion boundary between absolute `Date` values and local
/// business dates. Tests inject a fixed calendar; production uses the system's
/// autoupdating calendar so a time-zone change is observed without restart.
struct BusinessCalendar: BusinessCalendarProviding, Sendable {
    let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func day(containing date: Date) -> LocalDay {
        LocalDay(date, calendar: calendar)
    }

    func date(for day: LocalDay) -> Date {
        day.date(in: calendar) ?? .distantPast
    }

    /// P1-4 fix: non-failing conversion that returns `nil` instead of silently
    /// substituting `.distantPast`. Callers that must not hide an invalid day
    /// should prefer this over `date(for:)`.
    func dateOrNil(for day: LocalDay) -> Date? {
        day.date(in: calendar)
    }

    func date(for time: LocalTime, on day: LocalDay) -> Date {
        time.date(on: day, calendar: calendar) ?? date(for: day)
    }

    func addingDays(_ value: Int, to day: LocalDay) -> LocalDay {
        guard let result = calendar.date(byAdding: .day, value: value, to: date(for: day)) else { return day }
        return self.day(containing: result)
    }

    func addingMonths(_ value: Int, to day: LocalDay) -> LocalDay {
        guard let result = calendar.date(byAdding: .month, value: value, to: date(for: day)) else { return day }
        return self.day(containing: result)
    }

    func startOfWeek(containing day: LocalDay) -> LocalDay {
        let instant = date(for: day)
        let start = calendar.dateInterval(of: .weekOfYear, for: instant)?.start ?? instant
        return self.day(containing: start)
    }
}

enum SystemBusinessCalendar {
    /// P1-4 fix: a process-wide override so tests can inject a fixed calendar
    /// that the model-layer compatibility properties also honour. Without this,
    /// `current` always built a fresh `.autoupdatingCurrent` calendar that test
    /// fixtures could not reach, allowing a single operation to mix the Store's
    /// injected calendar with a different global one. Thread-safe.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _override: BusinessCalendar?

    static var override: BusinessCalendar? {
        get { lock.lock(); defer { lock.unlock() }; return _override }
        set { lock.lock(); defer { lock.unlock() }; _override = newValue }
    }

    static var current: BusinessCalendar {
        override ?? BusinessCalendar()
    }
}
