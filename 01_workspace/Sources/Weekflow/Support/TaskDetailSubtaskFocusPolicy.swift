import Foundation

enum TaskDetailSubtaskFocusPolicy {
    static func targetAfterDeleting(
        subtaskID: UUID,
        from subtasks: [TaskSubtask]
    ) -> UUID? {
        guard let index = subtasks.firstIndex(where: { $0.id == subtaskID }) else { return nil }
        if index > 0 {
            return subtasks[index - 1].id
        }
        if subtasks.count > 1 {
            return subtasks[index + 1].id
        }
        return nil
    }
}
