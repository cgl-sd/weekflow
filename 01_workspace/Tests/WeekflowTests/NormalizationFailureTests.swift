import Foundation
import Testing
@testable import Weekflow

private struct NormalizationFailure: Error {}

private func normalizationTestFolder(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowNormalization-\(name)-\(UUID().uuidString)", isDirectory: true)
}

/// P0-2: a normalization failure must roll back its transaction so the completion
/// marker is NOT written — otherwise a failed normalization would never be retried.
@Test func normalizationFailureDoesNotWriteCompletionMarker() throws {
    let folder = normalizationTestFolder("Marker")
    defer { try? FileManager.default.removeItem(at: folder) }
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    try LocalStorage(baseDirectory: folder).save(
        [WeeklyGoal(title: "目标", outcome: "o", startDate: day, endDate: day)],
        kind: .migration
    )

    let faulted = LocalStorage(baseDirectory: folder) { point in
        if point == .duringNormalization { throw NormalizationFailure() }
    }
    // The normalization body throws inside the transaction.
    #expect(throws: NormalizationFailure.self) {
        try faulted.normalizeAllPayloadsIfNeeded(marker: "test.marker")
    }
    // If the failed attempt had wrongly written the completion marker, this second
    // call would short-circuit (return without throwing). Because the marker must
    // NOT be written on failure, the second call re-enters normalization and throws.
    #expect(throws: NormalizationFailure.self) {
        try faulted.normalizeAllPayloadsIfNeeded(marker: "test.marker")
    }

    // A healthy storage runs normalization and writes the marker; a subsequent call
    // is then a no-op (idempotent), proving the marker was written by the healthy
    // run rather than the failed one.
    let healthy = LocalStorage(baseDirectory: folder)
    _ = try healthy.normalizeAllPayloadsIfNeeded(marker: "test.marker")
    let again = try healthy.normalizeAllPayloadsIfNeeded(marker: "test.marker")
    #expect(again == 0)
}

/// P0-2: when normalization fails during store startup, the store must enter
/// protection mode (stop saving) rather than silently continuing.
@MainActor
@Test func normalizationFailurePutsStoreIntoProtectionMode() throws {
    let folder = normalizationTestFolder("Protection")
    defer { try? FileManager.default.removeItem(at: folder) }
    let day = SystemBusinessCalendar.current.date(for: LocalDay(year: 2026, month: 7, day: 20))
    try LocalStorage(baseDirectory: folder).save(
        [WeeklyGoal(title: "目标", outcome: "o", startDate: day, endDate: day)],
        kind: .migration
    )
    let faulted = LocalStorage(baseDirectory: folder) { point in
        if point == .duringNormalization { throw NormalizationFailure() }
    }
    let store = WeekflowStore(storage: faulted)
    #expect(store.persistenceEnabled == false)
    #expect(store.persistenceIssue != nil)
}
