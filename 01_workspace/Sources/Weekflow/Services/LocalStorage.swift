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

    let fileManager: FileManager
    let legacyGoalsURL: URL
    let legacyChannelsURL: URL
    let legacyCalendarEventsURL: URL
    let legacyDailyPlanningStatesURL: URL
    let legacyFocusRecordsURL: URL
    let legacyDailySummariesURL: URL
    let persistenceActor: PersistenceActor
    let initializationError: Error?
    var preload: LocalStoragePreloadCache?

    init(
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil,
        faultInjector: PersistenceFaultInjector? = nil
    ) {
        let folder = baseDirectory ?? AppDataLocation.runtimeDirectory(fileManager: fileManager)
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
        let root = rootDirectory ?? AppDataLocation.runtimeDirectory(fileManager: fileManager)
        return LocalStorage(
            fileManager: fileManager,
            baseDirectory: root.appendingPathComponent("DevelopmentFixtures", isDirectory: true)
        )
    }

    /// 数据安全：应用启动、打开数据库之前，对上一次会话的库做一次滚动备份。
    /// 应在创建 Store 之前调用——此时数据库处于静止状态（上一会话关闭时已做 WAL
    /// 检查点），备份只读取主库文件，不会干扰任何打开中的连接，也不会与并发写入竞争。
    static func backupDefaultDatabase(fileManager: FileManager = .default) {
        // DEBUG must never inspect or mutate an installed Release build's data.
        // `runtimeDirectory` resolves project-local `.data` in DEBUG and
        // Application Support only in Release.
        let folder = AppDataLocation.runtimeDirectory(fileManager: fileManager)
        let databaseURL = folder
            .appendingPathComponent("Database", isDirectory: true)
            .appendingPathComponent("Weekflow.store")
        let service = DatabaseBackupService(databaseURL: databaseURL, fileManager: fileManager)
        do {
            try service.makeBackup()
        } catch {
            // C-1 fix: log backup failure instead of silent swallow.
            // Backup is best-effort; failure does not block startup.
            NSLog("[Weekflow] 数据库滚动备份失败: %@", DiagnosticRedactor.redact(error.localizedDescription))
        }
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

    func backupStatus() -> DatabaseBackupStatus {
        backupService.status()
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

    func loadPlans() throws -> [WeeklyPlan]? {
        if let preload {
            switch try preload.take(.plans, \.plans) {
            case .unavailable: break
            case let .value(value): return value
            }
        }
        if let stored = try readOptional({ try $0.loadPlans() }) {
            return stored
        }
        guard fileManager.fileExists(atPath: legacyPlansURL.path) else { return nil }
        let data = try Data(contentsOf: legacyPlansURL)
        let plans = try JSONDecoder.weekflow.decode([WeeklyPlan].self, from: data)
        try write { try $0.savePlans(plans, kind: .migration) }
        return plans
    }

    func savePlans(_ plans: [WeeklyPlan]) throws {
        try write { try $0.savePlans(plans, kind: .userEdit) }
    }

    var legacyPlansURL: URL {
        directoryURL.appendingPathComponent("plans.json")
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

    // MARK: - Private sync helpers

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
}
