import Foundation

enum PersistenceValidationError: LocalizedError, Equatable {
    case duplicateGoalID(UUID)
    case duplicateTaskID(UUID)
    case duplicateSubgoalID(UUID)
    case duplicatePayloadID(entityType: String, entityID: String)
    case conflictingGoalChange(UUID)
    case conflictingTaskChange(UUID)

    var errorDescription: String? {
        switch self {
        case .duplicateGoalID(let id):
            "检测到重复的周目标 ID：\(id.uuidString)"
        case .duplicateTaskID(let id):
            "检测到重复的任务 ID：\(id.uuidString)"
        case .duplicateSubgoalID(let id):
            "检测到重复的子目标 ID：\(id.uuidString)"
        case .duplicatePayloadID(let entityType, let entityID):
            "检测到重复的持久化实体 ID：\(entityType)/\(entityID)"
        case .conflictingGoalChange(let id):
            "同一周目标同时出现在写入与删除集合：\(id.uuidString)"
        case .conflictingTaskChange(let id):
            "同一任务同时出现在写入与删除集合：\(id.uuidString)"
        }
    }
}

enum PersistenceIdentityValidator {
    static func validate(goals: [WeeklyGoal]) throws {
        var goalIDs = Set<UUID>()
        var taskIDs = Set<UUID>()
        var subgoalIDs = Set<UUID>()

        for goal in goals {
            guard goalIDs.insert(goal.id).inserted else {
                throw PersistenceValidationError.duplicateGoalID(goal.id)
            }
            for subgoal in goal.subgoals {
                guard subgoalIDs.insert(subgoal.id).inserted else {
                    throw PersistenceValidationError.duplicateSubgoalID(subgoal.id)
                }
            }
            for task in goal.tasks {
                guard taskIDs.insert(task.id).inserted else {
                    throw PersistenceValidationError.duplicateTaskID(task.id)
                }
            }
        }
    }

    static func validatePayloadIDs<Value>(
        _ values: [Value],
        entityType: String,
        id: (Value) -> String
    ) throws {
        var identifiers = Set<String>()
        for value in values {
            let entityID = id(value)
            guard identifiers.insert(entityID).inserted else {
                throw PersistenceValidationError.duplicatePayloadID(
                    entityType: entityType,
                    entityID: entityID
                )
            }
        }
    }
}

extension PersistenceGoalChangeSet {
    func validateForPersistence() throws {
        var goalIDs = Set<UUID>()
        for goal in goalsToUpsert {
            guard goalIDs.insert(goal.id).inserted else {
                throw PersistenceValidationError.duplicateGoalID(goal.id)
            }
        }
        let deletedGoalIDs = Set(goalIDsToDelete)
        if let conflict = goalIDs.first(where: deletedGoalIDs.contains) {
            throw PersistenceValidationError.conflictingGoalChange(conflict)
        }

        var taskIDs = Set<UUID>()
        for upsert in tasksToUpsert {
            guard taskIDs.insert(upsert.task.id).inserted else {
                throw PersistenceValidationError.duplicateTaskID(upsert.task.id)
            }
        }
        let deletedTaskIDs = Set(taskIDsToDelete)
        if let conflict = taskIDs.first(where: deletedTaskIDs.contains) {
            throw PersistenceValidationError.conflictingTaskChange(conflict)
        }
    }
}
