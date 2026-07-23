import Foundation
import SwiftData

// MARK: - Frozen historical schema types (R10)
//
// These @Model types are INDEPENDENT, FROZEN copies of the V1/V2 record shapes.
// They exist so that future modifications to the *live* record classes
// (PersistedGoalRecord, etc.) can never silently rewrite the historical V1/V2
// definitions that existing user databases were created against.
//
// The live store continues to use the current record classes (see
// PersistenceModels.swift). These frozen types are referenced only by
// WeekflowFrozenSchemaV1/V2 for structure validation, fixture generation, and as
// the source/target of the staged migration plan (R11). They are deliberately NOT
// registered in the live ModelContainer under their own names today; wiring them
// into the live V1→V2→V3 migration is the R11 step.
//
// RULE: never edit a frozen type in place. A new schema version means new types.

// MARK: V1 frozen records

@Model
final class PersistenceMetadataRecordV1 {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date
    init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key; self.value = value; self.updatedAt = updatedAt
    }
}

@Model
final class PersistedGoalRecordV1 {
    @Attribute(.unique) var id: UUID
    var payload: Data
    var periodStart: Date
    var periodEnd: Date
    var channelID: String?
    var lifecycleState: String
    var revision: Int
    var updatedAt: Date
    init(id: UUID, payload: Data, periodStart: Date, periodEnd: Date,
         channelID: String?, lifecycleState: String, revision: Int, updatedAt: Date) {
        self.id = id; self.payload = payload; self.periodStart = periodStart
        self.periodEnd = periodEnd; self.channelID = channelID
        self.lifecycleState = lifecycleState; self.revision = revision; self.updatedAt = updatedAt
    }
}

@Model
final class PersistedTaskRecordV1 {
    @Attribute(.unique) var id: UUID
    var goalID: UUID
    var subgoalID: UUID?
    var payload: Data
    var channelID: String?
    var lifecycleState: String
    var revision: Int
    var updatedAt: Date
    init(id: UUID, goalID: UUID, subgoalID: UUID?, payload: Data, channelID: String?,
         lifecycleState: String, revision: Int, updatedAt: Date) {
        self.id = id; self.goalID = goalID; self.subgoalID = subgoalID; self.payload = payload
        self.channelID = channelID; self.lifecycleState = lifecycleState
        self.revision = revision; self.updatedAt = updatedAt
    }
}

@Model
final class PersistedTaskAssignmentRecordV1 {
    @Attribute(.unique) var uniquenessKey: String
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var day: Date
    var placementMask: Int
    var source: String
    var originTransactionID: UUID?
    var revision: Int
    init(uniquenessKey: String, id: UUID = UUID(), taskID: UUID, day: Date,
         placementMask: Int, source: String, originTransactionID: UUID?, revision: Int = 1) {
        self.uniquenessKey = uniquenessKey; self.id = id; self.taskID = taskID; self.day = day
        self.placementMask = placementMask; self.source = source
        self.originTransactionID = originTransactionID; self.revision = revision
    }
}

@Model
final class PersistedPayloadRecordV1 {
    @Attribute(.unique) var key: String
    var entityType: String
    var entityID: String
    var dateKey: Date?
    var payload: Data
    var revision: Int
    var updatedAt: Date
    init(key: String, entityType: String, entityID: String, dateKey: Date? = nil,
         payload: Data, revision: Int = 1, updatedAt: Date = .now) {
        self.key = key; self.entityType = entityType; self.entityID = entityID
        self.dateKey = dateKey; self.payload = payload; self.revision = revision; self.updatedAt = updatedAt
    }
}

@Model
final class PersistedLifecycleEventRecordV1 {
    @Attribute(.unique) var id: UUID
    var entityType: String
    var entityID: String
    var fromState: String
    var toState: String
    var transactionID: UUID
    var createdAt: Date
    init(id: UUID = UUID(), entityType: String, entityID: String, fromState: String,
         toState: String, transactionID: UUID, createdAt: Date = .now) {
        self.id = id; self.entityType = entityType; self.entityID = entityID
        self.fromState = fromState; self.toState = toState
        self.transactionID = transactionID; self.createdAt = createdAt
    }
}

@Model
final class PersistedMutationTransactionRecordV1 {
    @Attribute(.unique) var id: UUID
    var kind: String
    var createdAt: Date
    var undoState: String
    var committedAt: Date?
    var compensatesTransactionID: UUID?
    init(id: UUID = UUID(), kind: String, createdAt: Date = .now,
         undoState: String = PersistenceUndoState.available, committedAt: Date? = nil,
         compensatesTransactionID: UUID? = nil) {
        self.id = id; self.kind = kind; self.createdAt = createdAt; self.undoState = undoState
        self.committedAt = committedAt; self.compensatesTransactionID = compensatesTransactionID
    }
}

@Model
final class PersistedMutationOperationRecordV1 {
    @Attribute(.unique) var id: UUID
    var transactionID: UUID
    var sequence: Int
    var entityType: String
    var entityID: String
    var field: String
    var beforeValue: Data?
    var afterValue: Data?
    init(id: UUID = UUID(), transactionID: UUID, sequence: Int, entityType: String,
         entityID: String, field: String = "payload", beforeValue: Data?, afterValue: Data?) {
        self.id = id; self.transactionID = transactionID; self.sequence = sequence
        self.entityType = entityType; self.entityID = entityID; self.field = field
        self.beforeValue = beforeValue; self.afterValue = afterValue
    }
}

// MARK: V2 frozen record (V1 + migration audit)

@Model
final class PersistedMigrationAuditRecordV2 {
    @Attribute(.unique) var id: UUID
    var fromVersion: Int
    var toVersion: Int
    var result: String
    var failureReason: String?
    var completedAt: Date
    init(id: UUID = UUID(), fromVersion: Int, toVersion: Int, result: String,
         failureReason: String? = nil, completedAt: Date = .now) {
        self.id = id; self.fromVersion = fromVersion; self.toVersion = toVersion
        self.result = result; self.failureReason = failureReason; self.completedAt = completedAt
    }
}

// MARK: - Frozen VersionedSchemas

/// Frozen V1 schema referencing the independent V1 record types.
enum WeekflowFrozenSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            PersistenceMetadataRecordV1.self,
            PersistedGoalRecordV1.self,
            PersistedTaskRecordV1.self,
            PersistedTaskAssignmentRecordV1.self,
            PersistedPayloadRecordV1.self,
            PersistedLifecycleEventRecordV1.self,
            PersistedMutationTransactionRecordV1.self,
            PersistedMutationOperationRecordV1.self
        ]
    }
}

/// Frozen V2 schema: frozen V1 records + the frozen migration-audit record.
enum WeekflowFrozenSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        WeekflowFrozenSchemaV1.models + [PersistedMigrationAuditRecordV2.self]
    }
}
