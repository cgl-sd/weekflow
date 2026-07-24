import Foundation
import Observation

// Subtask CRUD, reorder, and toggle operations.

extension WeekflowStore {
    func addSubtask(
        goalID: UUID,
        taskID: UUID,
        title: String,
        persistImmediately: Bool = true
    ) -> UUID {
        // P1-5 fix: delegate to TaskService for title trimming + creation.
        let subtask = TaskSubtask(title: title.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !subtask.title.isEmpty else { return subtask.id }
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) {
            $0.subtasks.append(subtask)
        }
        return subtask.id
    }

    func updateSubtaskTitle(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        title: String,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].title = title
        }
    }

    func updateSubtaskActualMinutes(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        minutes: Int,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].actualMinutes = max(minutes, 0)
        }
    }

    func updateSubtaskPlannedMinutes(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        minutes: Int,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].plannedMinutes = max(minutes, 0)
        }
    }

    func deleteSubtask(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        persistImmediately: Bool = true
    ) {
        // P1-5 fix: delegate to TaskService.
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            task = taskService.withDeletedSubtask(task, subtaskID: subtaskID)
        }
    }

    func moveSubtask(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        to targetSubtaskID: UUID?,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let sourceIndex = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            guard let targetSubtaskID else {
                let subtask = task.subtasks.remove(at: sourceIndex)
                task.subtasks.append(subtask)
                return
            }
            guard subtaskID != targetSubtaskID,
                  let targetIndex = task.subtasks.firstIndex(where: { $0.id == targetSubtaskID }) else { return }
            let subtask = task.subtasks.remove(at: sourceIndex)
            task.subtasks.insert(subtask, at: min(targetIndex, task.subtasks.endIndex))
        }
    }

    func toggleSubtask(
        goalID: UUID,
        taskID: UUID,
        subtaskID: UUID,
        persistImmediately: Bool = true
    ) {
        updateTask(goalID: goalID, taskID: taskID, persistImmediately: persistImmediately) { task in
            guard let index = task.subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            task.subtasks[index].completed.toggle()
            task.subtasks[index].completedAt = task.subtasks[index].completed ? .now : nil
            if task.subtasks[index].completed && !task.completionCredits.contains(where: { $0.reason == .subtaskCompleted && businessCalendar.calendar.isDateInToday($0.date) }) {
                task.completionCredits.append(CompletionCredit(date: .now, reason: .subtaskCompleted, minutes: nil))
            }
        }
    }
}
