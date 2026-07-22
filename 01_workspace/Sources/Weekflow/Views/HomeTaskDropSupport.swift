import SwiftUI

struct HomeTaskRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// Stores continuously changing task-row geometry without publishing a
/// SwiftUI state mutation on every animation frame. Drop handling and anchored
/// menu placement read the latest snapshot directly when an interaction begins.
final class HomeTaskRowFrameCache {
    var frames: [UUID: CGRect] = [:]
}

struct HomeColumnTaskDropDelegate: DropDelegate {
    @Binding var draggedTaskToken: TaskDragToken?
    let date: Date
    let rowFrames: () -> [UUID: CGRect]
    let store: WeekflowStore
    var isDropTarget: Binding<Bool>? = nil

    func validateDrop(info: DropInfo) -> Bool {
        draggedTaskToken != nil
    }

    func dropEntered(info: DropInfo) {
        isDropTarget?.wrappedValue = true
        updateInsertion(at: info.location.y, persistImmediately: false)
    }

    func dropExited(info: DropInfo) {
        isDropTarget?.wrappedValue = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateInsertion(at: info.location.y, persistImmediately: false)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard draggedTaskToken != nil else { return false }
        updateInsertion(at: info.location.y, persistImmediately: true)
        store.activeDay = SystemBusinessCalendar.current.calendar.startOfDay(for: date)
        isDropTarget?.wrappedValue = false
        draggedTaskToken = nil
        return true
    }

    private func updateInsertion(at y: CGFloat, persistImmediately: Bool) {
        guard var token = draggedTaskToken else { return }
        let rowFrames = rowFrames()
        if token.sourceDate.map({ !SystemBusinessCalendar.current.calendar.isDate($0, inSameDayAs: date) }) ?? true {
            store.relocateTask(
                goalID: token.goalID,
                taskID: token.taskID,
                from: token.sourceDate,
                to: date,
                persistImmediately: false
            )
            token = TaskDragToken(
                goalID: token.goalID,
                taskID: token.taskID,
                sourceDate: date
            )
            draggedTaskToken = token
        }

        let target = store.tasks(on: date).first { entry in
            entry.task.id != token.taskID
                && (rowFrames[entry.task.id]?.midY ?? -.infinity) > y
        }.map { TaskReference(goalID: $0.goal.id, taskID: $0.task.id) }

        withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.86)) {
            store.reorderTask(
                goalID: token.goalID,
                taskID: token.taskID,
                before: target,
                on: date,
                persistImmediately: persistImmediately
            )
        }
    }
}
