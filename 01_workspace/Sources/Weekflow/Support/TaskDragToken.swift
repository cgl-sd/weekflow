import Foundation

struct TaskDragToken {
    let goalID: UUID
    let taskID: UUID
    let sourceDate: Date?

    var value: String {
        guard let sourceDate else {
            return "weekflow-task|\(goalID.uuidString)|\(taskID.uuidString)"
        }
        return "weekflow-task|\(goalID.uuidString)|\(taskID.uuidString)|\(Int(sourceDate.timeIntervalSince1970))"
    }

    init(goalID: UUID, taskID: UUID, sourceDate: Date? = nil) {
        self.goalID = goalID
        self.taskID = taskID
        self.sourceDate = sourceDate
    }

    init?(token: String) {
        let parts = token.split(separator: "|")
        guard (3...4).contains(parts.count),
              parts[0] == "weekflow-task",
              let goalID = UUID(uuidString: String(parts[1])),
              let taskID = UUID(uuidString: String(parts[2])) else { return nil }
        self.goalID = goalID
        self.taskID = taskID
        if parts.count == 4, let seconds = TimeInterval(parts[3]) {
            self.sourceDate = Date(timeIntervalSince1970: seconds)
        } else {
            self.sourceDate = nil
        }
    }
}
