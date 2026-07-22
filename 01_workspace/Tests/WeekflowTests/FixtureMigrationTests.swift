import Foundation
import SwiftData
import Testing
@testable import Weekflow

private enum HistoricalFixture: String, CaseIterable {
    case empty
    case normal
    case lifecycle
    case automaticDistribution
    case large
    case dateBoundary
}

@Test func generateHistoricalV1Fixtures() throws {
    guard ProcessInfo.processInfo.environment["WEEKFLOW_REGENERATE_V1_FIXTURES"] == "1" else { return }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
    for fixture in HistoricalFixture.allCases {
        let directory = root.appendingPathComponent(fixture.rawValue, isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try createV1Store(at: directory.appendingPathComponent("Weekflow.store"), fixture: fixture)
    }
}

@Test func everyHistoricalV1DatabaseMigratesToV2WithoutContentDrift() throws {
    for fixture in HistoricalFixture.allCases {
        let sourceDirectory = try #require(
            Bundle.module.url(forResource: fixture.rawValue, withExtension: nil, subdirectory: "Fixtures")
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeekflowV1Migration-\(fixture.rawValue)-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.copyItem(at: sourceDirectory, to: temporaryDirectory)

        let repository = try SwiftDataPersistenceRepository(
            storeURL: temporaryDirectory.appendingPathComponent("Weekflow.store")
        )
        let actual = WeekflowPersistenceSnapshot(
            goals: try repository.loadGoals() ?? [],
            channels: try repository.loadChannels() ?? [],
            calendarEvents: try repository.loadCalendarEvents() ?? [],
            dailyPlanningStates: try repository.loadDailyPlanningStates() ?? [],
            focusRecords: try repository.loadFocusRecords() ?? [],
            dailySummaries: try repository.loadDailySummaries() ?? []
        ).canonicalized
        #expect(actual == expectedSnapshot(for: fixture).canonicalized)
    }
}

@Test func migrationFailureLeavesTheHistoricalDatabaseBytesUntouched() throws {
    let sourceDirectory = try #require(
        Bundle.module.url(forResource: HistoricalFixture.normal.rawValue, withExtension: nil, subdirectory: "Fixtures")
    )
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBrokenMigration-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    try FileManager.default.copyItem(at: sourceDirectory, to: temporaryDirectory)
    let url = temporaryDirectory.appendingPathComponent("Weekflow.store")
    var corrupted = try Data(contentsOf: url)
    corrupted.removeLast(corrupted.count / 3)
    try corrupted.write(to: url, options: .atomic)
    let before = try Data(contentsOf: url)

    #expect(throws: Error.self) {
        _ = try SwiftDataPersistenceRepository(storeURL: url)
    }
    #expect(try Data(contentsOf: url) == before)
}

@Test func canonicalMigrationValidationRejectsEqualCountsWithDifferentContent() {
    let first = expectedSnapshot(for: .normal)
    var second = first
    second.goals[0].title = "数量相同但内容错误"
    #expect(first.goals.count == second.goals.count)
    #expect(first.canonicalized != second.canonicalized)
}

private func createV1Store(at url: URL, fixture: HistoricalFixture) throws {
    let schema = Schema(versionedSchema: WeekflowSchemaV1.self)
    let configuration = ModelConfiguration("Weekflow", schema: schema, url: url, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let snapshot = expectedSnapshot(for: fixture)

    for goal in snapshot.goals {
        var envelope = goal
        envelope.tasks = []
        context.insert(PersistedGoalRecord(
            id: goal.id,
            payload: try CompactPersistenceCoding.encode(envelope),
            periodStart: goal.startDate,
            periodEnd: goal.endDate,
            channelID: goal.channelID,
            lifecycleState: goal.isDeleted ? "trashed" : (goal.isArchived ? "archived" : "active"),
            revision: 1,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000)
        ))
        for task in goal.tasks {
            var taskEnvelope = task
            taskEnvelope.plannedDay = nil
            taskEnvelope.assignedDays = []
            context.insert(PersistedTaskRecord(
                id: task.id,
                goalID: goal.id,
                subgoalID: task.subgoalID,
                payload: try CompactPersistenceCoding.encode(taskEnvelope),
                channelID: task.channelID,
                lifecycleState: task.isDeleted ? "trashed" : (task.isArchived ? "archived" : "active"),
                revision: 1,
                updatedAt: task.updatedAt
            ))
            let placements = ([task.plannedDay].compactMap { $0 }.map { ($0, 1) }
                + task.assignedDays.map { ($0, 2) })
            for (day, mask) in Dictionary(grouping: placements, by: \.0).map({ day, values in
                (day, values.reduce(0) { $0 | $1.1 })
            }) {
                context.insert(PersistedTaskAssignmentRecord(
                    uniquenessKey: "\(task.id.uuidString):\(day.persistenceKey)",
                    taskID: task.id,
                    day: try #require(day.date(in: .current)),
                    placementMask: mask,
                    source: fixture == .automaticDistribution ? "automatic" : "manual",
                    originTransactionID: fixture == .automaticDistribution ? stableUUID(900) : nil
                ))
            }
        }
    }
    try context.save()
}

private func expectedSnapshot(for fixture: HistoricalFixture) -> WeekflowPersistenceSnapshot {
    guard fixture != .empty else { return WeekflowPersistenceSnapshot() }
    let count = fixture == .large ? 500 : 1
    let start = LocalDay(year: 2024, month: fixture == .dateBoundary ? 3 : 7, day: fixture == .dateBoundary ? 10 : 15)
    let end = LocalDay(year: 2024, month: fixture == .dateBoundary ? 11 : 7, day: fixture == .dateBoundary ? 3 : 21)
    var tasks: [WeekTask] = []
    for index in 0..<count {
        var task = WeekTask(
            id: stableUUID(index + 10),
            title: "V1 task \(index)",
            plannedDate: start.date(in: .current),
            assignedDates: [end.date(in: .current)].compactMap { $0 },
            estimatedMinutes: 30,
            status: fixture == .lifecycle ? .deleted : .planned,
            archivedAt: fixture == .lifecycle ? Date(timeIntervalSince1970: 1_720_000_000) : nil,
            channelID: "work",
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sortOrder: index
        )
        task.plannedDay = start
        task.assignedDays = [end]
        tasks.append(task)
    }
    var goal = WeeklyGoal(
        id: stableUUID(1),
        title: "V1 fixture \(fixture.rawValue)",
        outcome: "canonical migration",
        startDate: start.date(in: .current) ?? .distantPast,
        endDate: end.date(in: .current) ?? .distantPast,
        channelID: "work",
        tasks: tasks
    )
    goal.startDay = start
    goal.endDay = end
    if fixture == .lifecycle {
        goal.archivedAt = Date(timeIntervalSince1970: 1_720_000_000)
    }
    return WeekflowPersistenceSnapshot(goals: [goal])
}

private func stableUUID(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
}
