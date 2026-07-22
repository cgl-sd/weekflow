import Foundation

struct TaskTimerSession: Equatable {
    let goalID: UUID
    let taskID: UUID
    let startedAt: Date
    let baseActualMinutes: Int

    func matches(goalID: UUID, taskID: UUID) -> Bool {
        self.goalID == goalID && self.taskID == taskID
    }
}
