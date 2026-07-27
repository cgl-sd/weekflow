import Foundation
import Testing
@testable import Weekflow

@Test func taskEmbeddedAuditHistoryKeepsNewestBoundWithoutTouchingUserContent() {
    var task = WeekTask(title: "保留正文", plannedDate: .now, estimatedMinutes: 30)
    task.notes = "用户笔记"
    task.comments = [TaskComment(body: "用户评论")]

    for index in 0..<(TaskEmbeddedHistoryPolicy.maximumChangeRecords + 25) {
        task.appendChangeRecord(TaskChangeRecord(
            field: "序号",
            oldValue: "",
            newValue: String(index),
            source: .manual
        ))
    }

    #expect(task.changeRecords.count == TaskEmbeddedHistoryPolicy.maximumChangeRecords)
    #expect(task.changeRecords.first?.newValue == "25")
    #expect(task.changeRecords.last?.newValue == String(TaskEmbeddedHistoryPolicy.maximumChangeRecords + 24))
    #expect(task.notes == "用户笔记")
    #expect(task.comments.map { $0.body } == ["用户评论"])
}
