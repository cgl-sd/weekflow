import Foundation

/// Persistence facade used by WeekflowStore.
///
/// New writes go to the normalized SwiftData store. Legacy JSON files are read
/// only during the first migration and are retained as a recoverable backup.
struct LocalStorage {
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
    private let repositoryBox = RepositoryBox()

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        let folder = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Weekflow", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
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

    func load() throws -> [WeeklyGoal]? {
        try repositoryForReading()?.loadGoals()
    }

    func save(
        _ goals: [WeeklyGoal],
        kind: PersistenceMutationKind = .userEdit
    ) throws {
        try repositoryForWriting().saveGoals(goals, kind: kind)
    }

    func loadChannels() throws -> [TaskChannel]? {
        try repositoryForReading()?.loadChannels()
    }

    func saveChannels(_ channels: [TaskChannel]) throws {
        try repositoryForWriting().saveChannels(channels, kind: .userEdit)
    }

    func loadCalendarEvents() throws -> [CalendarEvent]? {
        try repositoryForReading()?.loadCalendarEvents()
    }

    func saveCalendarEvents(_ events: [CalendarEvent]) throws {
        try repositoryForWriting().saveCalendarEvents(events, kind: .userEdit)
    }

    func loadDailyPlanningStates() throws -> [DailyPlanningState]? {
        try repositoryForReading()?.loadDailyPlanningStates()
    }

    func saveDailyPlanningStates(_ states: [DailyPlanningState]) throws {
        try repositoryForWriting().saveDailyPlanningStates(states, kind: .userEdit)
    }

    func loadFocusRecords() throws -> [FocusRecord]? {
        try repositoryForReading()?.loadFocusRecords()
    }

    func saveFocusRecords(_ records: [FocusRecord]) throws {
        try repositoryForWriting().saveFocusRecords(records, kind: .userEdit)
    }

    func loadDailySummaries() throws -> [DailySummary]? {
        try repositoryForReading()?.loadDailySummaries()
    }

    func saveDailySummaries(_ summaries: [DailySummary]) throws {
        try repositoryForWriting().saveDailySummaries(summaries, kind: .userEdit)
    }

    func pendingAutomaticDistributionChanges() throws -> [PersistedAutomaticDistributionChange] {
        try repositoryForReading()?.pendingAutomaticDistributionChanges() ?? []
    }

    func commitAutomaticDistribution(transactionID: UUID) throws {
        try repositoryForReading()?.commitAutomaticDistribution(transactionID: transactionID)
    }

    func detachAutomaticDistribution(taskID: UUID, transactionID: UUID) throws {
        try repositoryForReading()?.detachAutomaticDistribution(
            taskID: taskID,
            transactionID: transactionID
        )
    }

    func diagnostics() throws -> PersistenceDiagnostics? {
        try repositoryForReading()?.diagnostics()
    }

    private func repositoryForReading() throws -> WeekflowPersistenceRepository? {
        if let repository = repositoryBox.repository { return repository }
        if fileManager.fileExists(atPath: databaseURL.path) {
            let repository = try SwiftDataPersistenceRepository(storeURL: databaseURL)
            repositoryBox.repository = repository
            return repository
        }
        guard legacyFilesExist else { return nil }
        try migrateLegacyJSON()
        return repositoryBox.repository
    }

    private func repositoryForWriting() throws -> WeekflowPersistenceRepository {
        if let repository = try repositoryForReading() { return repository }
        try fileManager.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
        let repository = try SwiftDataPersistenceRepository(storeURL: databaseURL)
        repositoryBox.repository = repository
        return repository
    }

    private var legacyFilesExist: Bool {
        legacyURLs.contains { fileManager.fileExists(atPath: $0.path) }
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
            let repository = try SwiftDataPersistenceRepository(storeURL: temporaryURL)
            try repository.importLegacySnapshot(snapshot)
            let migratedGoals = try repository.loadGoals() ?? []
            let migratedChannels = try repository.loadChannels() ?? []
            let migratedCalendarEvents = try repository.loadCalendarEvents() ?? []
            let migratedDailyPlans = try repository.loadDailyPlanningStates() ?? []
            let migratedFocus = try repository.loadFocusRecords() ?? []
            let migratedDailyReviews = try repository.loadDailySummaries() ?? []
            guard migratedGoals.count == snapshot.goals.count,
                  migratedChannels.count == snapshot.channels.count,
                  migratedCalendarEvents.count == snapshot.calendarEvents.count,
                  migratedDailyPlans.count == Set(snapshot.dailyPlanningStates.map { Calendar.current.startOfDay(for: $0.date) }).count,
                  migratedFocus.count == snapshot.focusRecords.count,
                  migratedDailyReviews.count == Set(snapshot.dailySummaries.map { Calendar.current.startOfDay(for: $0.date) }).count else {
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
            repositoryBox.repository = try SwiftDataPersistenceRepository(storeURL: databaseURL)
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

}

private final class RepositoryBox {
    var repository: WeekflowPersistenceRepository?
}

enum LocalStorageMigrationError: LocalizedError {
    case validationFailed

    var errorDescription: String? {
        switch self {
        case .validationFailed: "旧数据导入后的数量或关联校验失败"
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
