import Foundation

/// Command handling logic extracted from ContentView (P2-2 ContentView split).
///
/// Encapsulates all command execution logic so ContentView can focus on
/// layout and view composition. The handler receives dependencies via
/// closures to avoid tight coupling with specific view state.
@MainActor
struct ContentCommandHandler {
    let store: WeekflowStore
    let focusTimer: FocusTimerService

    // State mutation closures provided by ContentView
    var setShowTaskForm: (Bool) -> Void
    var setShowShortcutHelp: (Bool) -> Void
    var setPresentedSettings: (WorkspaceSettingsSection?) -> Void
    var setPresentedTask: (TaskDetailTarget?) -> Void
    var setDestination: (AppDestination) -> Void
    var navigateDate: (GlobalDateNavigation) -> Void
    var setShowPlanImporter: (Bool) -> Void
    var setShowPlanExporter: (Bool) -> Void

    enum GlobalDateNavigation { case today, previous, next }

    /// Handles an app command by dispatching to the appropriate action.
    func handle(_ command: AppCommand) {
        switch command {
        case .addTask:
            setShowTaskForm(true)
        case .shortcutHelp:
            setShowShortcutHelp(true)
        case .openHighlightedTask:
            openHighlightedTask()
        case .focusHighlightedTask:
            openFocusForHighlightedTask()
        case .toggleTimer:
            toggleHighlightedTimer()
        case .completeHighlightedTask:
            toggleHighlightedCompletion()
        case .autoScheduleHighlightedTask:
            store.autoScheduleHighlightedTask()
        case .delayHighlightedTask:
            delayHighlightedTask()
        case .backlogHighlightedTask:
            moveHighlightedTaskToBacklog()
        case .deleteHighlightedTask:
            deleteHighlightedTask()
        case .openSettings:
            setPresentedSettings(.general)
        case .openChannelSettings:
            setPresentedSettings(.channels)
        case .copyHighlightedTask:
            store.copyHighlightedTask()
        case .cutHighlightedTask:
            store.copyHighlightedTask(cutsSource: true)
        case .pasteTask:
            _ = store.pasteTaskClipboard(on: store.activeDay)
        case .jumpToToday:
            navigateDate(.today)
        case .jumpToPreviousDay:
            navigateDate(.previous)
        case .jumpToNextDay:
            navigateDate(.next)
        case .refreshGlobalShortcuts:
            break
        case .importPlan:
            setShowPlanImporter(true)
        case .exportPlan:
            setShowPlanExporter(true)
        }
    }

    // MARK: - Task Actions

    private func openHighlightedTask() {
        guard let highlighted = store.highlightedTask else { return }
        setPresentedTask(TaskDetailTarget(goalID: highlighted.goalID, taskID: highlighted.taskID))
    }

    private func openFocusForHighlightedTask() {
        linkHighlightedTaskToFocus()
        setDestination(.focus)
    }

    private func linkHighlightedTaskToFocus() {
        if let reference = store.highlightedTask,
           let entry = store.activeTasks.first(where: { $0.goal.id == reference.goalID && $0.task.id == reference.taskID }) {
            guard focusTimer.linkedTask != reference else { return }
            focusTimer.linkTask(reference, title: entry.task.title, estimatedMinutes: entry.task.estimatedMinutes)
        }
    }

    private func toggleHighlightedTimer() {
        guard let reference = store.highlightedTask else { return }
        store.toggleTaskTimer(goalID: reference.goalID, taskID: reference.taskID)
    }

    private func toggleHighlightedCompletion() {
        guard let reference = store.highlightedTask else { return }
        store.toggleTask(goalID: reference.goalID, taskID: reference.taskID)
    }

    private func delayHighlightedTask() {
        guard let reference = store.highlightedTask,
              let entry = store.activeTasks.first(where: { $0.goal.id == reference.goalID && $0.task.id == reference.taskID }) else { return }
        store.moveTask(
            goalID: reference.goalID,
            taskID: reference.taskID,
            to: SystemBusinessCalendar.current.calendar.date(
                byAdding: .day,
                value: 1,
                to: entry.task.plannedDate ?? store.activeDay
            )
        )
    }

    private func moveHighlightedTaskToBacklog() {
        guard let reference = store.highlightedTask else { return }
        store.unassignTask(goalID: reference.goalID, taskID: reference.taskID)
    }

    private func deleteHighlightedTask() {
        guard let reference = store.highlightedTask else { return }
        store.deleteTask(goalID: reference.goalID, taskID: reference.taskID)
    }
}
