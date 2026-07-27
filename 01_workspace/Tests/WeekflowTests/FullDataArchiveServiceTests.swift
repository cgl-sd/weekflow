import Foundation
import SQLite3
import Testing
@testable import Weekflow

@Test func fullDataArchiveRoundTripsAllSnapshotCollections() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowArchive-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let snapshot = WeekflowPersistenceSnapshot(
        goals: [WeeklyGoal(title: "发布 Weekflow", outcome: "稳定发布", startDate: start, endDate: start)],
        plans: [WeeklyPlan(title: "发布周", startDate: start, endDate: start)],
        channels: [TaskChannel.defaults[0]]
    )
    let url = folder.appendingPathComponent("export.weekflow.json")
    let service = FullDataArchiveService()

    try service.write(snapshot: snapshot, to: url)
    let restored = try service.read(from: url)

    #expect(restored == snapshot)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
}

@Test func fullDataArchiveRejectsDuplicateIdentitiesBeforeImport() throws {
    let goal = WeeklyGoal(title: "重复", outcome: "拒绝", startDate: .now, endDate: .now)
    let snapshot = WeekflowPersistenceSnapshot(goals: [goal, goal])

    #expect(throws: PersistenceValidationError.self) {
        try FullDataArchiveService().validate(snapshot)
    }
}

@Test func backupStatusRecordsSuccessAndLatestFailure() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBackupStatus-\(UUID().uuidString)", isDirectory: true)
    let database = root.appendingPathComponent("Database/Weekflow.store")
    try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    var sqlite: OpaquePointer?
    #expect(sqlite3_open(database.path, &sqlite) == SQLITE_OK)
    if let sqlite {
        #expect(sqlite3_exec(sqlite, "CREATE TABLE status_test (value TEXT);", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(sqlite)
    }

    let service = DatabaseBackupService(databaseURL: database)
    let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
    _ = try #require(try service.makeBackup(timestamp: timestamp))
    #expect(service.status().lastSuccessAt == timestamp)
    #expect(service.status().backupCount == 1)

    try Data("not-a-database".utf8).write(to: database, options: .atomic)
    #expect(throws: (any Error).self) {
        try service.makeBackup(timestamp: timestamp.addingTimeInterval(60))
    }
    #expect(service.status().lastSuccessAt == timestamp)
    #expect(service.status().latestFailure != nil)
}

@MainActor
@Test func fullDataImportBacksUpReplacesAtomicallyAndSurvivesRestart() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowFullImport-\(UUID().uuidString)", isDirectory: true)
    let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
    let targetRoot = root.appendingPathComponent("Target", isDirectory: true)
    let archiveURL = root.appendingPathComponent("transfer.weekflow.json")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = WeekflowStore(
        storage: LocalStorage(baseDirectory: sourceRoot),
        synchronousPersistence: true
    )
    source.goals = [WeeklyGoal(title: "归档来源", outcome: "完整恢复", startDate: .now, endDate: .now)]
    try source.exportFullDataArchive(to: archiveURL)

    let targetStorage = LocalStorage(baseDirectory: targetRoot)
    let target = WeekflowStore(storage: targetStorage, synchronousPersistence: true)
    target.goals = [WeeklyGoal(title: "导入前数据", outcome: "应被备份", startDate: .now, endDate: .now)]
    target.persistStartup()

    try await target.importFullDataArchive(from: archiveURL)
    #expect(target.goals.map(\.title) == ["归档来源"])
    #expect(target.databaseBackupStatus().backupCount == 1)

    await targetStorage.closeRepositoryForRecovery()
    let reloaded = WeekflowStore(
        storage: LocalStorage(baseDirectory: targetRoot),
        synchronousPersistence: true
    )
    #expect(reloaded.goals.map(\.title) == ["归档来源"])
}
