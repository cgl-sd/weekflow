import Foundation

struct DailySummary: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var content: String
    var updatedAt = Date.now
}
