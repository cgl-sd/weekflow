import Foundation

enum AppDestination: String, CaseIterable, Identifiable {
    case home = "首页"
    case focus = "专注模式"
    case dailyPlanning = "每日计划"
    case dailyShutdown = "每日回顾"
    case weeklyPlanning = "每周计划"
    case weeklyReview = "每周回顾"
    case archive = "已归档"
    case trash = "垃圾桶"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house"
        case .focus: "mug"
        case .dailyPlanning: "checklist.checked"
        case .dailyShutdown: "rectangle.portrait.and.arrow.right"
        case .weeklyPlanning: "calendar.badge.plus"
        case .weeklyReview: "arrow.triangle.2.circlepath"
        case .archive: "archivebox"
        case .trash: "trash"
        }
    }
}

enum WorkspaceView: String, CaseIterable, Identifiable {
    case board = "仪表盘"
    case dayCalendar = "日历 · 单日"
    case threeDayCalendar = "日历 · 三日"
    case weekdaysCalendar = "日历 · 工作日"
    case weekCalendar = "日历 · 整周"
    case monthCalendar = "日历 · 月"

    var id: String { rawValue }
    var isCalendar: Bool { self != .board }

    var visibleDayCount: Int {
        switch self {
        case .board: 0
        case .dayCalendar: 1
        case .threeDayCalendar: 3
        case .weekdaysCalendar: 5
        case .weekCalendar: 7
        case .monthCalendar: 0
        }
    }
}

enum AssistantPanel: String, CaseIterable, Identifiable {
    case calendar, goals, backlog, shutdown, search

    static let railCases: [AssistantPanel] = [.calendar, .goals, .backlog, .shutdown, .search]

    var id: String { rawValue }

    static func toggled(_ item: AssistantPanel, current: AssistantPanel?) -> AssistantPanel? {
        current == item ? nil : item
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .goals: "target"
        case .backlog: "tray"
        case .shutdown: "moon.stars"
        case .search: "magnifyingglass"
        }
    }

    var title: String {
        switch self {
        case .calendar: "日历"
        case .goals: "周目标"
        case .backlog: "待办箱"
        case .shutdown: "归档"
        case .search: "搜索"
        }
    }
}

enum AssistantCalendarPresentation: Equatable {
    case timeline
    case dayTasks
}
