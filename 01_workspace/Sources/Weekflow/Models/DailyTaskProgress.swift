import Foundation

struct DailyTaskProgress: Equatable {
    let totalTaskCount: Int
    let completedTaskCount: Int

    init(tasks: [WeekTask]) {
        totalTaskCount = tasks.count
        completedTaskCount = tasks.filter { $0.status == .completed }.count
    }

    var fraction: Double {
        guard totalTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(totalTaskCount)
    }

    var isVisible: Bool {
        completedTaskCount > 0
    }
}
