import Foundation
import Testing
@testable import Weekflow

@Test func corruptLocalDataPausesPersistenceWithoutOverwritingTheOriginalFile() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCorruptStorage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let goalsURL = folder.appendingPathComponent("weekflow.json")
    let originalData = Data("{not-valid-json".utf8)
    try originalData.write(to: goalsURL)

    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))

    #expect(store.persistenceIssue != nil)
    #expect(store.goals.isEmpty)

    store.addGoal(title: "不应写入", outcome: "保护原文件", endDate: .now)

    #expect(try Data(contentsOf: goalsURL) == originalData)
}

@Test func failedLocalSavePausesFurtherPersistenceAndReportsTheIssue() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowBlockedStorage-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let blockedDirectory = root.appendingPathComponent("not-a-directory")
    try Data("occupied".utf8).write(to: blockedDirectory)
    let store = WeekflowStore(storage: LocalStorage(baseDirectory: blockedDirectory))

    #expect(store.persistenceIssue == nil)

    store.addGoal(title: "无法保存", outcome: "报告错误", endDate: .now)

    #expect(store.persistenceIssue?.contains("保存失败") == true)
    #expect(try Data(contentsOf: blockedDirectory) == Data("occupied".utf8))
}
