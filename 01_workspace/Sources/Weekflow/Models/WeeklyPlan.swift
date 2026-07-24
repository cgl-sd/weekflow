import Foundation

/// A planning period that groups weekly goals together.
/// Plans have a defined date range and support archive/continuation lifecycle.
struct WeeklyPlan: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var startDay: LocalDay
    var endDay: LocalDay
    var archivedAt: Date?
    var completedAt: Date?
    var deletedAt: Date?
    var carriedFromPlanID: UUID?
    var sortOrder: Int

    var isArchived: Bool { archivedAt != nil && deletedAt == nil }
    var isActive: Bool { archivedAt == nil && completedAt == nil && deletedAt == nil }
    var isDeleted: Bool { deletedAt != nil }

    var startDate: Date {
        get { SystemBusinessCalendar.current.date(for: startDay) }
        set { startDay = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    var endDate: Date {
        get { SystemBusinessCalendar.current.date(for: endDay) }
        set { endDay = SystemBusinessCalendar.current.day(containing: newValue) }
    }

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        archivedAt: Date? = nil,
        completedAt: Date? = nil,
        deletedAt: Date? = nil,
        carriedFromPlanID: UUID? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.startDay = SystemBusinessCalendar.current.day(containing: startDate)
        self.endDay = SystemBusinessCalendar.current.day(containing: endDate)
        self.archivedAt = archivedAt
        self.completedAt = completedAt
        self.deletedAt = deletedAt
        self.carriedFromPlanID = carriedFromPlanID
        self.sortOrder = sortOrder
    }
}
