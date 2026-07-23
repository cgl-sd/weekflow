import Foundation
import SwiftData
import Testing
@testable import Weekflow

/// R10: the frozen V1/V2 historical record types must be independent @Model types
/// (not reused live classes), version-suffixed, yet property-for-property identical
/// to the locked historical fingerprint. This guards against a future edit to a live
/// record class silently rewriting a frozen historical definition.
private func propertySignatures(_ structure: Set<String>) -> Set<String> {
    // Drop the "EntityName:" prefix; keep only the sorted property-list signature.
    Set(structure.map { entry in
        String(entry.drop(while: { $0 != ":" }).dropFirst())
    })
}

@Test func frozenHistoricalSchemaTypesAreIndependentFromLiveTypes() {
    // Cardinality: frozen V1 = 8 models, frozen V2 = V1 + migration audit = 9.
    #expect(WeekflowFrozenSchemaV1.models.count == 8)
    #expect(WeekflowFrozenSchemaV2.models.count == 9)

    // No-reuse: every frozen type is a distinct Swift type from the live records.
    let liveTypes: [any PersistentModel.Type] = [
        PersistenceMetadataRecord.self, PersistedGoalRecord.self, PersistedTaskRecord.self,
        PersistedTaskAssignmentRecord.self, PersistedPayloadRecord.self,
        PersistedLifecycleEventRecord.self, PersistedMutationTransactionRecord.self,
        PersistedMutationOperationRecord.self, PersistedMigrationAuditRecord.self
    ]
    let liveIDs = Set(liveTypes.map { ObjectIdentifier($0) })
    for frozen in WeekflowFrozenSchemaV2.models {
        #expect(!liveIDs.contains(ObjectIdentifier(frozen)))
    }

    // Frozen entity names are version-suffixed (independent), never the live names.
    let v1Structure = WeekflowSchemaDescriptor.structure(for: WeekflowFrozenSchemaV1.self)
    #expect(v1Structure.contains { $0.hasPrefix("PersistedGoalRecordV1:") })
    #expect(!v1Structure.contains { $0.hasPrefix("PersistedGoalRecord:") })

    // Property-for-property identical to the locked historical fingerprint.
    #expect(propertySignatures(v1Structure) == propertySignatures(WeekflowSchemaV1.modelStructure))
    let v2Structure = WeekflowSchemaDescriptor.structure(for: WeekflowFrozenSchemaV2.self)
    #expect(propertySignatures(v2Structure) == propertySignatures(WeekflowSchemaV2.modelStructure))
}
