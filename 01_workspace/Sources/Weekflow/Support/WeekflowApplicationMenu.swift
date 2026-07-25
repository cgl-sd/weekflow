import AppKit

@MainActor
final class WeekflowApplicationMenu: NSObject {
    private var addWeeklyGoal: (() -> Void)?

    func install(addWeeklyGoal: (() -> Void)? = nil) {
        if let addWeeklyGoal {
            self.addWeeklyGoal = addWeeklyGoal
        }

        let mainMenu = NSMenu()
        mainMenu.addItem(topLevelItem(title: "Weekflow", submenu: applicationMenu()))
        mainMenu.addItem(topLevelItem(title: "文件", submenu: fileMenu()))
        mainMenu.addItem(topLevelItem(title: "编辑", submenu: editMenu()))
        mainMenu.addItem(topLevelItem(title: "显示", submenu: viewMenu()))
        mainMenu.addItem(topLevelItem(title: "任务", submenu: taskMenu()))
        mainMenu.addItem(topLevelItem(title: "窗口", submenu: windowMenu()))
        mainMenu.addItem(topLevelItem(title: "帮助", submenu: helpMenu()))
        NSApp.mainMenu = mainMenu
    }

    private func applicationMenu() -> NSMenu {
        let menu = NSMenu(title: "Weekflow")
        menu.addItem(actionItem("关于 Weekflow", action: #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(actionItem("设置…", action: #selector(openSettings), key: ","))

        let services = NSMenu(title: "服务")
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        NSApp.servicesMenu = services

        menu.addItem(.separator())
        menu.addItem(responderItem("隐藏 Weekflow", action: #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(responderItem(
            "隐藏其他应用",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        ))
        menu.addItem(responderItem("全部显示", action: #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(responderItem("退出 Weekflow", action: #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "文件")
        menu.addItem(actionItem(
            "新建周目标",
            action: #selector(createWeeklyGoal),
            key: "n",
            modifiers: [.command, .shift]
        ))
        menu.addItem(actionItem("新建任务", action: #selector(createTask), key: "a", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(commandItem("导入周规划…", command: .importPlan, key: "i", modifiers: [.command, .shift]))
        menu.addItem(commandItem("导出周规划…", command: .exportPlan, key: "e", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(responderItem("关闭窗口", action: #selector(NSWindow.performClose(_:)), key: "w"))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(responderItem("撤销", action: Selector(("undo:")), key: "z"))
        menu.addItem(responderItem(
            "重做",
            action: Selector(("redo:")),
            key: "z",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(responderItem("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(responderItem("复制", action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(responderItem("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(responderItem("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "显示")
        menu.addItem(responderItem(
            "进入全屏幕",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            key: "f",
            modifiers: [.command, .control]
        ))
        return menu
    }

    private func taskMenu() -> NSMenu {
        let menu = NSMenu(title: "任务")
        menu.addItem(commandItem("打开所选任务", command: .openHighlightedTask, key: "\r", modifiers: []))
        menu.addItem(commandItem("开始或暂停计时", command: .toggleTimer, key: " ", modifiers: []))
        menu.addItem(commandItem("标记完成或未完成", command: .completeHighlightedTask, key: "c", modifiers: []))
        menu.addItem(commandItem("进入专注模式", command: .focusHighlightedTask, key: "f", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(commandItem("自动安排", command: .autoScheduleHighlightedTask, key: "x", modifiers: []))
        menu.addItem(commandItem("推迟一天", command: .delayHighlightedTask, key: "d", modifiers: []))
        menu.addItem(commandItem("移入待办箱", command: .backlogHighlightedTask, key: "z", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(commandItem("复制所选任务", command: .copyHighlightedTask))
        menu.addItem(commandItem("剪切所选任务", command: .cutHighlightedTask))
        menu.addItem(commandItem("粘贴任务", command: .pasteTask))
        menu.addItem(.separator())
        menu.addItem(commandItem("删除所选任务", command: .deleteHighlightedTask))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "窗口")
        menu.addItem(responderItem("最小化", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(responderItem("缩放", action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(responderItem("前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = menu
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "帮助")
        menu.addItem(actionItem(
            "键盘快捷键",
            action: #selector(showShortcutHelp),
            key: "?",
            modifiers: [.command]
        ))
        return menu
    }

    private func topLevelItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func actionItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func responderItem(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func commandItem(
        _ title: String,
        command: AppCommand,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = actionItem(title, action: #selector(postCommand(_:)), key: key, modifiers: modifiers)
        item.representedObject = command.rawValue
        return item
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(
            string: "周目标驱动的个人执行系统\n\n开发者：cgl-sd\n© 2026 cgl-sd. 保留所有权利。",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        credits.addAttribute(
            .paragraphStyle,
            value: centeredParagraphStyle,
            range: NSRange(location: 0, length: credits.length)
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Weekflow",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发预览版",
            .version: "构建 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private var centeredParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = 3
        return style
    }

    @objc private func openSettings() { CommandRouter.shared.send(.openSettings) }
    @objc private func createWeeklyGoal() { addWeeklyGoal?() }
    @objc private func createTask() { CommandRouter.shared.send(.addTask) }
    @objc private func showShortcutHelp() { CommandRouter.shared.send(.shortcutHelp) }

    @objc private func postCommand(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let command = AppCommand(rawValue: rawValue) else { return }
        CommandRouter.shared.send(command)
    }

}
