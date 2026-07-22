import Foundation

/// Per-day planning choices that belong to Weekflow's local planning model.
///
/// The selected cutoff is stored in minutes after midnight so it remains
/// independent from locale formatting while still mapping cleanly to the
/// corresponding calendar marker.
struct DailyPlanningState: Identifiable, Codable, Hashable {
    static let minimumStartMinutes = 0
    static let maximumStartMinutes = 23 * 60 + 30
    static let startStepMinutes = 30
    static let defaultStartMinutes = 9 * 60
    static let allowedStartMinutes = Array(
        stride(
            from: minimumStartMinutes,
            through: maximumStartMinutes,
            by: startStepMinutes
        )
    )
    static let minimumCutoffMinutes = 30
    static let maximumCutoffMinutes = 24 * 60
    static let cutoffStepMinutes = 30
    static let defaultCutoffMinutes = 17 * 60
    static let allowedCutoffMinutes = Array(
        stride(
            from: minimumCutoffMinutes,
            through: maximumCutoffMinutes,
            by: cutoffStepMinutes
        )
    )

    var id: UUID
    var date: Date
    var startMinutes: Int
    var cutoffMinutes: Int

    init(
        id: UUID = UUID(),
        date: Date,
        startMinutes: Int = DailyPlanningState.defaultStartMinutes,
        cutoffMinutes: Int = DailyPlanningState.defaultCutoffMinutes,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.date = calendar.startOfDay(for: date)
        let normalizedStart = Self.normalizedStartMinutes(startMinutes)
        let normalizedCutoff = max(
            Self.normalizedCutoffMinutes(cutoffMinutes),
            Self.minimumStartMinutes + Self.cutoffStepMinutes
        )
        self.startMinutes = min(normalizedStart, normalizedCutoff - Self.startStepMinutes)
        self.cutoffMinutes = max(normalizedCutoff, self.startMinutes + Self.cutoffStepMinutes)
    }

    static func normalizedStartMinutes(_ minutes: Int) -> Int {
        let rounded = Int((Double(minutes) / Double(startStepMinutes)).rounded()) * startStepMinutes
        return min(max(rounded, minimumStartMinutes), maximumStartMinutes)
    }

    static func normalizedCutoffMinutes(_ minutes: Int) -> Int {
        let rounded = Int((Double(minutes) / Double(cutoffStepMinutes)).rounded()) * cutoffStepMinutes
        return min(max(rounded, minimumCutoffMinutes), maximumCutoffMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, startMinutes, cutoffMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let date = try container.decode(Date.self, forKey: .date)
        let start = try container.decodeIfPresent(Int.self, forKey: .startMinutes)
            ?? Self.defaultStartMinutes
        let cutoff = try container.decodeIfPresent(Int.self, forKey: .cutoffMinutes)
            ?? Self.defaultCutoffMinutes
        self.init(id: id, date: date, startMinutes: start, cutoffMinutes: cutoff)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(startMinutes, forKey: .startMinutes)
        try container.encode(cutoffMinutes, forKey: .cutoffMinutes)
    }
}
