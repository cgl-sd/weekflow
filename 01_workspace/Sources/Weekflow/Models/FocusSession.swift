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

struct FocusRecord: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var mode: FocusMode
    var minutes: Int
    var sessionCount = 1

    private enum CodingKeys: String, CodingKey {
        case id, date, mode, minutes, sessionCount
    }

    init(
        id: UUID = UUID(),
        date: Date,
        mode: FocusMode,
        minutes: Int,
        sessionCount: Int = 1
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.minutes = minutes
        self.sessionCount = sessionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        mode = try container.decode(FocusMode.self, forKey: .mode)
        minutes = try container.decode(Int.self, forKey: .minutes)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 1
    }
}
