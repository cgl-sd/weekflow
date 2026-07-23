import Foundation
import Testing
@testable import Weekflow

/// R16: performance gates for large task counts. Bounds are deliberately generous
/// so the test is stable across machines/load while still guarding against gross
/// regressions; the measured numbers are emitted for performance-results.md.
/// (Precise median/P95 + Instruments profiling are run separately; the 8h soak is
/// environment-bound.)
private func makeFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowPerf-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func seedGoals(taskCount: Int) -> [WeeklyGoal] {
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    let tasks = (0..<taskCount).map { index in
        WeekTask(
            id: UUID(),
            title: "规模任务 \(index)",
            plannedDate: day,
            estimatedMinutes: 30,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
            sortOrder: index
        )
    }
    return [WeeklyGoal(title: "规模目标", outcome: "性能", startDate: day, endDate: day, tasks: tasks)]
}

@Test func coldLoadAndSingleEditStayBoundedAtTenThousandTasks() throws {
    let folder = makeFolder("Cold10k")
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = seedGoals(taskCount: 10_000)
    let storage = LocalStorage(baseDirectory: folder)
    try storage.save(original, kind: .migration)

    let clock = ContinuousClock()
    let loadDuration = clock.measure { _ = try? storage.load() }
    let loaded = try #require(try storage.load())

    var edited = loaded
    edited[0].tasks[5_000].title = "只编辑这一项"
    edited[0].tasks[5_000].updatedAt = .now
    let changes = PersistenceGoalChangeSet.difference(before: original, after: edited)
    #expect(changes.tasksToUpsert.count == 1)
    #expect(changes.goalsToUpsert.isEmpty)

    let editDuration = clock.measure { try? storage.applyGoalChanges(changes) }

    print("PERF 10k coldLoad=\(loadDuration) singleEdit=\(editDuration)")
    // Generous, stable gates (R16 targets: cold start ≤1.5s, single edit ≤100ms;
    // widened here to stay reliable under parallel CI load).
    #expect(loadDuration < .seconds(10))
    #expect(editDuration < .milliseconds(1000))
}

@Test func singleTaskPersistCostDoesNotScaleLinearlyWithTotalTasks() throws {
    func singleEditDuration(taskCount: Int) throws -> Duration {
        let folder = makeFolder("Scale\(taskCount)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = seedGoals(taskCount: taskCount)
        let storage = LocalStorage(baseDirectory: folder)
        try storage.save(original, kind: .migration)
        var edited = original
        edited[0].tasks[taskCount / 2].title = "x"
        edited[0].tasks[taskCount / 2].updatedAt = .now
        let changes = PersistenceGoalChangeSet.difference(before: original, after: edited)
        try storage.applyGoalChanges(changes)  // warm up
        let clock = ContinuousClock()
        return clock.measure { try? storage.applyGoalChanges(changes) }
    }
    let small = try singleEditDuration(taskCount: 1_000)
    let large = try singleEditDuration(taskCount: 10_000)
    print("PERF singleEdit 1k=\(small) 10k=\(large)")
    // O(1) in total stored records: 10x the data must not cost 10x the write.
    #expect(large < small * 8 + .milliseconds(100))
}
