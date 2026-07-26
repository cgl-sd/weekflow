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

/// Native SwiftUI command definitions. Using the scene command lifecycle keeps
/// menus stable without polling or swizzling NSApplication internals.
struct WeekflowSceneCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建周目标") {
                CommandRouter.shared.addWeeklyGoalHandler?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("新建任务") {
                CommandRouter.shared.send(.addTask)
            }
            .keyboardShortcut("a", modifiers: [])

            Divider()

            Button("导入周规划…") {
                CommandRouter.shared.send(.importPlan)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("导出周规划…") {
                CommandRouter.shared.send(.exportPlan)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                CommandRouter.shared.send(.openSettings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("任务") {
            command("打开所选任务", .openHighlightedTask, key: "\r", modifiers: [])
            command("开始或暂停计时", .toggleTimer, key: " ", modifiers: [])
            command("标记完成或未完成", .completeHighlightedTask, key: "c", modifiers: [])
            command("进入专注模式", .focusHighlightedTask, key: "f", modifiers: [])
            Divider()
            command("自动安排", .autoScheduleHighlightedTask, key: "x", modifiers: [])
            command("推迟一天", .delayHighlightedTask, key: "d", modifiers: [])
            command("移入待办箱", .backlogHighlightedTask, key: "z", modifiers: [])
            Divider()
            command("复制所选任务", .copyHighlightedTask)
            command("剪切所选任务", .cutHighlightedTask)
            command("粘贴任务", .pasteTask)
            Divider()
            command("删除所选任务", .deleteHighlightedTask)
        }

        CommandGroup(replacing: .help) {
            Button("键盘快捷键") {
                CommandRouter.shared.send(.shortcutHelp)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }

    @ViewBuilder
    private func command(
        _ title: String,
        _ command: AppCommand,
        key: KeyEquivalent? = nil,
        modifiers: EventModifiers = .command
    ) -> some View {
        if let key {
            Button(title) { CommandRouter.shared.send(command) }
                .keyboardShortcut(key, modifiers: modifiers)
        } else {
            Button(title) { CommandRouter.shared.send(command) }
        }
    }
}
