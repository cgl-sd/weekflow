import Foundation

/// Persistence facade used by WeekflowStore.
///
/// New writes go to the normalized SwiftData store. Legacy JSON files are read
/// only during the first migration and are retained as a recoverable backup.
///
/// Marked `@unchecked Sendable` because `FileManager` is thread-safe for the
/// operations used here, and `PersistenceActor` is a proper actor.
struct LocalStorage: @unchecked Sendable {
    let directoryURL: URL
    let dataDirectoryURL: URL
    let databaseURL: URL

    private let fileManager: FileManager
    private let legacyGoalsURL: URL
    private let legacyChannelsURL: URL
    private let legacyCalendarEventsURL: URL
    private let legacyDailyPlanningStatesURL: URL
    private let legacyFocusRecordsURL: URL
    private let legacyDailySummariesURL: URL
    private let persistenceActor: PersistenceActor
    private let initializationError: Error?
    private var preload: LocalStoragePreloadCache?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        faultInjector: PersistenceFaultInjector? = nil
    ) {
        let folder = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Weekflow", isDirectory: true)
        self.fileManager = fileManager
        directoryURL = folder
        dataDirectoryURL = folder.appendingPathComponent("Database", isDirectory: true)
        databaseURL = dataDirectoryURL.appendingPathComponent("Weekflow.store")
        legacyGoalsURL = folder.appendingPathComponent("weekflow.json")
        legacyChannelsURL = folder.appendingPathComponent("channels.json")
        legacyCalendarEventsURL = folder.appendingPathComponent("calendar-events.json")
        legacyDailyPlanningStatesURL = folder.appendingPathComponent("daily-planning-states.json")
        legacyFocusRecordsURL = folder.appendingPathComponent("focus-records.json")
        legacyDailySummariesURL = folder.appendingPathComponent("daily-summaries.json")
        persistenceActor = PersistenceActor(storeURL: databaseURL, faultInjector: faultInjector)
        preload = nil
        initializationError = Self.validateStorageHealth(
            fileManager: fileManager,
            rootDirectory: folder,
            dataDirectory: dataDirectoryURL
        )
    }

    static func developmentFixtures(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) -> LocalStorage {
        let root = rootDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Weekflow", isDirectory: true)
        return LocalStorage(
            fileManager: fileManager,
            baseDirectory: root.appendingPathComponent("DevelopmentFixtures", isDirectory: true)
        )
    }

    /// 数据安全：应用启动、打开数据库之前，对上一次会话的库做一次滚动备份。
    /// 应在创建 Store 之前调用——此时数据库处于静止状态（上一会话关闭时已做 WAL
    /// 检查点），备份只读取主库文件，不会干扰任何打开中的连接，也不会与并发写入竞争。
    static func backupDefaultDatabase(fileManager: FileManager = .default) {
        let folder = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Weekflow", isDirectory: true)
        let databaseURL = folder
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent("Weekflow.store")
        let service = DatabaseBackupService(databaseURL: databaseURL, fileManager: fileManager)
        try? service.makeBackup()
    }

    func preloaded(with preload: LocalStoragePreload) -> LocalStorage {
        var copy = self
        copy.preload = LocalStoragePreloadCache(preload)
        return copy
    }

    /// 数据安全：滚动备份与恢复服务（备份最近 N 份 SQLite 快照）。
    var backupService: DatabaseBackupService {
        DatabaseBackupService(databaseURL: databaseURL)
    }

    /// 在成功加载后调用，保存一份当前良好状态的备份（轮转保留最近 N 份）。
    func makeBackup() throws {
        try backupService.makeBackup()
    }

    /// 从最近一份良好备份恢复（库损坏时的兜底）。无备份返回 false。
    @discardableResult
    func restoreLatestBackup() throws -> Bool {
        try backupService.restoreLatest()
    }

    func load() throws -> [WeeklyGoal]? {
        if let preload {
            switch try preload.take(.goals, \.goals) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadGoals() }
    }

    func save(
        _ goals: [WeeklyGoal],
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try write { try $0.saveGoals(goals, kind: kind) }
    }

    func applyGoalChanges(
        _ changes: PersistenceGoalChangeSet,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        guard !changes.isEmpty else { return }
        try write { try $0.applyGoalChanges(changes, kind: kind) }
    }

    func loadChannels() throws -> [TaskChannel]? {
        if let preload {
            switch try preload.take(.channels, \.channels) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadChannels() }
    }

    func saveChannels(_ channels: [TaskChannel]) throws {
        try write { try $0.saveChannels(channels, kind: .userEdit) }
    }

    func loadCalendarEvents() throws -> [CalendarEvent]? {
        if let preload {
            switch try preload.take(.calendarEvents, \.calendarEvents) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadCalendarEvents() }
    }

    func saveCalendarEvents(_ events: [CalendarEvent]) throws {
        try write { try $0.saveCalendarEvents(events, kind: .userEdit) }
    }

    func loadDailyPlanningStates() throws -> [DailyPlanningState]? {
        if let preload {
            switch try preload.take(.dailyPlanningStates, \.dailyPlanningStates) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadDailyPlanningStates() }
    }

    func saveDailyPlanningStates(_ states: [DailyPlanningState]) throws {
        try write { try $0.saveDailyPlanningStates(states, kind: .userEdit) }
    }

    func loadFocusRecords() throws -> [FocusRecord]? {
        if let preload {
            switch try preload.take(.focusRecords, \.focusRecords) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadFocusRecords() }
    }

    func saveFocusRecords(_ records: [FocusRecord]) throws {
        try write { try $0.saveFocusRecords(records, kind: .userEdit) }
    }

    func loadDailySummaries() throws -> [DailySummary]? {
        if let preload {
            switch try preload.take(.dailySummaries, \.dailySummaries) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadDailySummaries() }
    }

    func loadActiveTimerSession() throws -> TaskTimerSession? {
        if let preload {
            switch try preload.take(.activeTimer, \.activeTimerSession) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try readOptional { try $0.loadActiveTimerSession() }
    }

    func saveDailySummaries(_ summaries: [DailySummary]) throws {
        try write { try $0.saveDailySummaries(summaries, kind: .userEdit) }
    }

    func saveActiveTimerSession(_ session: TaskTimerSession?) throws {
        try write { try $0.saveActiveTimerSession(session) }
    }

    // Phase 3-1: single-record upsert / delete (O(1) in stored record count).
    func upsertCalendarEvent(_ event: CalendarEvent) throws {
        try write { try $0.upsertCalendarEvent(event, kind: .userEdit) }
    }

    func deleteCalendarEvent(id: String) throws {
        try write { try $0.deleteCalendarEvent(id: id, kind: .userEdit) }
    }

    func upsertFocusRecord(_ record: FocusRecord) throws {
        try write { try $0.upsertFocusRecord(record, kind: .userEdit) }
    }

    func upsertDailySummary(_ summary: DailySummary) throws {
        try write { try $0.upsertDailySummary(summary, kind: .userEdit) }
    }

    func upsertDailyPlanningState(_ state: DailyPlanningState) throws {
        try write { try $0.upsertDailyPlanningState(state, kind: .userEdit) }
    }

    func upsertDailyPlanAndCalendarEvent(
        state: DailyPlanningState,
        event: CalendarEvent
    ) throws {
        try write {
            try $0.upsertDailyPlanAndCalendarEvent(
                state: state,
                event: event,
                kind: .userEdit
            )
        }
    }

    func pendingAutomaticDistributionChanges() throws -> [PersistedAutomaticDistributionChange] {
        if let preload {
            switch try preload.take(
                .automaticDistribution,
                \.pendingAutomaticDistributionChanges
            ) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        return try read { try $0.pendingAutomaticDistributionChanges() } ?? []
    }

    func commitAutomaticDistribution(transactionID: UUID) throws {
        try read { try $0.commitAutomaticDistribution(transactionID: transactionID) }
    }

    func detachAutomaticDistribution(taskID: UUID, transactionID: UUID) throws {
        try read { try $0.detachAutomaticDistribution(
            taskID: taskID,
            transactionID: transactionID
        ) }
    }

    func diagnostics() throws -> PersistenceDiagnostics? {
        try read { try $0.diagnostics() }
    }

    /// P1-1: Eagerly normalize all persisted payloads to current format.
    @discardableResult
    func normalizeAllPayloads() throws -> Int {
        try write { try $0.normalizeAllPayloads() }
    }

    @discardableResult
    func normalizeAllPayloadsIfNeeded(marker: String) throws -> Int {
        if let preload, try preload.consume(.payloadNormalization) {
            return 0
        }
        return try write { try $0.normalizeAllPayloadsIfNeeded(marker: marker) }
    }

    func saveApplicationSnapshot(
        _ snapshot: WeekflowPersistenceSnapshot,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try write { try $0.saveApplicationSnapshot(snapshot, kind: kind) }
    }

    func saveDailyPlanAndCalendarEvents(
        states: [DailyPlanningState],
        events: [CalendarEvent]
    ) throws {
        try write {
            try $0.saveDailyPlanAndCalendarEvents(
                states: states,
                events: events,
                kind: .userEdit
            )
        }
    }

    func saveGoalChangesAndActiveTimer(
        changes: PersistenceGoalChangeSet,
        session: TaskTimerSession?,
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try write {
            try $0.saveGoalChangesAndActiveTimer(
                changes: changes,
                session: session,
                kind: kind
            )
        }
    }

    private func read<Result: Sendable>(
        _ operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result? {
        if let initializationError { throw initializationError }
        if !fileManager.fileExists(atPath: databaseURL.path) {
            guard legacyFilesExist else { return nil }
            try migrateLegacyJSON()
        }
        try ensurePreMigrationBackup()
        return try PersistenceActorBridge.run(on: persistenceActor, operation)
    }

    private func readOptional<Result: Sendable>(
        _ operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result?
    ) throws -> Result? {
        if let initializationError { throw initializationError }
        if !fileManager.fileExists(atPath: databaseURL.path) {
            guard legacyFilesExist else { return nil }
            try migrateLegacyJSON()
        }
        try ensurePreMigrationBackup()
        return try PersistenceActorBridge.run(on: persistenceActor, operation)
    }

    private func write<Result: Sendable>(
        _ operation: @Sendable @escaping (SwiftDataPersistenceRepository) throws -> Result
    ) throws -> Result {
        if let initializationError { throw initializationError }
        if !fileManager.fileExists(atPath: databaseURL.path), legacyFilesExist {
            try migrateLegacyJSON()
        }
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: databaseURL.path) {
            try ensurePreMigrationBackup()
        }
        return try PersistenceActorBridge.run(on: persistenceActor, operation)
    }

    // MARK: - Async writes (non-blocking on MainActor)
    // MARK: - Async startup reads

    func loadAsync() async throws -> [WeeklyGoal]? {
        try await readOptionalAsync { try $0.loadGoals() }
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

    private var legacyFilesExist: Bool {
        legacyURLs.contains { fileManager.fileExists(atPath: $0.path) }
    }

    /// Creates a pre-migration backup with versioned path (P1-3 fix).
    /// Future migrations (V2→V3, etc.) will create separate backup directories.
    private func ensurePreMigrationBackup() throws {
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

    private var legacyURLs: [URL] {
        [
            legacyGoalsURL,
            legacyChannelsURL,
            legacyCalendarEventsURL,
            legacyDailyPlanningStatesURL,
            legacyFocusRecordsURL,
            legacyDailySummariesURL
        ]
    }

    private func migrateLegacyJSON() throws {
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

    private func loadLegacySnapshot() throws -> WeekflowPersistenceSnapshot {
        WeekflowPersistenceSnapshot(
            goals: try decodeLegacy([WeeklyGoal].self, at: legacyGoalsURL) ?? [],
            channels: try decodeLegacy([TaskChannel].self, at: legacyChannelsURL) ?? [],
            calendarEvents: try decodeLegacy([CalendarEvent].self, at: legacyCalendarEventsURL) ?? [],
            dailyPlanningStates: try decodeLegacy([DailyPlanningState].self, at: legacyDailyPlanningStatesURL) ?? [],
            focusRecords: try decodeLegacy([FocusRecord].self, at: legacyFocusRecordsURL) ?? [],
            dailySummaries: try decodeLegacy([DailySummary].self, at: legacyDailySummariesURL) ?? []
        )
    }

    private func decodeLegacy<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.weekflow.decode(type, from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    private func createReadOnlyLegacyBackup() throws {
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

    private static func validateStorageHealth(
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
