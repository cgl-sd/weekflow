import SwiftUI
import Observation

/// Internal commands are typed and routed to exactly one active scene.
enum AppCommand: String, Sendable {
    case addTask, shortcutHelp, openHighlightedTask, focusHighlightedTask
    case toggleTimer, completeHighlightedTask, autoScheduleHighlightedTask
    case delayHighlightedTask, backlogHighlightedTask, deleteHighlightedTask
    case openSettings, openChannelSettings
    case jumpToToday, jumpToPreviousDay, jumpToNextDay
    case copyHighlightedTask, cutHighlightedTask, pasteTask
    case refreshGlobalShortcuts
    case importPlan, exportPlan
}

struct RoutedAppCommand: Equatable, Sendable {
    let id: UUID
    let command: AppCommand
    let targetSceneID: UUID?
}

@MainActor
@Observable
final class CommandRouter {
    static let shared = CommandRouter()

    private(set) var latest: RoutedAppCommand?
    private(set) var activeSceneID: UUID?
    var globalShortcutRefreshHandler: (() -> Void)?
    /// Handler for creating a new weekly goal (set by ContentView on appear).
    var addWeeklyGoalHandler: (() -> Void)?

    func sceneBecameActive(_ sceneID: UUID) { activeSceneID = sceneID }

    func send(_ command: AppCommand, targetSceneID: UUID? = nil) {
        if command == .refreshGlobalShortcuts {
            globalShortcutRefreshHandler?()
            return
        }
        latest = RoutedAppCommand(
            id: UUID(),
            command: command,
            targetSceneID: targetSceneID ?? activeSceneID
        )
    }
}
