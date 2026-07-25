import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class WeekflowAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let globalDateShortcuts = GlobalDateShortcutService()
    private let focusStatusItemController = FocusStatusItemController()
    private let applicationMenu = WeekflowApplicationMenu()
    /// Checkpoint invoked on system power transitions (sleep/wake). Flushes the
    /// in-flight active-task timer so elapsed work survives low-power states.
    private var powerTransitionCheckpoint: (() -> Void)?
    /// Phase 2-4 fix: the SINGLE, fully-ordered termination checkpoint. Owned and
    /// triggered exclusively by the AppDelegate so exit persistence is never split
    /// across View and Delegate. It checkpoints the active timer (flushing elapsed
    /// time into goals) and THEN performs the synchronous full-app persist.
    private var terminationCheckpoint: (@MainActor () async -> Bool)?
    private var terminationInProgress = false
    private var didCleanUp = false
    private let defaultWindowSize = NSSize(
        width: WeekflowLayout.windowWidth,
        height: WeekflowLayout.windowHeight
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        globalDateShortcuts.refresh()
        CommandRouter.shared.globalShortcutRefreshHandler = { [weak self] in
            self?.globalDateShortcuts.refresh()
        }
        UNUserNotificationCenter.current().delegate = self
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(checkpointForSystemPowerTransition),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(checkpointForSystemPowerTransition),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        DispatchQueue.main.async {
            self.configureAndActivateWindows(remainingAttempts: 8)
        }
    }

    func installFocusStatusItem(timer: FocusTimerService) {
        focusStatusItemController.install(timer: timer)
    }

    func installApplicationMenu(addWeeklyGoal: @escaping () -> Void) {
        applicationMenu.install(addWeeklyGoal: addWeeklyGoal)
        // SwiftUI finishes constructing its default command menu after the
        // scene appears. Reinstall on the next run-loop turn so the complete
        // Chinese menu becomes the stable application menu.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applicationMenu.install()
            // After the reinstall, permanently lock the menu bar.
            // Any future attempt by SwiftUI or system dialogs to change
            // NSApp.mainMenu will be silently blocked via method swizzling.
            self?.applicationMenu.activatePermanentLock()
        }
    }

    func installPowerTransitionCheckpoint(_ checkpoint: @escaping () -> Void) {
        powerTransitionCheckpoint = checkpoint
    }

    /// Phase 2-4 fix: installs the single, fully-ordered termination checkpoint.
    func installTerminationCheckpoint(
        _ checkpoint: @escaping @MainActor () async -> Bool
    ) {
        terminationCheckpoint = checkpoint
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminationCheckpoint else {
            cleanUpBeforeTermination()
            return .terminateNow
        }
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true
        Task { @MainActor in
            let shouldTerminate = await terminationCheckpoint()
            terminationInProgress = false
            if shouldTerminate { cleanUpBeforeTermination() }
            sender.reply(toApplicationShouldTerminate: shouldTerminate)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUpBeforeTermination()
    }

    private func cleanUpBeforeTermination() {
        guard !didCleanUp else { return }
        didCleanUp = true
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        CommandRouter.shared.globalShortcutRefreshHandler = nil
        globalDateShortcuts.shutdown()
        focusStatusItemController.uninstall()
    }

    @objc private func checkpointForSystemPowerTransition(_ notification: Notification) {
        powerTransitionCheckpoint?()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func configureInitialSize(for window: NSWindow) {
        window.minSize = defaultWindowSize
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let targetHeight = min(defaultWindowSize.height, visibleFrame.height)
        let targetWidth = min(defaultWindowSize.width, visibleFrame.width)
        let targetX = min(max(window.frame.midX - targetWidth / 2, visibleFrame.minX), visibleFrame.maxX - targetWidth)
        let targetY = min(max(window.frame.midY - targetHeight / 2, visibleFrame.minY), visibleFrame.maxY - targetHeight)
        window.setFrame(NSRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight), display: true, animate: false)
    }

    private func configureAndActivateWindows(remainingAttempts: Int) {
        let windows = NSApp.windows.filter { !($0 is NSPanel) }
        guard !windows.isEmpty else {
            guard remainingAttempts > 0 else { return }
            // P3-14 fix: use [weak self] to avoid strong capture in retry loop.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.configureAndActivateWindows(remainingAttempts: remainingAttempts - 1)
            }
            return
        }

        windows.forEach {
            configureInitialSize(for: $0)
            $0.makeKeyAndOrderFront(nil)
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}

@main
struct WeekflowApp: App {
    @NSApplicationDelegateAdaptor(WeekflowAppDelegate.self) private var appDelegate
    @AppStorage(AppAppearancePreference.storageKey)
    private var appearanceRawValue = AppAppearancePreference.defaultValue
    @AppStorage(AppThemePreferences.colorTokenKey)
    private var themeColorToken = AppThemePreferences.defaultColorToken
    @State private var store: WeekflowStore?
    @State private var isLoadingStore = false
    @State private var focusTimer = FocusTimerService()

    var body: some Scene {
        WindowGroup("Weekflow") {
            Group {
                if let store {
                    loadedContent(store)
                } else {
                    ProgressView("正在安全地载入本地数据…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task { await loadStoreIfNeeded() }
                }
            }
            .frame(
                minWidth: WeekflowLayout.windowWidth,
                idealWidth: WeekflowLayout.windowWidth,
                minHeight: WeekflowLayout.windowHeight
            )
            .tint(AppThemePreferences.color(for: themeColorToken))
            .onChange(of: appearanceRawValue) { _, _ in
                appearancePreference.applyToApplication()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Suppress ALL default SwiftUI menus so they never override our
            // custom NSMenu installed via WeekflowApplicationMenu.
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
        .commands {
            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .windowArrangement) {}
            CommandGroup(replacing: .windowList) {}
            CommandGroup(replacing: .help) {}
        }
    }

    @ViewBuilder
    private func loadedContent(_ store: WeekflowStore) -> some View {
        PersistenceProtectedContentView(store: store, focusTimer: focusTimer)
            .environment(\.businessCalendar, store.businessCalendar)
            .onAppear {
                appearancePreference.applyToApplication()
                appDelegate.installFocusStatusItem(timer: focusTimer)
                appDelegate.installPowerTransitionCheckpoint {
                    store.checkpointActiveTaskTimer()
                }
                appDelegate.installTerminationCheckpoint {
                    store.checkpointActiveTaskTimer()
                    return await store.persistForTermination()
                }
                appDelegate.installApplicationMenu {
                    store.addGoal(
                        title: "新的周目标",
                        outcome: "明确本周想达成的结果",
                        endDate: .now
                    )
                }
            }
    }

    @MainActor
    private func loadStoreIfNeeded() async {
        guard store == nil, !isLoadingStore else { return }
        isLoadingStore = true
        defer { isLoadingStore = false }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--development-fixtures") {
            store = WeekflowStore(
                storage: .developmentFixtures(),
                developmentFixture: .stageOne(referenceDate: .now)
            )
            return
        }
#endif
        // 数据安全：打开数据库前，对上一次会话的库做滚动备份（此时库静止，
        // 上一会话关闭时已做 WAL 检查点；不干扰任何打开中的连接）。
        LocalStorage.backupDefaultDatabase()
        let baseStorage = await Task.detached(priority: .userInitiated) { LocalStorage() }.value
        let storage = await LocalStoragePreloader.preload(baseStorage)
        store = WeekflowStore(storage: storage)
    }

    private var appearancePreference: AppAppearancePreference {
        AppAppearancePreference(rawValue: appearanceRawValue) ?? .system
    }
}

private struct PersistenceProtectedContentView: View {
    @Bindable var store: WeekflowStore
    @Bindable var focusTimer: FocusTimerService

    var body: some View {
        if let issue = store.persistenceIssue {
            // Dedicated read-only recovery interface (Section 5.1 requirement).
            // Replaces the previous alert-over-normal-UI approach.
            PersistenceRecoveryView(issue: issue)
        } else {
            ContentView(store: store, focusTimer: focusTimer)
        }
    }
}

/// Full-screen recovery interface shown when persistence fails.
/// P2-2 Fix: Added actual recovery actions instead of just displaying error text.
private struct PersistenceRecoveryView: View {
    let issue: String
    @Environment(\.openURL) private var openURL
    @State private var showDiagnostics = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("本地数据需要检查")
                .font(.title2.bold())

            Text(issue)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 400)

            Text("应用已进入保护模式。原有本地文件不会被主动删除。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            // P2-2 Fix: Recovery action buttons
            VStack(spacing: 12) {
                Button {
                    openDataFolder()
                } label: {
                    Label("打开数据文件夹", systemImage: "folder")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 12) {
                    Button {
                        copyErrorDetails()
                    } label: {
                        Label("复制错误详情", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        retryConnection()
                    } label: {
                        Label("重试连接", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出应用", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func openDataFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dataFolder = appSupport.appendingPathComponent("Weekflow", isDirectory: true)
        NSWorkspace.shared.open(dataFolder)
    }

    private func copyErrorDetails() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(issue, forType: .string)
    }

    private func retryConnection() {
        // P3-13 fix: The retry action terminates and relaunches the app so the
        // Store is re-initialized from disk. A plain window close + relaunch is
        // the safest recovery path for a corrupted persistence session.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dataFolder = appSupport.appendingPathComponent("Weekflow", isDirectory: true)
        // Remove the failure marker so the next launch attempts a fresh connection.
        let failureMarker = dataFolder.appendingPathComponent("Database/persistence-failure.json")
        try? FileManager.default.removeItem(at: failureMarker)
        // Relaunch: open a new instance then terminate the current one.
        if let appURL = Bundle.main.bundleURL as URL? {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [appURL.path]
            try? task.run()
        }
        NSApplication.shared.terminate(nil)
    }
}
