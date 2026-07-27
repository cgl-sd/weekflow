import Foundation
import Testing
@testable import Weekflow

@Test func diagnosticBundleExcludesUserContentAndAbsoluteStoragePaths() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDiagnostics-\(UUID().uuidString)", isDirectory: true)
    let output = root.appendingPathComponent("support.json")
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = LocalStorage(baseDirectory: root.appendingPathComponent("Private User Data"))
    let privateTitle = "PRIVATE-TASK-TITLE-\(UUID().uuidString)"
    try storage.save([
        WeeklyGoal(title: privateTitle, outcome: "PRIVATE-OUTCOME", startDate: .now, endDate: .now)
    ])

    try DiagnosticSupportService().write(storage: storage, to: output)
    let text = try String(contentsOf: output, encoding: .utf8)

    #expect(!text.contains(privateTitle))
    #expect(!text.contains("PRIVATE-OUTCOME"))
    #expect(!text.contains(root.path))
    #expect(text.contains("\"goals\" : 1"))
}

@Test func diagnosticRedactorRemovesHomeDirectoryAndUserPath() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let redacted = DiagnosticRedactor.redact("failed at \(home)/Library and /Users/example/Desktop")
    #expect(!redacted.contains(home))
    #expect(!redacted.contains("/Users/example"))
    #expect(redacted.contains("<HOME>"))
}
