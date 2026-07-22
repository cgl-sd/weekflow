import Foundation

struct DailySummary: Identifiable, Codable, Hashable {
    var id: UUID
    var day: LocalDay
    var content: String
    var updatedAt: Date

    var date: Date {
        get { SystemBusinessCalendar.current.date(for: day) }
        set { day = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    init(id: UUID = UUID(), date: Date, content: String, updatedAt: Date = .now) {
        self.id = id
        day = SystemBusinessCalendar.current.day(containing: date)
        self.content = content
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, day, date, content, updatedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        day = try container.decodeIfPresent(LocalDay.self, forKey: .day)
            ?? SystemBusinessCalendar.current.day(containing: container.decode(Date.self, forKey: .date))
        content = try container.decode(String.self, forKey: .content)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encode(content, forKey: .content)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
