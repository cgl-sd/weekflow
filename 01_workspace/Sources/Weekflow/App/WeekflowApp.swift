import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class WeekflowAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let globalDateShortcuts = GlobalDateShortcutService()
    private let focusStatusItemController = FocusStatusItemController()
    private let applicationMenu = WeekflowApplicationMenu()
    private let defaultWindowSize = NSSize(
        width: WeekflowLayout.windowWidth,
        height: WeekflowLayout.windowHeight
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        globalDateShortcuts.install()
        UNUserNotificationCenter.current().delegate = self
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

    func applicationWillTerminate(_ notification: Notification) {
        focusStatusItemController.uninstall()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.configureAndActivateWindows(remainingAttempts: remainingAttempts - 1)
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
        WindowGroup("Workflow") {
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
    @State private var showsPersistenceIssue: Bool

    init(store: WeekflowStore, focusTimer: FocusTimerService) {
        self.store = store
        self.focusTimer = focusTimer
        _showsPersistenceIssue = State(initialValue: store.persistenceIssue != nil)
    }

    var body: some View {
        ContentView(store: store, focusTimer: focusTimer)
            .alert("本地数据需要检查", isPresented: $showsPersistenceIssue) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(store.persistenceIssue ?? "")
            }
            .onChange(of: store.persistenceIssue) { _, issue in
                if issue != nil { showsPersistenceIssue = true }
            }
    }
}
