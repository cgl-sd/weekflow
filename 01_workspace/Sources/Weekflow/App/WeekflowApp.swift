import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class WeekflowAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let globalDateShortcuts = GlobalDateShortcutService()
    private let focusStatusItemController = FocusStatusItemController()
    private let applicationMenu = WeekflowApplicationMenu()
    private var checkpointActiveTimer: (() -> Void)?
    /// P0-1 fix: synchronous termination persist callback.
    private var terminationPersist: (() -> Void)?
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.applicationMenu.install()
        }
    }

    func installActiveTimerCheckpoint(_ checkpoint: @escaping () -> Void) {
        checkpointActiveTimer = checkpoint
    }

    /// P0-1 fix: installs the synchronous termination persist callback.
    func installTerminationPersist(_ persist: @escaping () -> Void) {
        terminationPersist = persist
    }

    func applicationWillTerminate(_ notification: Notification) {
        checkpointActiveTimer?()
        // P0-1 fix: flush any pending async writes synchronously before exit.
        terminationPersist?()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        CommandRouter.shared.globalShortcutRefreshHandler = nil
        globalDateShortcuts.shutdown()
        focusStatusItemController.uninstall()
    }

    @objc private func checkpointForSystemPowerTransition(_ notification: Notification) {
        checkpointActiveTimer?()
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
    @State private var store: WeekflowStore
    @State private var focusTimer = FocusTimerService()

    init() {
        _store = State(initialValue: Self.makeStore())
    }

    private static func makeStore() -> WeekflowStore {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--development-fixtures") {
            return WeekflowStore(
                storage: .developmentFixtures(),
                developmentFixture: .stageOne(referenceDate: .now)
            )
        }
#endif
        return WeekflowStore()
    }

    var body: some Scene {
        WindowGroup("Weekflow") {
            PersistenceProtectedContentView(store: store, focusTimer: focusTimer)
                .frame(
                    minWidth: WeekflowLayout.windowWidth,
                    idealWidth: WeekflowLayout.windowWidth,
                    minHeight: WeekflowLayout.windowHeight
                )
                .tint(AppThemePreferences.color(for: themeColorToken))
                .onAppear {
                    appearancePreference.applyToApplication()
                    appDelegate.installFocusStatusItem(timer: focusTimer)
                    appDelegate.installActiveTimerCheckpoint {
                        store.checkpointActiveTaskTimer()
                    }
                    // P0-1 fix: ensure pending writes are flushed on termination.
                    appDelegate.installTerminationPersist {
                        store.persistForTermination()
                    }
                    appDelegate.installApplicationMenu {
                        store.addGoal(
                            title: "新的周目标",
                            outcome: "明确本周想达成的结果",
                            endDate: .now
                        )
                    }
                }
                .onChange(of: appearanceRawValue) { _, _ in
                    appearancePreference.applyToApplication()
                }
        }
        .windowStyle(.hiddenTitleBar)
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
