import Foundation
import SwiftData
import Testing
@testable import Weekflow

/// R11 (fixture foundation): the frozen V1/V2 historical schemas must be real,
/// instantiable SwiftData schemas that can persist and reload historical records.
/// These synthetic historical fixtures are the inputs a V1→V2→V3 staged migration
/// is validated against. Each runs in an isolated temporary ModelContainer and does
/// not touch the live store.
private func historicalFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowHistorical-\(name)-\(UUID().uuidString)", isDirectory: true)
}

@Test func frozenV1SchemaPersistsAndReloadsHistoricalGoalRecord() throws {
    let folder = historicalFolder("V1")
    defer { try? FileManager.default.removeItem(at: folder) }
    let schema = Schema(versionedSchema: WeekflowFrozenSchemaV1.self)
    let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("Weekflow.store"))
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let id = UUID()
    context.insert(PersistedGoalRecordV1(
        id: id,
        payload: Data("v1-goal-payload".utf8),
        periodStart: .now,
        periodEnd: .now,
        channelID: nil,
        lifecycleState: PersistedLifecycleState.active.rawValue,
        revision: 1,
        updatedAt: .now
    ))
    try context.save()

    // Reopen fresh to prove the historical record round-trips on disk.
    let reopened = try ModelContainer(for: schema, configurations: [config])
    let fetched = try ModelContext(reopened).fetch(FetchDescriptor<PersistedGoalRecordV1>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.id == id)
    #expect(fetched.first?.payload == Data("v1-goal-payload".utf8))
}

@Test func frozenV2SchemaPersistsHistoricalMigrationAuditRecord() throws {
    let folder = historicalFolder("V2")
    defer { try? FileManager.default.removeItem(at: folder) }
    let schema = Schema(versionedSchema: WeekflowFrozenSchemaV2.self)
    let config = ModelConfiguration(schema: schema, url: folder.appendingPathComponent("Weekflow.store"))
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    // V2 = V1 records + the migration-audit record.
    context.insert(PersistedGoalRecordV1(
        id: UUID(), payload: Data("v2-goal".utf8), periodStart: .now, periodEnd: .now,
        channelID: nil, lifecycleState: PersistedLifecycleState.active.rawValue,
        revision: 1, updatedAt: .now
    ))
    context.insert(PersistedMigrationAuditRecordV2(
        fromVersion: 1, toVersion: 2, result: "success"
    ))
    try context.save()

    let reopened = try ModelContainer(for: schema, configurations: [config])
    let ctx = ModelContext(reopened)
    #expect(try ctx.fetch(FetchDescriptor<PersistedGoalRecordV1>()).count == 1)
    let audits = try ctx.fetch(FetchDescriptor<PersistedMigrationAuditRecordV2>())
    #expect(audits.count == 1)
    #expect(audits.first?.fromVersion == 1)
    #expect(audits.first?.toVersion == 2)
}
