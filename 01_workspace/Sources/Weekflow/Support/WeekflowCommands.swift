import SwiftUI
import AppKit
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

/// Suppresses ALL default English menus that SwiftUI auto-generates.
/// Without this, the menu bar shows English titles (File, Edit, View, Window, Help).
struct WeekflowDefaultMenuSuppression: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {}
        CommandGroup(replacing: .appSettings) {}
        CommandGroup(replacing: .appTermination) {}
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .importExport) {}
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(replacing: .textFormatting) {}
        CommandGroup(replacing: .toolbar) {}
    }
}

/// Additional default menu suppression (CommandsBuilder max 10 items per block).
struct WeekflowDefaultMenuSuppression2: Commands {
    var body: some Commands {
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(replacing: .windowArrangement) {}
        CommandGroup(replacing: .windowList) {}
        CommandGroup(replacing: .help) {}
    }
}

/// All-visible Chinese menus. Only useful items, all in Chinese.
struct WeekflowCommands: Commands {
    var body: some Commands {
        // ─── 文件 ───
        CommandMenu("文件") {
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

            Divider()

            Button("关闭窗口") {
                NSApp.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        // ─── 编辑 ───
        CommandMenu("编辑") {
            Button("撤销") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: .command)
            Button("重做") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])

            Divider()

            Button("剪切") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button("复制") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                .keyboardShortcut("c", modifiers: .command)
            Button("粘贴") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: .command)
            Button("全选") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a", modifiers: .command)
        }

        // ─── 显示 ───
        CommandMenu("显示") {
            Button("进入全屏幕") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }

        // ─── 任务 ───
        CommandMenu("任务") {
            Button("打开所选任务") { CommandRouter.shared.send(.openHighlightedTask) }
                .keyboardShortcut(.return, modifiers: [])
            Button("开始或暂停计时") { CommandRouter.shared.send(.toggleTimer) }
                .keyboardShortcut(.space, modifiers: [])
            Button("标记完成或未完成") { CommandRouter.shared.send(.completeHighlightedTask) }
                .keyboardShortcut("c", modifiers: [])
            Button("进入专注模式") { CommandRouter.shared.send(.focusHighlightedTask) }
                .keyboardShortcut("f", modifiers: [])

            Divider()

            Button("自动安排") { CommandRouter.shared.send(.autoScheduleHighlightedTask) }
                .keyboardShortcut("x", modifiers: [])
            Button("推迟一天") { CommandRouter.shared.send(.delayHighlightedTask) }
                .keyboardShortcut("d", modifiers: [])
            Button("移入待办箱") { CommandRouter.shared.send(.backlogHighlightedTask) }
                .keyboardShortcut("z", modifiers: [])

            Divider()

            Button("复制所选任务") { CommandRouter.shared.send(.copyHighlightedTask) }
            Button("剪切所选任务") { CommandRouter.shared.send(.cutHighlightedTask) }
            Button("粘贴任务") { CommandRouter.shared.send(.pasteTask) }

            Divider()

            Button("删除所选任务") { CommandRouter.shared.send(.deleteHighlightedTask) }
        }

        // ─── 窗口 ───
        CommandMenu("窗口") {
            Button("最小化") { NSApp.keyWindow?.performMiniaturize(nil) }
                .keyboardShortcut("m", modifiers: .command)
            Button("前置全部窗口") { NSApp.arrangeInFront(nil) }
        }

        // ─── 帮助 ───
        CommandMenu("帮助") {
            Button("键盘快捷键") {
                CommandRouter.shared.send(.shortcutHelp)
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}

