import Foundation

extension Notification.Name {
    static let weekflowAddTask = Notification.Name("weekflow.addTask")
    static let weekflowShortcutHelp = Notification.Name("weekflow.shortcutHelp")
    static let weekflowOpenHighlightedTask = Notification.Name("weekflow.openHighlightedTask")
    static let weekflowFocusHighlightedTask = Notification.Name("weekflow.focusHighlightedTask")
    static let weekflowToggleTimer = Notification.Name("weekflow.toggleTimer")
    static let weekflowCompleteHighlightedTask = Notification.Name("weekflow.completeHighlightedTask")
    static let weekflowAutoScheduleHighlightedTask = Notification.Name("weekflow.autoScheduleHighlightedTask")
    static let weekflowDelayHighlightedTask = Notification.Name("weekflow.delayHighlightedTask")
    static let weekflowBacklogHighlightedTask = Notification.Name("weekflow.backlogHighlightedTask")
    static let weekflowDeleteHighlightedTask = Notification.Name("weekflow.deleteHighlightedTask")
    static let weekflowOpenSettings = Notification.Name("weekflow.openSettings")
    static let weekflowOpenChannelSettings = Notification.Name("weekflow.openChannelSettings")
    static let weekflowJumpToToday = Notification.Name("weekflow.jumpToToday")
    static let weekflowJumpToPreviousDay = Notification.Name("weekflow.jumpToPreviousDay")
    static let weekflowJumpToNextDay = Notification.Name("weekflow.jumpToNextDay")
    static let weekflowCopyHighlightedTask = Notification.Name("weekflow.copyHighlightedTask")
    static let weekflowCutHighlightedTask = Notification.Name("weekflow.cutHighlightedTask")
    static let weekflowPasteTask = Notification.Name("weekflow.pasteTask")
}

enum WeekflowCommand {
    static func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
