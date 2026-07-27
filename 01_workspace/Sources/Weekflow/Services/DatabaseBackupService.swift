import Foundation
import SQLite3

struct DatabaseBackupStatus: Codable, Equatable, Sendable {
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var latestFailure: String?
    var backupCount: Int

    static let empty = DatabaseBackupStatus(
        lastAttemptAt: nil,
        lastSuccessAt: nil,
        latestFailure: nil,
        backupCount: 0
    )
}

/// Creates validated SQLite snapshots and restores them without discarding the
/// current store before a replacement is known to be usable.
struct DatabaseBackupService: @unchecked Sendable {
    enum BackupError: LocalizedError {
        case checkpointFailed(Int32)
        case missingStore(URL)
        case invalidStore(URL, String)

        var errorDescription: String? {
            switch self {
            case let .checkpointFailed(code):
                "SQLite WAL 检查点失败（错误码 \(code)）"
            case let .missingStore(url):
                "备份中缺少数据库文件：\(url.path)"
            case let .invalidStore(url, detail):
                "数据库完整性校验失败：\(url.path)（\(detail)）"
            }
        }
    }

    let databaseURL: URL
    let backupsDirectory: URL
    let maxBackups: Int
    let maxRestoreSafetyCopies: Int
    private let fileManager: FileManager

    private static let completionMarkerName = "complete"
    private static let statusFileName = "backup-status.json"

    init(
        databaseURL: URL,
        backupsDirectory: URL? = nil,
        maxBackups: Int = 5,
        maxRestoreSafetyCopies: Int = 3,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.backupsDirectory = backupsDirectory ?? databaseURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        self.maxBackups = max(1, maxBackups)
        self.maxRestoreSafetyCopies = max(1, maxRestoreSafetyCopies)
        self.fileManager = fileManager
    }

    private var walURL: URL { URL(fileURLWithPath: databaseURL.path + "-wal") }
    private var shmURL: URL { URL(fileURLWithPath: databaseURL.path + "-shm") }
    private var applicationDataDirectory: URL {
        databaseURL.deletingLastPathComponent().deletingLastPathComponent()
    }
    private var statusURL: URL {
        applicationDataDirectory.appendingPathComponent(Self.statusFileName)
    }
    private var legacyPlansURL: URL {
        applicationDataDirectory.appendingPathComponent("plans.json")
    }

    /// Builds the snapshot in a hidden staging directory. Only a validated,
    /// completed snapshot is atomically renamed into the discoverable set.
    @discardableResult
    func makeBackup(timestamp: Date = .now) throws -> URL? {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return nil }
        do {
            try createPrivateDirectory(at: backupsDirectory)
            try checkpointWAL()
            let temporary = backupsDirectory.appendingPathComponent(
                ".partial-\(UUID().uuidString)",
                isDirectory: true
            )
            try createPrivateDirectory(at: temporary)
            do {
                let stagedStore = temporary.appendingPathComponent(databaseURL.lastPathComponent)
                try fileManager.copyItem(at: databaseURL, to: stagedStore)
                try validateSQLiteStore(at: stagedStore)
                try setPrivateFilePermissions(at: stagedStore)

                if fileManager.fileExists(atPath: legacyPlansURL.path) {
                    let stagedPlans = temporary.appendingPathComponent(legacyPlansURL.lastPathComponent)
                    try fileManager.copyItem(at: legacyPlansURL, to: stagedPlans)
                    try setPrivateFilePermissions(at: stagedPlans)
                }

                let marker = temporary.appendingPathComponent(Self.completionMarkerName)
                let manifest = "formatVersion=1\ncreatedAt=\(ISO8601DateFormatter().string(from: timestamp))\n"
                try Data(manifest.utf8).write(to: marker, options: .atomic)
                try setPrivateFilePermissions(at: marker)

                let backupDirectory = nextBackupDirectory(timestamp: timestamp)
                try fileManager.moveItem(at: temporary, to: backupDirectory)
                try rotate()
                recordStatus(
                    DatabaseBackupStatus(
                        lastAttemptAt: timestamp,
                        lastSuccessAt: timestamp,
                        latestFailure: nil,
                        backupCount: backupCount()
                    )
                )
                return backupDirectory
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        } catch {
            let previous = status()
            recordStatus(
                DatabaseBackupStatus(
                    lastAttemptAt: timestamp,
                    lastSuccessAt: previous.lastSuccessAt,
                    latestFailure: error.localizedDescription,
                    backupCount: backupCount()
                )
            )
            throw error
        }
    }

    func status() -> DatabaseBackupStatus {
        guard let data = try? Data(contentsOf: statusURL),
              var decoded = try? JSONDecoder.weekflow.decode(DatabaseBackupStatus.self, from: data)
        else {
            var fallback = DatabaseBackupStatus.empty
            fallback.backupCount = backupCount()
            return fallback
        }
        decoded.backupCount = backupCount()
        return decoded
    }

    private func recordStatus(_ status: DatabaseBackupStatus) {
        do {
            try createPrivateDirectory(at: applicationDataDirectory)
            let data = try JSONEncoder.weekflow.encode(status)
            try data.write(to: statusURL, options: .atomic)
            try setPrivateFilePermissions(at: statusURL)
        } catch {
            NSLog("[Weekflow] 无法保存备份状态: %@", DiagnosticRedactor.redact(error.localizedDescription))
        }
    }

    private func checkpointWAL() throws {
        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READWRITE, nil)
        guard openResult == SQLITE_OK, let handle = db else {
            if let db { sqlite3_close(db) }
            throw BackupError.checkpointFailed(openResult)
        }
        defer { sqlite3_close(handle) }
        let checkpointResult = sqlite3_wal_checkpoint_v2(
            handle,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            nil,
            nil
        )
        guard checkpointResult == SQLITE_OK else {
            throw BackupError.checkpointFailed(checkpointResult)
        }
    }

    func latestBackup() -> URL? {
        completeBackups().first
    }

    func backupCount() -> Int {
        completeBackups().count
    }

    /// Returns only complete, integrity-checked snapshots, newest first. Recovery
    /// UI must never expose partial directories or an invalid SQLite store.
    func availableBackups() -> [URL] {
        completeBackups()
    }

    /// Preflights and stages the replacement before touching the current store.
    /// The previous live SQLite family is retained under RestoreSafety.
    func restore(from backupDirectory: URL) throws {
        let backedUpStore = backupDirectory.appendingPathComponent(databaseURL.lastPathComponent)
        guard isCompleteBackup(backupDirectory) else {
            throw BackupError.missingStore(backedUpStore)
        }
        try validateSQLiteStore(at: backedUpStore)
        try createPrivateDirectory(at: databaseURL.deletingLastPathComponent())

        let stagingDirectory = databaseURL.deletingLastPathComponent().appendingPathComponent(
            ".restore-stage-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        try createPrivateDirectory(at: stagingDirectory)
        let stagedStore = stagingDirectory.appendingPathComponent(databaseURL.lastPathComponent)
        try fileManager.copyItem(at: backedUpStore, to: stagedStore)
        try validateSQLiteStore(at: stagedStore)
        try setPrivateFilePermissions(at: stagedStore)

        let backedUpPlans = backupDirectory.appendingPathComponent(legacyPlansURL.lastPathComponent)
        let stagedPlans = stagingDirectory.appendingPathComponent(legacyPlansURL.lastPathComponent)
        if fileManager.fileExists(atPath: backedUpPlans.path) {
            try fileManager.copyItem(at: backedUpPlans, to: stagedPlans)
            try setPrivateFilePermissions(at: stagedPlans)
        }

        let safetyDirectory = try preserveCurrentStoreFamily()
        do {
            if fileManager.fileExists(atPath: databaseURL.path) {
                _ = try fileManager.replaceItemAt(databaseURL, withItemAt: stagedStore)
            } else {
                try fileManager.moveItem(at: stagedStore, to: databaseURL)
            }
            for sidecar in [walURL, shmURL] where fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
            if fileManager.fileExists(atPath: stagedPlans.path) {
                if fileManager.fileExists(atPath: legacyPlansURL.path) {
                    _ = try fileManager.replaceItemAt(legacyPlansURL, withItemAt: stagedPlans)
                } else {
                    try fileManager.moveItem(at: stagedPlans, to: legacyPlansURL)
                }
            }
            try validateSQLiteStore(at: databaseURL)
            if let safetyDirectory {
                let marker = safetyDirectory.appendingPathComponent(Self.completionMarkerName)
                try Data("restoreSafetyVersion=1\n".utf8).write(to: marker, options: .atomic)
                try setPrivateFilePermissions(at: marker)
            }
            try rotateRestoreSafetyCopies()
        } catch {
            if let safetyDirectory {
                try? restoreSafetyCopy(from: safetyDirectory)
            }
            try? rotateRestoreSafetyCopies()
            throw error
        }
    }

    @discardableResult
    func restoreLatest() throws -> Bool {
        guard let latest = latestBackup() else { return false }
        try restore(from: latest)
        return true
    }

    private func preserveCurrentStoreFamily() throws -> URL? {
        let existingFiles = [databaseURL, walURL, shmURL, legacyPlansURL]
            .filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingFiles.isEmpty else { return nil }

        let root = applicationDataDirectory.appendingPathComponent("RestoreSafety", isDirectory: true)
        try createPrivateDirectory(at: root)
        let directory = root.appendingPathComponent(
            "\(Self.timestampFormatter.string(from: .now))-\(UUID().uuidString)",
            isDirectory: true
        )
        try createPrivateDirectory(at: directory)
        do {
            for source in existingFiles {
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                try fileManager.copyItem(at: source, to: destination)
                try setPrivateFilePermissions(at: destination)
            }
            return directory
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    private func restoreSafetyCopy(from directory: URL) throws {
        for destination in [databaseURL, walURL, shmURL, legacyPlansURL] {
            let source = directory.appendingPathComponent(destination.lastPathComponent)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let rollback = destination.deletingLastPathComponent().appendingPathComponent(
                ".rollback-\(UUID().uuidString)"
            )
            try fileManager.copyItem(at: source, to: rollback)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: rollback)
            } else {
                try fileManager.moveItem(at: rollback, to: destination)
            }
        }
    }

    /// Restore safety copies contain a full SQLite family and can otherwise grow
    /// without bound after repeated recovery attempts. Keep the newest bounded
    /// set, including an incomplete directory left by a failed attempt.
    private func rotateRestoreSafetyCopies() throws {
        let root = applicationDataDirectory.appendingPathComponent("RestoreSafety", isDirectory: true)
        guard let directories = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let ordered = directories.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in ordered.dropFirst(maxRestoreSafetyCopies) {
            try fileManager.removeItem(at: old)
        }
    }

    private func validateSQLiteStore(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw BackupError.missingStore(url)
        }
        var db: OpaquePointer?
        // A copied SwiftData store remains in WAL journal mode even after a
        // successful checkpoint. Ordinary read-only open may still try to create
        // `-shm` beside the snapshot and incorrectly report "unable to open".
        // Immutable URI mode guarantees validation is side-effect free and reads
        // the already-checkpointed main database exactly as it will be restored.
        let uri = "file:\(url.path)?immutable=1"
        let result = sqlite3_open_v2(
            uri,
            &db,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )
        guard result == SQLITE_OK, let handle = db else {
            let detail = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed: \(result)"
            if let db { sqlite3_close(db) }
            throw BackupError.invalidStore(url, detail)
        }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA quick_check;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw BackupError.invalidStore(url, String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0),
              String(cString: value) == "ok" else {
            throw BackupError.invalidStore(url, String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func completeBackups() -> [URL] {
        guard let directories = try? fileManager.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return directories
            .filter(isCompleteBackup)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func isCompleteBackup(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        guard fileManager.fileExists(
            atPath: directory.appendingPathComponent(Self.completionMarkerName).path
        ) && fileManager.fileExists(
            atPath: directory.appendingPathComponent(databaseURL.lastPathComponent).path
        ) else { return false }
        return (try? validateSQLiteStore(
            at: directory.appendingPathComponent(databaseURL.lastPathComponent)
        )) != nil
    }

    private func rotate() throws {
        for old in completeBackups().dropFirst(maxBackups) {
            try fileManager.removeItem(at: old)
        }
    }

    private func nextBackupDirectory(timestamp: Date) -> URL {
        let stamp = Self.timestampFormatter.string(from: timestamp)
        var candidate = backupsDirectory.appendingPathComponent(stamp, isDirectory: true)
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = backupsDirectory.appendingPathComponent("\(stamp)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    private func createPrivateDirectory(at url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
    }

    private func setPrivateFilePermissions(at url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
