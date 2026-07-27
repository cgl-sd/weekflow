import Foundation

enum DiagnosticRedactor {
    static func redact(_ value: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var redacted = value.replacingOccurrences(of: home, with: "<HOME>")
        if let expression = try? NSRegularExpression(pattern: #"/Users/[^/\s]+"#) {
            let range = NSRange(redacted.startIndex..., in: redacted)
            redacted = expression.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: "<HOME>"
            )
        }
        return redacted
    }
}

struct DiagnosticSupportService: Sendable {
    private struct SupportReport: Codable {
        let formatVersion: Int
        let generatedAt: Date
        let appVersion: String
        let appBuild: String
        let bundleIdentifier: String
        let operatingSystem: String
        let storageScope: String
        let databaseBytes: Int64
        let walBytes: Int64
        let backupStatus: DatabaseBackupStatus
        let diagnostics: Diagnostics?
        let failureMarkers: [FailureMarker]
    }

    private struct Diagnostics: Codable {
        let goals: Int
        let tasks: Int
        let assignments: Int
        let transactions: Int
        let operations: Int
        let payloadBytes: Int
        let historyBytes: Int
        let cleanableTransactions: Int
    }

    private struct FailureMarker: Codable {
        let name: String
        let modifiedAt: Date?
        let bytes: Int64
    }

    func write(storage: LocalStorage, to url: URL) throws {
        let persistence = try storage.diagnostics().map {
            Diagnostics(
                goals: $0.goalCount,
                tasks: $0.taskCount,
                assignments: $0.assignmentCount,
                transactions: $0.transactionCount,
                operations: $0.operationCount,
                payloadBytes: $0.payloadByteCount,
                historyBytes: $0.historyByteCount,
                cleanableTransactions: $0.cleanableTransactionCount
            )
        }
        let report = SupportReport(
            formatVersion: 1,
            generatedAt: .now,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "development",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            storageScope: storageScope,
            databaseBytes: fileSize(storage.databaseURL),
            walBytes: fileSize(URL(fileURLWithPath: storage.databaseURL.path + "-wal")),
            backupStatus: storage.backupStatus(),
            diagnostics: persistence,
            failureMarkers: failureMarkers(in: storage.dataDirectoryURL)
        )
        let data = try JSONEncoder.weekflow.encode(report)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }

    private var storageScope: String {
#if DEBUG
        "project-local-debug"
#else
        "sandboxed-application-support"
#endif
    }

    private func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func failureMarkers(in directory: URL) -> [FailureMarker] {
        ["persistence-failure.json", "migration-failure.json"].compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return FailureMarker(
                name: name,
                modifiedAt: attributes?[.modificationDate] as? Date,
                bytes: (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            )
        }
    }
}
