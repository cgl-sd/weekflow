import Foundation

// Async I/O operations, legacy migration, and health validation.

extension LocalStorage {
    // MARK: - Async startup reads

    func loadAsync() async throws -> [WeeklyGoal]? {
        try await readOptionalAsync { try $0.loadGoals() }
    }

    func loadPlansAsync() async throws -> [WeeklyPlan]? {
        if let stored = try await readOptionalAsync({ try $0.loadPlans() }) {
            return stored
        }
        guard fileManager.fileExists(atPath: legacyPlansURL.path) else { return nil }
        let data = try Data(contentsOf: legacyPlansURL)
        let plans = try JSONDecoder.weekflow.decode([WeeklyPlan].self, from: data)
        try await writeAsync { try $0.savePlans(plans, kind: .migration) }
        return plans
    }

    func loadChannelsAsync() async throws -> [TaskChannel]? {
        try await readOptionalAsync { try $0.loadChannels() }
    }

    func loadCalendarEventsAsync() async throws -> [CalendarEvent]? {
        try await readOptionalAsync { try $0.loadCalendarEvents() }
    }

    func loadDailyPlanningStatesAsync() async throws -> [DailyPlanningState]? {
        try await readOptionalAsync { try $0.loadDailyPlanningStates() }
    }

    func loadFocusRecordsAsync() async throws -> [FocusRecord]? {
        try await readOptionalAsync { try $0.loadFocusRecords() }
    }

    func loadDailySummariesAsync() async throws -> [DailySummary]? {
        try await readOptionalAsync { try $0.loadDailySummaries() }
    }

    func loadActiveTimerSessionAsync() async throws -> TaskTimerSession? {
        try await readOptionalAsync { try $0.loadActiveTimerSession() }
    }

    func pendingAutomaticDistributionChangesAsync() async throws
        -> [PersistedAutomaticDistributionChange] {
        try await readAsync { try $0.pendingAutomaticDistributionChanges() } ?? []
    }

    @discardableResult
    func normalizeAllPayloadsIfNeededAsync(marker: String) async throws -> Int {
        try await writeAsync { try $0.normalizeAllPayloadsIfNeeded(marker: marker) }
    }

    // MARK: - Async writes (non-blocking on MainActor)

    /// Async variant of `applyGoalChanges` that suspends instead of blocking.
    func applyGoalChangesAsync(
        _ changes: PersistenceGoalChangeSet,
        kind: PersistenceMutationKind = .userEdit
    ) async throws {
        guard !changes.isEmpty else { return }
        try await writeAsync { try $0.applyGoalChanges(changes, kind: kind) }
    }

    func saveChannelsAsync(_ channels: [TaskChannel]) async throws {
        try await writeAsync { try $0.saveChannels(channels, kind: .userEdit) }
    }

    func savePlansAsync(_ plans: [WeeklyPlan]) async throws {
        try await writeAsync { try $0.savePlans(plans, kind: .userEdit) }
    }

    func saveCalendarEventsAsync(_ events: [CalendarEvent]) async throws {
        try await writeAsync { try $0.saveCalendarEvents(events, kind: .userEdit) }
    }

    func saveDailyPlanningStatesAsync(_ states: [DailyPlanningState]) async throws {
        try await writeAsync { try $0.saveDailyPlanningStates(states, kind: .userEdit) }
    }

    func saveFocusRecordsAsync(_ records: [FocusRecord]) async throws {
        try await writeAsync { try $0.saveFocusRecords(records, kind: .userEdit) }
    }

    func saveDailySummariesAsync(_ summaries: [DailySummary]) async throws {
        try await writeAsync { try $0.saveDailySummaries(summaries, kind: .userEdit) }
    }

    func saveActiveTimerSessionAsync(_ session: TaskTimerSession?) async throws {
        try await writeAsync { try $0.saveActiveTimerSession(session) }
    }

    func upsertCalendarEventAsync(_ event: CalendarEvent) async throws {
        try await writeAsync { try $0.upsertCalendarEvent(event, kind: .userEdit) }
    }

    func deleteCalendarEventAsync(id: String) async throws {
        try await writeAsync { try $0.deleteCalendarEvent(id: id, kind: .userEdit) }
    }

    func upsertFocusRecordAsync(_ record: FocusRecord) async throws {
        try await writeAsync { try $0.upsertFocusRecord(record, kind: .userEdit) }
    }

    func upsertDailySummaryAsync(_ summary: DailySummary) async throws {
        try await writeAsync { try $0.upsertDailySummary(summary, kind: .userEdit) }
    }

    func upsertDailyPlanningStateAsync(_ state: DailyPlanningState) async throws {
        try await writeAsync { try $0.upsertDailyPlanningState(state, kind: .userEdit) }
    }

    func upsertDailyPlanAndCalendarEventAsync(
        state: DailyPlanningState,
        event: CalendarEvent
    ) async throws {
        try await writeAsync {
            try $0.upsertDailyPlanAndCalendarEvent(
                state: state,
                event: event,
                kind: .userEdit
            )
        }
    }

    func saveApplicationSnapshotAsync(
        _ snapshot: WeekflowPersistenceSnapshot,
        kind: PersistenceMutationKind = .userEdit
    ) async throws {
        try await writeAsync { try $0.saveApplicationSnapshot(snapshot, kind: kind) }
    }

    func saveDailyPlanAndCalendarEventsAsync(
        states: [DailyPlanningState],
        events: [CalendarEvent]
    ) async throws {
        try await writeAsync {
            try $0.saveDailyPlanAndCalendarEvents(
                states: states,
                events: events,
                kind: .userEdit
            )
        }
    }

    func saveGoalChangesAndActiveTimerAsync(
        changes: PersistenceGoalChangeSet,
        session: TaskTimerSession?,
        kind: PersistenceMutationKind = .userEdit
    ) async throws {
        try await writeAsync {
            try $0.saveGoalChangesAndActiveTimer(
                changes: changes,
                session: session,
                kind: kind
            )
        }
    }

    func commitAutomaticDistributionAsync(transactionID: UUID) async throws {
        try await writeAsync { try $0.commitAutomaticDistribution(transactionID: transactionID) }
    }

    // MARK: - Async private helpers

    private func readAsync<Result: Sendable>(
        _ operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) async throws -> Result? {
        if let initializationError { throw initializationError }
        if !fileManager.fileExists(atPath: databaseURL.path) {
            guard legacyFilesExist else { return nil }
            try migrateLegacyJSON()
        }
        try ensurePreMigrationBackup()
        return try await PersistenceActorBridge.runAsync(on: persistenceActor, operation)
    }

    private func readOptionalAsync<Result: Sendable>(
        _ operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result?
    ) async throws -> Result? {
        if let initializationError { throw initializationError }
        if !fileManager.fileExists(atPath: databaseURL.path) {
            guard legacyFilesExist else { return nil }
            try migrateLegacyJSON()
        }
        try ensurePreMigrationBackup()
        return try await PersistenceActorBridge.runAsync(on: persistenceActor, operation)
    }

    /// Async write path – suspends the calling task, never blocks the thread.
    private func writeAsync<Result: Sendable>(
        _ operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) async throws -> Result {
        if let initializationError { throw initializationError }
        if !fileManager.fileExists(atPath: databaseURL.path), legacyFilesExist {
            try migrateLegacyJSON()
        }
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: databaseURL.path) {
            try ensurePreMigrationBackup()
        }
        return try await PersistenceActorBridge.runAsync(on: persistenceActor, operation)
    }

    // MARK: - Legacy migration

    var legacyFilesExist: Bool {
        legacyURLs.contains { fileManager.fileExists(atPath: $0.path) }
    }

    /// Creates a pre-migration backup with versioned path (P1-3 fix).
    /// Future migrations (V2→V3, etc.) will create separate backup directories.
    func ensurePreMigrationBackup() throws {
        let currentVersion = SwiftDataPersistenceRepository.schemaVersion
        let previousVersion = currentVersion - 1
        guard previousVersion >= 1 else { return }  // No backup needed for V1

        let backupDirectory = directoryURL
            .appendingPathComponent("MigrationBackups", isDirectory: true)
            .appendingPathComponent("v\(previousVersion)-to-v\(currentVersion)", isDirectory: true)
        let completionMarker = backupDirectory.appendingPathComponent("complete")
        guard !fileManager.fileExists(atPath: completionMarker.path) else { return }

        let temporary = directoryURL.appendingPathComponent(
            "MigrationBackup-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
            let family = try fileManager.contentsOfDirectory(
                at: dataDirectoryURL,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(databaseURL.lastPathComponent) }
            for source in family {
                try fileManager.copyItem(
                    at: source,
                    to: temporary.appendingPathComponent(source.lastPathComponent)
                )
            }
            // Versioned manifest (P1-3 fix)
            let manifest = """
            fromVersion=\(previousVersion)
            toVersion=\(currentVersion)
            createdAt=\(ISO8601DateFormatter().string(from: .now))
            databaseFiles=\(family.map(\.lastPathComponent).joined(separator: ","))
            """
            try Data(manifest.utf8).write(
                to: temporary.appendingPathComponent("complete"),
                options: .atomic
            )
            try fileManager.createDirectory(
                at: backupDirectory.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: temporary, to: backupDirectory)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    var legacyURLs: [URL] {
        [
            legacyGoalsURL,
            legacyChannelsURL,
            legacyCalendarEventsURL,
            legacyDailyPlanningStatesURL,
            legacyFocusRecordsURL,
            legacyDailySummariesURL
        ]
    }

    func migrateLegacyJSON() throws {
        let snapshot = try loadLegacySnapshot()
        let temporaryDirectory = directoryURL.appendingPathComponent(
            "Weekflow-import-\(UUID().uuidString)",
            isDirectory: true
        )
        let temporaryURL = temporaryDirectory.appendingPathComponent("Weekflow.store")

        func buildTemporaryStore() throws {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            let temporaryActor = PersistenceActor(storeURL: temporaryURL)
            try PersistenceActorBridge.run(on: temporaryActor) {
                try $0.importLegacySnapshot(snapshot)
            }
            let migratedGoals = try PersistenceActorBridge.run(on: temporaryActor) { try $0.loadGoals() ?? [] }
            let migratedChannels = try PersistenceActorBridge.run(on: temporaryActor) { try $0.loadChannels() ?? [] }
            let migratedCalendarEvents = try PersistenceActorBridge.run(on: temporaryActor) { try $0.loadCalendarEvents() ?? [] }
            let migratedDailyPlans = try PersistenceActorBridge.run(on: temporaryActor) { try $0.loadDailyPlanningStates() ?? [] }
            let migratedFocus = try PersistenceActorBridge.run(on: temporaryActor) { try $0.loadFocusRecords() ?? [] }
            let migratedDailyReviews = try PersistenceActorBridge.run(on: temporaryActor) { try $0.loadDailySummaries() ?? [] }
            let migrated = WeekflowPersistenceSnapshot(
                goals: migratedGoals,
                channels: migratedChannels,
                calendarEvents: migratedCalendarEvents,
                dailyPlanningStates: migratedDailyPlans,
                focusRecords: migratedFocus,
                dailySummaries: migratedDailyReviews
            )
            guard migrated.canonicalized == snapshot.canonicalized else {
                throw LocalStorageMigrationError.validationFailed
            }
        }

        do {
            try buildTemporaryStore()
            // Complete the recoverable copy before switching the live store.
            // Legacy source files themselves are never changed or removed.
            try createReadOnlyLegacyBackup()
            // The complete SQLite family lives in one directory, so the final
            // rename is atomic. A crash cannot expose a half-moved WAL family.
            try fileManager.moveItem(at: temporaryDirectory, to: dataDirectoryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    func loadLegacySnapshot() throws -> WeekflowPersistenceSnapshot {
        WeekflowPersistenceSnapshot(
            goals: try decodeLegacy([WeeklyGoal].self, at: legacyGoalsURL) ?? [],
            channels: try decodeLegacy([TaskChannel].self, at: legacyChannelsURL) ?? [],
            calendarEvents: try decodeLegacy([CalendarEvent].self, at: legacyCalendarEventsURL) ?? [],
            dailyPlanningStates: try decodeLegacy([DailyPlanningState].self, at: legacyDailyPlanningStatesURL) ?? [],
            focusRecords: try decodeLegacy([FocusRecord].self, at: legacyFocusRecordsURL) ?? [],
            dailySummaries: try decodeLegacy([DailySummary].self, at: legacyDailySummariesURL) ?? []
        )
    }

    func decodeLegacy<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.weekflow.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    func createReadOnlyLegacyBackup() throws {
        let backupDirectory = directoryURL.appendingPathComponent("LegacyJSONBackup", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let allJSONFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        for sourceURL in allJSONFiles {
            let destinationURL = backupDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if !fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o444))],
                    ofItemAtPath: destinationURL.path
                )
            }
        }
        let manifest = "schemaVersion=\(SwiftDataPersistenceRepository.schemaVersion)\nmigratedAt=\(ISO8601DateFormatter().string(from: .now))\n"
        let manifestURL = backupDirectory.appendingPathComponent("migration.txt")
        if !fileManager.fileExists(atPath: manifestURL.path) {
            try Data(manifest.utf8).write(to: manifestURL, options: .atomic)
        }
    }

    // MARK: - Health validation

    static func validateStorageHealth(
        fileManager: FileManager,
        rootDirectory: URL,
        dataDirectory: URL
    ) -> Error? {
        do {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw LocalStorageHealthError.expectedDirectory(rootDirectory)
                }
            } else {
                try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            }

            var createdDataDirectory = false
            if fileManager.fileExists(atPath: dataDirectory.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw LocalStorageHealthError.expectedDirectory(dataDirectory)
                }
            } else {
                try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: false)
                createdDataDirectory = true
            }

            let probe = dataDirectory.appendingPathComponent(".weekflow-health-\(UUID().uuidString)")
            defer {
                try? fileManager.removeItem(at: probe)
                if createdDataDirectory { try? fileManager.removeItem(at: dataDirectory) }
            }
            try Data("write-probe".utf8).write(to: probe, options: [.atomic])
            try Data("replace-probe".utf8).write(to: probe, options: [.atomic])
            guard try Data(contentsOf: probe) == Data("replace-probe".utf8) else {
                throw LocalStorageHealthError.atomicReplacementFailed(dataDirectory)
            }
            return nil
        } catch {
            return error
        }
    }
}

// MARK: - Error types

enum LocalStorageMigrationError: LocalizedError {
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .validationFailed: "旧数据导入后的数量或关联校验失败"
        }
    }
}

enum LocalStorageHealthError: LocalizedError {
    case expectedDirectory(URL)
    case atomicReplacementFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .expectedDirectory(url):
            "本地存储路径不是目录：\(url.path)"
        case let .atomicReplacementFailed(url):
            "本地存储目录无法完成原子替换：\(url.path)"
        }
    }
}

// MARK: - JSON coding helpers

extension JSONEncoder {
    static var weekflow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var weekflow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
