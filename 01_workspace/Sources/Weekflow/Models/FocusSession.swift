import Foundation
import SwiftUI

/// Legacy enum kept only for backward-compatible decoding of old records.
/// New code should use `FocusModePreferences` and string-based mode IDs.
enum FocusMode: String, CaseIterable, Identifiable, Codable {
    case meditation
    case study
    case leisure

    var id: String { rawValue }
}

extension FocusMode {
    var title: String { FocusModePreferences.title(for: rawValue) }
    var symbol: String { FocusModePreferences.symbol(for: rawValue) }
    var defaultMinutes: Int { 60 }
    var accentColor: Color { FocusModePreferences.color(for: rawValue) }
    var runningSymbol: String { "\(symbol).fill" }
}

/// A single focus session record. Internal storage is always in **seconds**;
/// `minutes` is a derived display value (P1-4 requirement: "内部统一存储秒").
struct FocusRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var day: LocalDay
    /// String-based mode ID referencing FocusModePreferences.
    var modeID: String
    /// Canonical storage – all accumulation happens here.
    var seconds: Int
    var sessionCount = 1

    /// Derived display value. Never stored independently.
    var minutes: Int { DurationDisplay.minutes(for: seconds) }

    /// Display helpers resolved from preferences.
    var modeTitle: String { FocusModePreferences.title(for: modeID) }
    var modeColor: Color { FocusModePreferences.color(for: modeID) }

    private enum CodingKeys: String, CodingKey {
        case id, day, date, mode, minutes, seconds, sessionCount
    }

    init(
        id: UUID = UUID(),
        date: Date,
        modeID: String,
        seconds: Int,
        sessionCount: Int = 1,
        calendar: BusinessCalendarProviding = SystemBusinessCalendar.current
    ) {
        self.id = id
        day = calendar.day(containing: date)
        self.modeID = modeID
        self.seconds = max(seconds, 0)
        self.sessionCount = sessionCount
    }

    /// Backward-compatible initializer accepting minutes. Converts to seconds
    /// immediately; used for legacy data migration.
    init(
        id: UUID = UUID(),
        date: Date,
        modeID: String,
        minutes: Int,
        seconds: Int? = nil,
        sessionCount: Int = 1,
        calendar: BusinessCalendarProviding = SystemBusinessCalendar.current
    ) {
        self.init(
            id: id,
            date: date,
            modeID: modeID,
            seconds: seconds ?? minutes * 60,
            sessionCount: sessionCount,
            calendar: calendar
        )
    }

    /// Source-compatible adapter for call sites that still construct legacy
    /// built-in modes. Persistence remains string-ID based.
    init(
        id: UUID = UUID(),
        date: Date,
        mode: FocusMode,
        minutes: Int,
        seconds: Int? = nil,
        sessionCount: Int = 1,
        calendar: BusinessCalendarProviding = SystemBusinessCalendar.current
    ) {
        self.init(
            id: id,
            date: date,
            modeID: mode.rawValue,
            minutes: minutes,
            seconds: seconds,
            sessionCount: sessionCount,
            calendar: calendar
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        day = try container.decodeIfPresent(LocalDay.self, forKey: .day)
            ?? SystemBusinessCalendar.current.day(containing: container.decode(Date.self, forKey: .date))
        // Decode mode as raw string (backward compatible with old FocusMode enum)
        modeID = try container.decode(String.self, forKey: .mode)
        // Prefer seconds; fall back to legacy minutes * 60 for old data.
        if let storedSeconds = try container.decodeIfPresent(Int.self, forKey: .seconds) {
            seconds = storedSeconds
        } else {
            let legacyMinutes = try container.decode(Int.self, forKey: .minutes)
            seconds = legacyMinutes * 60
        }
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 1
    }

    var date: Date {
        get { SystemBusinessCalendar.current.date(for: day) }
        set { day = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(modeID, forKey: .mode)
        // Encode both for backward compatibility with older readers.
        try container.encode(minutes, forKey: .minutes)
        try container.encode(seconds, forKey: .seconds)
        try container.encode(sessionCount, forKey: .sessionCount)
    }
}

/// Persisted snapshot of an in-flight focus countdown (P1-8 fix).
///
/// The focus timer previously kept all running state in memory, so a crash,
/// `kill -9`, or forced termination lost the active session and any unlogged
/// elapsed seconds. This snapshot is written on every state change and
/// periodically while running, allowing the next launch to recover the
/// countdown and preserve elapsed work.
struct FocusTimerSession: Codable, Equatable, Sendable {
    var modeID: String
    var totalSeconds: Int
    var remainingSeconds: Int
    var unloggedSeconds: Int
    var hasStarted: Bool
    /// P0-5 fix: whether the timer was actively running when the snapshot was
    /// persisted. Used on restore to distinguish a paused session (no offline
    /// time should be counted) from a crash during active timing.
    var isRunning: Bool?
    var linkedTask: TaskReference?
    var linkedTaskTitle: String?
    var lastCheckpointAt: Date

    private enum CodingKeys: String, CodingKey {
        case mode, modeID, totalSeconds, remainingSeconds, unloggedSeconds
        case hasStarted, isRunning, linkedTask, linkedTaskTitle, lastCheckpointAt
    }

    init(
        modeID: String,
        totalSeconds: Int,
        remainingSeconds: Int,
        unloggedSeconds: Int,
        hasStarted: Bool,
        isRunning: Bool? = nil,
        linkedTask: TaskReference? = nil,
        linkedTaskTitle: String? = nil,
        lastCheckpointAt: Date
    ) {
        self.modeID = modeID
        self.totalSeconds = totalSeconds
        self.remainingSeconds = remainingSeconds
        self.unloggedSeconds = unloggedSeconds
        self.hasStarted = hasStarted
        self.isRunning = isRunning
        self.linkedTask = linkedTask
        self.linkedTaskTitle = linkedTaskTitle
        self.lastCheckpointAt = lastCheckpointAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Backward compat: old snapshots stored enum under "mode"
        if let id = try container.decodeIfPresent(String.self, forKey: .modeID) {
            modeID = id
        } else {
            modeID = try container.decode(String.self, forKey: .mode)
        }
        totalSeconds = try container.decode(Int.self, forKey: .totalSeconds)
        remainingSeconds = try container.decode(Int.self, forKey: .remainingSeconds)
        unloggedSeconds = try container.decode(Int.self, forKey: .unloggedSeconds)
        hasStarted = try container.decode(Bool.self, forKey: .hasStarted)
        isRunning = try container.decodeIfPresent(Bool.self, forKey: .isRunning)
        linkedTask = try container.decodeIfPresent(TaskReference.self, forKey: .linkedTask)
        linkedTaskTitle = try container.decodeIfPresent(String.self, forKey: .linkedTaskTitle)
        lastCheckpointAt = try container.decode(Date.self, forKey: .lastCheckpointAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modeID, forKey: .mode)
        try container.encode(modeID, forKey: .modeID)
        try container.encode(totalSeconds, forKey: .totalSeconds)
        try container.encode(remainingSeconds, forKey: .remainingSeconds)
        try container.encode(unloggedSeconds, forKey: .unloggedSeconds)
        try container.encode(hasStarted, forKey: .hasStarted)
        try container.encodeIfPresent(isRunning, forKey: .isRunning)
        try container.encodeIfPresent(linkedTask, forKey: .linkedTask)
        try container.encodeIfPresent(linkedTaskTitle, forKey: .linkedTaskTitle)
        try container.encode(lastCheckpointAt, forKey: .lastCheckpointAt)
    }
}
