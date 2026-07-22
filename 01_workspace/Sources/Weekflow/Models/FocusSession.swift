import Foundation
import SwiftUI

enum FocusMode: String, CaseIterable, Identifiable, Codable {
    case meditation
    case study
    case leisure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meditation: "禅定"
        case .study: "学习"
        case .leisure: "休闲"
        }
    }

    var symbol: String {
        switch self {
        case .meditation: "leaf"
        case .study: "book.closed"
        case .leisure: "cup.and.saucer"
        }
    }

    var defaultMinutes: Int { 60 }

    var accentColor: Color {
        switch self {
        case .meditation: WeekflowPalette.focusMeditation
        case .study: WeekflowPalette.focusStudy
        case .leisure: WeekflowPalette.focusLeisure
        }
    }

    var runningSymbol: String { "\(symbol).fill" }
}

/// A single focus session record. Internal storage is always in **seconds**;
/// `minutes` is a derived display value (P1-4 requirement: “内部统一存储秒”).
struct FocusRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var day: LocalDay
    var mode: FocusMode
    /// Canonical storage – all accumulation happens here.
    var seconds: Int
    var sessionCount = 1

    /// Derived display value. Never stored independently.
    var minutes: Int { DurationDisplay.minutes(for: seconds) }

    private enum CodingKeys: String, CodingKey {
        case id, day, date, mode, minutes, seconds, sessionCount
    }

    init(
        id: UUID = UUID(),
        date: Date,
        mode: FocusMode,
        seconds: Int,
        sessionCount: Int = 1
    ) {
        self.id = id
        day = SystemBusinessCalendar.current.day(containing: date)
        self.mode = mode
        self.seconds = max(seconds, 0)
        self.sessionCount = sessionCount
    }

    /// Backward-compatible initializer accepting minutes. Converts to seconds
    /// immediately; used for legacy data migration.
    init(
        id: UUID = UUID(),
        date: Date,
        mode: FocusMode,
        minutes: Int,
        seconds: Int? = nil,
        sessionCount: Int = 1
    ) {
        self.init(
            id: id,
            date: date,
            mode: mode,
            seconds: seconds ?? minutes * 60,
            sessionCount: sessionCount
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        day = try container.decodeIfPresent(LocalDay.self, forKey: .day)
            ?? SystemBusinessCalendar.current.day(containing: container.decode(Date.self, forKey: .date))
        mode = try container.decode(FocusMode.self, forKey: .mode)
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
        try container.encode(mode, forKey: .mode)
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
    var mode: FocusMode
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
}
