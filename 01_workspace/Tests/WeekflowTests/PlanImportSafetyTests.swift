import Foundation
import Testing
@testable import Weekflow

@Test func legacyPlansJSONMigratesIntoSwiftDataOnce() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowLegacyPlans-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let plan = WeeklyPlan(title: "原始规划", startDate: .now, endDate: .now)
    try JSONEncoder.weekflow.encode([plan]).write(
        to: folder.appendingPathComponent("plans.json"),
        options: .atomic
    )

    let storage = LocalStorage(baseDirectory: folder)
    #expect(try storage.loadPlans()?.first?.title == "原始规划")

    let changed = WeeklyPlan(title: "不应覆盖数据库", startDate: .now, endDate: .now)
    try JSONEncoder.weekflow.encode([changed]).write(
        to: folder.appendingPathComponent("plans.json"),
        options: .atomic
    )
    #expect(try LocalStorage(baseDirectory: folder).loadPlans()?.first?.title == "原始规划")
}

@Test func planImportRejectsUnsafeBoundsAndInvalidRanges() {
    let oversized = Data(repeating: 0, count: PlanImportService.maximumFileSize + 1)
    if case .failure(.limitExceeded) = PlanImportService.parse(data: oversized) {
        // expected
    } else {
        Issue.record("超大导入文件应被拒绝")
    }

    let invalidRange = Data("""
    {"startDate":"2026-07-30","endDate":"2026-07-20","goals":[{"title":"目标"}]}
    """.utf8)
    if case .failure(.invalidDateRange) = PlanImportService.parse(data: invalidRange) {
        // expected
    } else {
        Issue.record("反向日期范围应被拒绝")
    }

    let invalidMinutes = Data("""
    {"startDate":"2026-07-20","endDate":"2026-07-30","goals":[{"title":"目标","tasks":[{"title":"任务","minutes":0}]}]}
    """.utf8)
    if case .failure(.invalidValue) = PlanImportService.parse(data: invalidMinutes) {
        // expected
    } else {
        Issue.record("非法任务时长应被拒绝")
    }
}
