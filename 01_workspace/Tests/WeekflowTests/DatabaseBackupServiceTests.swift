import Foundation
import Testing
@testable import Weekflow

private func tempDBURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBackupTest-\(name)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Weekflow.store")
}

/// 数据安全：备份后即使主库损坏，也能从最近备份恢复原内容。
@Test func backupAndRestoreRecoversDatabaseContent() throws {
    let dbURL = tempDBURL("Restore")
    let dir = dbURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let original = Data("good-database-content".utf8)
    try original.write(to: dbURL)

    let service = DatabaseBackupService(
        databaseURL: dbURL,
        backupsDirectory: dbURL.deletingLastPathComponent().appendingPathComponent("Backups"),
        maxBackups: 5
    )
    let backupDir = try #require(try service.makeBackup())
    #expect(FileManager.default.fileExists(atPath: backupDir.appendingPathComponent("Weekflow.store").path))

    // 模拟损坏：覆盖主库。
    try Data("corrupted".utf8).write(to: dbURL)
    #expect(try Data(contentsOf: dbURL) != original)

    // 从最近备份恢复原内容。
    let restored = try service.restoreLatest()
    #expect(restored)
    #expect(try Data(contentsOf: dbURL) == original)
}

/// 数据安全：无备份时 restoreLatest 返回 false（不误报成功）。
@Test func restoreWithoutAnyBackupReturnsFalse() throws {
    let dbURL = tempDBURL("NoBackup")
    let dir = dbURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("db".utf8).write(to: dbURL)

    let service = DatabaseBackupService(
        databaseURL: dbURL,
        backupsDirectory: dbURL.deletingLastPathComponent().appendingPathComponent("Backups"),
        maxBackups: 3
    )
    #expect(service.latestBackup() == nil)
    #expect(try service.restoreLatest() == false)
}

/// 数据安全：滚动备份只保留最近 N 份。
@Test func backupRotationKeepsOnlyTheMostRecentN() throws {
    let dbURL = tempDBURL("Rotate")
    let dir = dbURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data("db".utf8).write(to: dbURL)

    let service = DatabaseBackupService(
        databaseURL: dbURL,
        backupsDirectory: dbURL.deletingLastPathComponent().appendingPathComponent("Backups"),
        maxBackups: 3
    )
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    for i in 0..<6 {
        _ = try service.makeBackup(timestamp: base.addingTimeInterval(Double(i)))
    }
    #expect(service.backupCount() == 3)
    // 最近一份是时间戳最大者（2023-11-14…）。
    let latest = try #require(service.latestBackup())
    #expect(latest.lastPathComponent.hasPrefix("20231114"))
}

/// 数据安全：主库不存在时 makeBackup 返回 nil（不创建空备份）。
@Test func makeBackupWithoutDatabaseReturnsNil() throws {
    let dbURL = tempDBURL("Missing")
    let service = DatabaseBackupService(
        databaseURL: dbURL,
        backupsDirectory: dbURL.deletingLastPathComponent().appendingPathComponent("Backups"),
        maxBackups: 3
    )
    let result = try service.makeBackup()
    #expect(result == nil)
}
