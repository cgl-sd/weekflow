import Foundation
import SwiftData

enum WeekflowSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            PersistenceMetadataRecord.self,
            PersistedGoalRecord.self,
            PersistedTaskRecord.self,
            PersistedTaskAssignmentRecord.self,
            PersistedPayloadRecord.self,
            PersistedLifecycleEventRecord.self,
            PersistedMutationTransactionRecord.self,
            PersistedMutationOperationRecord.self
        ]
    }
}

/// V1 remains frozen above. V2 adds an append-only migration audit entity;
/// business-date payload normalization is performed by backward-compatible
/// Codable adapters when records are next written.
enum WeekflowSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        WeekflowSchemaV1.models + [PersistedMigrationAuditRecord.self]
    }
}

enum WeekflowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WeekflowSchemaV1.self, WeekflowSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: WeekflowSchemaV1.self, toVersion: WeekflowSchemaV2.self)]
    }
}

enum PersistedLifecycleState: String, Codable {
    case active
    case archived
    case trashed
    case purged
}

@Model
final class PersistenceMetadataRecord {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date

    init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedMigrationAuditRecord {
    @Attribute(.unique) var id: UUID
    var fromVersion: Int
    var toVersion: Int
    var result: String
    var failureReason: String?
    var completedAt: Date

    init(
        id: UUID = UUID(),
        fromVersion: Int,
        toVersion: Int,
        result: String,
        failureReason: String? = nil,
        completedAt: Date = .now
    ) {
        self.id = id
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.result = result
        self.failureReason = failureReason
        self.completedAt = completedAt
    }
}

@Model
final class PersistedGoalRecord {
    @Attribute(.unique) var id: UUID
    var payload: Data
    var periodStart: Date
    var periodEnd: Date
    var channelID: String?
    var lifecycleState: String
    var revision: Int
    var updatedAt: Date

    init(
        id: UUID,
        payload: Data,
        periodStart: Date,
        periodEnd: Date,
        channelID: String?,
        lifecycleState: String,
        revision: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.payload = payload
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.channelID = channelID
        self.lifecycleState = lifecycleState
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedTaskRecord {
    @Attribute(.unique) var id: UUID
    var goalID: UUID
    var subgoalID: UUID?
    var payload: Data
    var channelID: String?
    var lifecycleState: String
    var revision: Int
    var updatedAt: Date

    init(
        id: UUID,
        goalID: UUID,
        subgoalID: UUID?,
        payload: Data,
        channelID: String?,
        lifecycleState: String,
        revision: Int,
        updatedAt: Date
    ) {
        self.id = id
        self.goalID = goalID
        self.subgoalID = subgoalID
        self.payload = payload
        self.channelID = channelID
        self.lifecycleState = lifecycleState
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedTaskAssignmentRecord {
    /// A task can occur at most once per calendar day. Planned and assigned
    /// placement are represented by bits in `placementMask`.
    @Attribute(.unique) var uniquenessKey: String
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var day: Date
    var placementMask: Int
    var source: String
    var originTransactionID: UUID?
    var revision: Int

    init(
        uniquenessKey: String,
        id: UUID = UUID(),
        taskID: UUID,
        day: Date,
        placementMask: Int,
        source: String,
        originTransactionID: UUID?,
        revision: Int = 1
    ) {
        self.uniquenessKey = uniquenessKey
        self.id = id
        self.taskID = taskID
        self.day = day
        self.placementMask = placementMask
        self.source = source
        self.originTransactionID = originTransactionID
        self.revision = revision
    }
}

@Model
final class PersistedPayloadRecord {
    @Attribute(.unique) var key: String
    var entityType: String
    var entityID: String
    var dateKey: Date?
    var payload: Data
    var revision: Int
    var updatedAt: Date

    init(
        key: String,
        entityType: String,
        entityID: String,
        dateKey: Date? = nil,
        payload: Data,
        revision: Int = 1,
        updatedAt: Date = .now
    ) {
        self.key = key
        self.entityType = entityType
        self.entityID = entityID
        self.dateKey = dateKey
        self.payload = payload
        self.revision = revision
        self.updatedAt = updatedAt
    }
}

@Model
final class PersistedLifecycleEventRecord {
    @Attribute(.unique) var id: UUID
    var entityType: String
    var entityID: String
    var fromState: String
    var toState: String
    var transactionID: UUID
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityType: String,
        entityID: String,
        fromState: String,
        toState: String,
        transactionID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.fromState = fromState
        self.toState = toState
        self.transactionID = transactionID
        self.createdAt = createdAt
    }
}

@Model
final class PersistedMutationTransactionRecord {
    @Attribute(.unique) var id: UUID
    var kind: String
    var createdAt: Date
    var undoState: String
    var committedAt: Date?
    var compensatesTransactionID: UUID?

    init(
        id: UUID = UUID(),
        kind: String,
        createdAt: Date = .now,
        undoState: String = "available",
        committedAt: Date? = nil,
        compensatesTransactionID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.undoState = undoState
        self.committedAt = committedAt
        self.compensatesTransactionID = compensatesTransactionID
    }
}

@Model
final class PersistedMutationOperationRecord {
    @Attribute(.unique) var id: UUID
    var transactionID: UUID
    var sequence: Int
    var entityType: String
    var entityID: String
    var field: String
    var beforeValue: Data?
    var afterValue: Data?

    init(
        id: UUID = UUID(),
        transactionID: UUID,
        sequence: Int,
        entityType: String,
        entityID: String,
        field: String = "payload",
        beforeValue: Data?,
        afterValue: Data?
    ) {
        self.id = id
        self.transactionID = transactionID
        self.sequence = sequence
        self.entityType = entityType
        self.entityID = entityID
        self.field = field
        self.beforeValue = beforeValue
        self.afterValue = afterValue
    }
}
