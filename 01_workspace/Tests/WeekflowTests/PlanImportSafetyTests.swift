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

@Test func planImportPreflightsFileSizeBeforeReading() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowImportPreflight-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let oversized = root.appendingPathComponent("oversized.json")
    try Data(repeating: 0, count: PlanImportService.maximumFileSize + 1).write(to: oversized)
    #expect(throws: PlanImportService.PlanImportError.self) {
        _ = try PlanImportService.readData(from: oversized)
    }

    #expect(throws: PlanImportService.PlanImportError.self) {
        _ = try PlanImportService.readData(from: root)
    }

    let valid = root.appendingPathComponent("valid.json")
    let expected = Data("{}".utf8)
    try expected.write(to: valid)
    #expect(try PlanImportService.readData(from: valid) == expected)
}

@MainActor
@Test func exportedCrossYearPlanRoundTripsJanuaryTaskDate() throws {
    let start = try #require(PlanImportService.parseDatePublic("2026-12-29"))
    let end = try #require(PlanImportService.parseDatePublic("2027-01-04"))
    let januaryTaskDate = try #require(PlanImportService.parseDatePublic("2027-01-02"))
    let plan = WeeklyPlan(title: "跨年周", startDate: start, endDate: end)
    let goal = WeeklyGoal(
        title: "跨年目标",
        outcome: "导入导出日期一致",
        startDate: start,
        endDate: end,
        tasks: [WeekTask(title: "一月任务", plannedDate: januaryTaskDate, estimatedMinutes: 30)],
        planID: plan.id
    )
    let data = try #require(PlanImportService.exportPlan(plan, goals: [goal]))
    let payload: PlanImportService.PlanImportPayload
    switch PlanImportService.parse(data: data) {
    case let .success(value): payload = value
    case let .failure(error):
        Issue.record("跨年导出内容无法重新解析：\(error.localizedDescription)")
        return
    }

    let fixture = WeekflowDevelopmentFixture(
        identifier: "cross-year-import",
        referenceDate: start,
        goals: [],
        channels: TaskChannel.defaults,
        calendarEvents: []
    )
    let store = WeekflowStore(developmentFixture: fixture)
    _ = PlanImportService.importIntoStore(payload, store: store, archiveExisting: false)
    let importedDate = try #require(store.goals.first?.tasks.first?.plannedDate)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    #expect(calendar.component(.year, from: importedDate) == 2027)
    #expect(calendar.component(.month, from: importedDate) == 1)
    #expect(calendar.component(.day, from: importedDate) == 2)
}
