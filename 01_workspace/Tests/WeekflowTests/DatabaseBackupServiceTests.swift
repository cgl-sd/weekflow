import Foundation
import SQLite3
import Testing
@testable import Weekflow

private func temporaryDatabase(_ name: String) throws -> (root: URL, database: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBackupTest-\(name)-\(UUID().uuidString)", isDirectory: true)
    let database = root.appendingPathComponent("Database/Weekflow.store")
    try FileManager.default.createDirectory(
        at: database.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try executeSQL("CREATE TABLE records (value TEXT NOT NULL); INSERT INTO records VALUES ('original');", at: database)
    return (root, database)
}

private func executeSQL(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        throw NSError(domain: "DatabaseBackupServiceTests", code: 1)
    }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
        throw NSError(
            domain: "DatabaseBackupServiceTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))]
        )
    }
}

private func recordValues(at url: URL) throws -> [String] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
          let database else {
        throw NSError(domain: "DatabaseBackupServiceTests", code: 3)
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, "SELECT value FROM records ORDER BY rowid", -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw NSError(domain: "DatabaseBackupServiceTests", code: 4)
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        values.append(String(cString: sqlite3_column_text(statement, 0)))
    }
    return values
}

@Test func backupAndRestoreRecoversDatabaseContent() throws {
    let fixture = try temporaryDatabase("Restore")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = DatabaseBackupService(databaseURL: fixture.database)
    let backup = try #require(try service.makeBackup())
    #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("complete").path))

    try executeSQL("INSERT INTO records VALUES ('changed');", at: fixture.database)
    #expect(try recordValues(at: fixture.database) == ["original", "changed"])
    #expect(try service.restoreLatest())
    #expect(try recordValues(at: fixture.database) == ["original"])

    let safetyRoot = fixture.root.appendingPathComponent("RestoreSafety")
    let safetyCopies = try FileManager.default.contentsOfDirectory(at: safetyRoot, includingPropertiesForKeys: nil)
    #expect(safetyCopies.count == 1)
    #expect(try recordValues(at: safetyCopies[0].appendingPathComponent("Weekflow.store")) == ["original", "changed"])
}

@Test func backupAndRestoreIncludesLegacyPlansFile() throws {
    let fixture = try temporaryDatabase("Plans")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let plans = fixture.root.appendingPathComponent("plans.json")
    try Data("original-plans".utf8).write(to: plans)
    let service = DatabaseBackupService(databaseURL: fixture.database)
    _ = try #require(try service.makeBackup())
    try Data("changed-plans".utf8).write(to: plans)
    #expect(try service.restoreLatest())
    #expect(try Data(contentsOf: plans) == Data("original-plans".utf8))
}

@Test func restoreWithoutAnyBackupReturnsFalseAndKeepsLiveStore() throws {
    let fixture = try temporaryDatabase("NoBackup")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = DatabaseBackupService(databaseURL: fixture.database)
    let original = try Data(contentsOf: fixture.database)
    #expect(service.latestBackup() == nil)
    #expect(try service.restoreLatest() == false)
    #expect(try Data(contentsOf: fixture.database) == original)
}

@Test func incompleteAndInvalidBackupsAreNeverRestored() throws {
    let fixture = try temporaryDatabase("Invalid")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let backups = fixture.root.appendingPathComponent("Backups")
    let incomplete = backups.appendingPathComponent("99999999-999999")
    try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
    try Data("not sqlite".utf8).write(to: incomplete.appendingPathComponent("Weekflow.store"))
    let service = DatabaseBackupService(databaseURL: fixture.database)
    let original = try Data(contentsOf: fixture.database)

    #expect(service.backupCount() == 0)
    #expect(service.latestBackup() == nil)
    #expect(try service.restoreLatest() == false)
    #expect(try Data(contentsOf: fixture.database) == original)

    try Data("complete".utf8).write(to: incomplete.appendingPathComponent("complete"))
    #expect(service.latestBackup() == nil)
    #expect(throws: DatabaseBackupService.BackupError.self) {
        try service.restore(from: incomplete)
    }
    #expect(try Data(contentsOf: fixture.database) == original)
}

@Test func backupRotationKeepsOnlyCompleteRecentSnapshots() throws {
    let fixture = try temporaryDatabase("Rotate")
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let service = DatabaseBackupService(databaseURL: fixture.database, maxBackups: 3)
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    for offset in 0..<6 {
        _ = try service.makeBackup(timestamp: base.addingTimeInterval(Double(offset)))
    }
    let partial = fixture.root.appendingPathComponent("Backups/.partial-test")
    try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
    #expect(service.backupCount() == 3)
    #expect(FileManager.default.fileExists(atPath: partial.path))
    #expect(try #require(service.latestBackup()).lastPathComponent.hasPrefix("20231114"))
}

@Test func makeBackupWithoutDatabaseReturnsNil() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBackupMissing-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let database = root.appendingPathComponent("Database/Weekflow.store")
    let service = DatabaseBackupService(databaseURL: database)
    #expect(try service.makeBackup() == nil)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Backups").path))
}
