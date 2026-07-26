import Foundation
import SQLite3

/// 数据安全：SQLite 库的滚动备份与完整性恢复。
///
/// 策略：每次成功加载后做一次备份（此时库处于已知良好状态），保留最近 `maxBackups`
/// 份；当加载失败（库损坏）时，可从最近一份良好备份恢复。备份拷贝 SQLite 的
/// 主库 + WAL + SHM 三个文件（一起拷贝才构成一致快照）。
///
/// 这是本地优先应用最重要的一道数据安全防线：库文件损坏或误删时，用户数据仍可
/// 从最近备份找回，而不是永久丢失。
/// `@unchecked Sendable`：`FileManager` 在所用操作上线程安全（与 `LocalStorage` 同理）。
struct DatabaseBackupService: @unchecked Sendable {
    let databaseURL: URL
    let backupsDirectory: URL
    let maxBackups: Int
    private let fileManager: FileManager

    init(databaseURL: URL, backupsDirectory: URL? = nil, maxBackups: Int = 5, fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        // 默认把备份放在 Database 目录的“同级”（Weekflow/Backups），而不是 Database
        // 内部——避免在 SwiftData 的数据库目录里多放子目录而干扰其存储加载。测试可传入
        // 独立的 backupsDirectory 以保证隔离。
        self.backupsDirectory = backupsDirectory ?? databaseURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        self.maxBackups = max(1, maxBackups)
        self.fileManager = fileManager
    }

    /// SQLite 的 WAL / SHM 伴随文件路径。
    private var walURL: URL { URL(fileURLWithPath: databaseURL.path + "-wal") }
    private var shmURL: URL { URL(fileURLWithPath: databaseURL.path + "-shm") }
    private var legacyPlansURL: URL {
        databaseURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plans.json")
    }

    /// 做一次带时间戳的备份并轮转，返回备份目录；主库不存在时返回 nil。
    /// 先把 WAL 检查点回主库（得到一致的单一文件快照），再只拷贝主库——避免拷贝
    /// 正在被 SQLite 内存映射的 WAL/SHM 而干扰打开中的数据库。
    @discardableResult
    func makeBackup(timestamp: Date = .now) throws -> URL? {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        let stamp = Self.timestampFormatter.string(from: timestamp)
        var backupDir = backupsDirectory.appendingPathComponent(stamp, isDirectory: true)
        // 同一秒内重复备份时追加后缀，避免覆盖。
        var suffix = 1
        while fileManager.fileExists(atPath: backupDir.path) {
            backupDir = backupsDirectory.appendingPathComponent("\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
        checkpointWAL()
        try fileManager.copyItem(at: databaseURL, to: backupDir.appendingPathComponent(databaseURL.lastPathComponent))
        if fileManager.fileExists(atPath: legacyPlansURL.path) {
            try fileManager.copyItem(
                at: legacyPlansURL,
                to: backupDir.appendingPathComponent(legacyPlansURL.lastPathComponent)
            )
        }
        try rotate()
        return backupDir
    }

    /// 通过一个独立的 SQLite 连接执行 WAL 检查点（TRUNCATE），把 WAL 数据全部落回
    /// 主库并清空 WAL。WAL 模式允许并发连接，此操作不会破坏打开中的库。
    private func checkpointWAL() {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let handle = db else {
            if let db { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(handle) }
        sqlite3_wal_checkpoint_v2(handle, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    /// 最近一份备份目录（按时间戳字典序，时间戳格式保证其即时间序）。
    func latestBackup() -> URL? {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil
        ) else { return nil }
        return dirs
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    /// 现有备份数量。
    func backupCount() -> Int {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil
        ) else { return 0 }
        return dirs.filter { $0.hasDirectoryPath }.count
    }

    /// 从指定备份恢复：移除当前主库三件套，再从备份拷回单一主库文件。
    func restore(from backupDir: URL) throws {
        for file in [databaseURL, walURL, shmURL] {
            try? fileManager.removeItem(at: file)
        }
        let backedUpStore = backupDir.appendingPathComponent(databaseURL.lastPathComponent)
        if fileManager.fileExists(atPath: backedUpStore.path) {
            try fileManager.copyItem(at: backedUpStore, to: databaseURL)
        }
        let backedUpPlans = backupDir.appendingPathComponent(legacyPlansURL.lastPathComponent)
        if fileManager.fileExists(atPath: backedUpPlans.path) {
            if fileManager.fileExists(atPath: legacyPlansURL.path) {
                try fileManager.removeItem(at: legacyPlansURL)
            }
            try fileManager.copyItem(at: backedUpPlans, to: legacyPlansURL)
        }
    }

    /// 从最近备份恢复；无备份返回 false。
    @discardableResult
    func restoreLatest() throws -> Bool {
        guard let latest = latestBackup() else { return false }
        try restore(from: latest)
        return true
    }

    /// 轮转：按时间戳保留最近 maxBackups 份，删除更旧的。
    private func rotate() throws {
        guard let dirs = try? fileManager.contentsOfDirectory(
            at: backupsDirectory, includingPropertiesForKeys: nil
        ) else { return }
        let backups = dirs
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(maxBackups) {
            try? fileManager.removeItem(at: old)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
