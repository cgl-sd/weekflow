import Foundation

/// Distinguishes the kind of timer that created a session, persisted so
/// recovery after crash or restart can apply the correct restore strategy.
enum TaskTimerType: String, Codable, Sendable {
    /// A countdown timer linked to a specific task.
    case taskCountdown
    /// A free-form focus session (meditation, study, etc.).
    case focusSession
}

struct TaskTimerSession: Codable, Equatable {
    let goalID: UUID
    let taskID: UUID
    var startedAt: Date
    var baseActualSeconds: Int
    var lastCheckpointAt: Date
    var timerType: TaskTimerType

    var baseActualMinutes: Int { DurationDisplay.minutes(for: baseActualSeconds) }

    init(
        goalID: UUID,
        taskID: UUID,
        startedAt: Date,
        baseActualSeconds: Int,
        lastCheckpointAt: Date,
        timerType: TaskTimerType = .taskCountdown
    ) {
        self.goalID = goalID
        self.taskID = taskID
        self.startedAt = startedAt
        self.baseActualSeconds = baseActualSeconds
        self.lastCheckpointAt = lastCheckpointAt
        self.timerType = timerType
    }

    init(goalID: UUID, taskID: UUID, startedAt: Date, baseActualMinutes: Int) {
        self.init(
            goalID: goalID,
            taskID: taskID,
            startedAt: startedAt,
            baseActualSeconds: baseActualMinutes * 60,
            lastCheckpointAt: startedAt,
            timerType: .taskCountdown
        )
    }

    private enum CodingKeys: String, CodingKey {
        case goalID, taskID, startedAt, baseActualSeconds, lastCheckpointAt, timerType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        goalID = try container.decode(UUID.self, forKey: .goalID)
        taskID = try container.decode(UUID.self, forKey: .taskID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        baseActualSeconds = try container.decode(Int.self, forKey: .baseActualSeconds)
        lastCheckpointAt = try container.decode(Date.self, forKey: .lastCheckpointAt)
        timerType = try container.decodeIfPresent(TaskTimerType.self, forKey: .timerType) ?? .taskCountdown
    }

    func matches(goalID: UUID, taskID: UUID) -> Bool {
        self.goalID == goalID && self.taskID == taskID
    }
}

struct InterruptedTaskTimerRecovery: Equatable {
    let session: TaskTimerSession
    let elapsedSeconds: Int
}
