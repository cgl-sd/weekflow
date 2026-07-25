import Foundation
import Observation
import SwiftUI
import UserNotifications

@MainActor
protocol FocusNotificationScheduling: AnyObject {
    func requestPermission()
    func requestPermission(completion: @escaping @MainActor (Bool) -> Void)
    func sendCompletion(modeTitle: String, minutes: Int)
}

extension FocusNotificationScheduling {
    func requestPermission(completion: @escaping @MainActor (Bool) -> Void) {
        requestPermission()
        completion(true)
    }
}

@MainActor
final class SystemFocusNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {
        requestPermission { _ in }
    }

    func requestPermission(completion: @escaping @MainActor (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in completion(granted) }
        }
    }

    func sendCompletion(modeTitle: String, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(modeTitle)结束"
        content.body = "本次 \(minutes) 分钟专注已经完成。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "weekflow.focus.completed", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
@Observable
final class FocusTimerService {
    static let minimumDurationMinutes = 5
    static let maximumDurationMinutes = 240
    static let durationStepMinutes = 5

    private(set) var selectedModeID: String = "meditation"
    private(set) var remainingSeconds: Int
    private(set) var totalSeconds: Int
    private(set) var isRunning = false
    private(set) var hasStarted = false
    private(set) var linkedTask: TaskReference?
    private(set) var linkedTaskTitle: String?
    private(set) var configuredMinutes: [String: Int]
    private(set) var notificationPermissionIssue: String?

    /// Resolved display properties for the selected mode.
    var selectedModeConfig: FocusModeConfig {
        FocusModePreferences.mode(for: selectedModeID) ?? FocusModeConfig.builtInMeditation
    }
    var selectedModeTitle: String { selectedModeConfig.title }
    var selectedModeSymbol: String { selectedModeConfig.iconName }
    var selectedModeColor: Color { selectedModeConfig.color }
    var selectedModeRunningSymbol: String { selectedModeConfig.runningSymbol }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationScheduler: FocusNotificationScheduling
    @ObservationIgnored private var taskWriter: ((TaskReference, Int) -> Void)?
    @ObservationIgnored private var focusWriter: ((String, Int, Date) -> Void)?
    @ObservationIgnored private var unloggedSeconds = 0
    @ObservationIgnored private var lastTickDate: Date?
    @ObservationIgnored private let continuousClock = ContinuousClock()
    @ObservationIgnored private var lastTickInstant: ContinuousClock.Instant?
    /// P1-8 fix: counts seconds since the last snapshot write so we persist
    /// periodically (every ~30s) while running, not on every tick.
    @ObservationIgnored private var secondsSinceSnapshot = 0
    /// P1-8 fix: interval between periodic focus-session snapshots.
    private static let snapshotIntervalSeconds = 30
    private static let sessionKey = "weekflow.focus.activeSession.v1"

    init(
        defaults: UserDefaults = .standard,
        notificationScheduler: FocusNotificationScheduling = SystemFocusNotificationScheduler()
    ) {
        self.defaults = defaults
        self.notificationScheduler = notificationScheduler
        var durations: [String: Int] = [:]
        for mode in FocusModePreferences.modes {
            let stored = defaults.integer(forKey: Self.durationKey(for: mode.id))
            durations[mode.id] = stored > 0 ? stored : 60
        }
        configuredMinutes = durations
        let initialSeconds = (durations["meditation"] ?? 60) * 60
        remainingSeconds = initialSeconds
        totalSeconds = initialSeconds
        // P1-8 fix: recover an interrupted focus session if one was persisted.
        restorePersistedSession()
    }

    var formattedRemaining: String {
        if remainingSeconds >= 100 * 60 {
            return String(
                format: "%02d:%02d:%02d",
                remainingSeconds / 3_600,
                (remainingSeconds % 3_600) / 60,
                remainingSeconds % 60
            )
        }
        return String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    var currentDurationMinutes: Int {
        max(Int(ceil(Double(totalSeconds) / 60)), 1)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return 1 - Double(remainingSeconds) / Double(totalSeconds)
    }

    func minutes(for modeID: String) -> Int {
        configuredMinutes[modeID] ?? 60
    }

    func updateMinutes(_ minutes: Int, for modeID: String) {
        guard !isRunning else { return }
        let clamped = min(
            max(minutes, Self.minimumDurationMinutes),
            Self.maximumDurationMinutes
        )
        configuredMinutes[modeID] = clamped
        defaults.set(clamped, forKey: Self.durationKey(for: modeID))
        if selectedModeID == modeID {
            resetCountdown(seconds: clamped * 60)
        }
    }

    /// Updates the duration through the countdown itself. Independent sessions
    /// remember the value per mode; task-linked sessions retain the task as the
    /// source of truth and only update the current countdown.
    func updateCurrentDurationMinutes(_ minutes: Int) {
        guard !isRunning else { return }
        let clamped = min(
            max(minutes, Self.minimumDurationMinutes),
            Self.maximumDurationMinutes
        )
        if linkedTask == nil {
            updateMinutes(clamped, for: selectedModeID)
        } else {
            resetCountdown(seconds: clamped * 60)
        }
    }

    func select(_ modeID: String) {
        guard !isRunning else { return }
        guard selectedModeID != modeID else { return }
        selectedModeID = modeID
        linkedTask = nil
        linkedTaskTitle = nil
        resetCountdown(seconds: minutes(for: modeID) * 60)
    }

    /// Configures the callback that receives raw elapsed **seconds** for a
    /// linked task. Accumulation is always in seconds; minute conversion is
    /// the receiver's responsibility (see `DurationDisplay.minutes(for:)`).
    func configureTaskWriter(_ writer: @escaping (TaskReference, Int) -> Void) {
        taskWriter = writer
    }

    /// Configures the callback that receives raw elapsed **seconds** for a
    /// focus session. Accumulation is always in seconds; minute conversion is
    /// the receiver's responsibility (see `DurationDisplay.minutes(for:)`).
    func configureFocusWriter(_ writer: @escaping (String, Int, Date) -> Void) {
        focusWriter = writer
    }

    func linkTask(_ reference: TaskReference, title: String, estimatedMinutes: Int) {
        guard !isRunning else { return }
        linkedTask = reference
        linkedTaskTitle = title
        resetCountdown(seconds: max(estimatedMinutes, 1) * 60)
        persistSnapshot()
    }

    func clearLinkedTask() {
        guard !isRunning else { return }
        linkedTask = nil
        linkedTaskTitle = nil
        resetCountdown(seconds: minutes(for: selectedModeID) * 60)
        persistSnapshot()
    }

    func start(now: Date = .now) {
        if remainingSeconds <= 0 {
            resetCountdown(seconds: minutes(for: selectedModeID) * 60)
        }
        notificationScheduler.requestPermission { [weak self] granted in
            self?.notificationPermissionIssue = granted
                ? nil
                : "通知权限已关闭；计时仍会保存，但结束时不会显示系统通知。"
        }
        hasStarted = true
        isRunning = true
        lastTickDate = now
        lastTickInstant = continuousClock.now
        installTimer()
        persistSnapshot(at: now)
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func pause() {
        guard isRunning else { return }
        reconcileAfterInactivity()
        isRunning = false
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
        lastTickInstant = nil
        flushElapsedTime()
        persistSnapshot()
    }

    func cancel() {
        if isRunning { reconcileAfterInactivity() }
        timer?.invalidate()
        timer = nil
        isRunning = false
        hasStarted = false
        lastTickDate = nil
        lastTickInstant = nil
        flushElapsedTime()
        linkedTask = nil
        linkedTaskTitle = nil
        resetCountdown(seconds: minutes(for: selectedModeID) * 60)
        clearSnapshot()
    }

    func stop() {
        cancel()
    }

    /// Used by global controls such as the menu bar. Any elapsed work is
    /// settled before the new mode becomes active, so switching never drops
    /// task actual time or focus records.
    func stopAndSelect(_ modeID: String) {
        guard selectedModeID != modeID else { return }
        if isRunning || hasStarted || linkedTask != nil {
            stop()
        }
        select(modeID)
    }

    /// Flushes accumulated seconds to the configured writers without stopping
    /// the timer. Used for unified checkpoint on app exit, sleep, wake and
    /// task switch so no elapsed work is lost between flushes.
    func checkpoint(now: Date = .now) {
        guard isRunning || hasStarted else { return }
        reconcileAfterInactivity()
        flushElapsedTime(at: now)
        persistSnapshot(at: now)
    }

    func advance(by seconds: Int) {
        guard isRunning, seconds > 0 else { return }
        let elapsed = min(seconds, remainingSeconds)
        remainingSeconds -= elapsed
        unloggedSeconds += elapsed
        if let lastTickDate { self.lastTickDate = lastTickDate.addingTimeInterval(TimeInterval(elapsed)) }
        lastTickInstant = continuousClock.now
        // P1-8 fix: periodically snapshot the running session so a crash loses
        // at most ~30s of elapsed work.
        secondsSinceSnapshot += elapsed
        if secondsSinceSnapshot >= Self.snapshotIntervalSeconds {
            persistSnapshot()
        }
        guard remainingSeconds == 0 else { return }
        timer?.invalidate()
        timer = nil
        isRunning = false
        hasStarted = false
        lastTickDate = nil
        lastTickInstant = nil
        flushElapsedTime()
        clearSnapshot()
        notificationScheduler.sendCompletion(modeTitle: selectedModeTitle, minutes: totalSeconds / 60)
    }

    /// P3-15 fix: maximum seconds that a single reconciliation step may advance.
    /// Prevents an entire night's sleep from being counted as focus time.
    private static let maximumReconcileStepSeconds = 120

    func reconcileAfterInactivity() {
        guard isRunning, let lastTickInstant else { return }
        let duration = lastTickInstant.duration(to: continuousClock.now)
        // P3-15 fix: cap elapsed to avoid counting device sleep as focus time.
        let elapsed = min(max(Int(duration.components.seconds), 0), Self.maximumReconcileStepSeconds)
        guard elapsed > 0 else { return }
        advance(by: elapsed)
        if isRunning {
            self.lastTickInstant = continuousClock.now
            self.lastTickDate = .now
        }
    }

    /// Deterministic wall-clock reconciliation used for cross-restart recovery
    /// and tests. Runtime ticks use the monotonic overload above.
    func reconcileAfterInactivity(now: Date) {
        guard isRunning, let lastTickDate else { return }
        // P3-15 fix: cap elapsed to avoid counting device sleep as focus time.
        let elapsed = min(max(Int(now.timeIntervalSince(lastTickDate)), 0), Self.maximumReconcileStepSeconds)
        guard elapsed > 0 else { return }
        advance(by: elapsed)
        if isRunning {
            self.lastTickDate = now
            self.lastTickInstant = continuousClock.now
        }
    }

    private func installTimer() {
        timer?.invalidate()
        // P2-11 fix: the Timer fires on the main RunLoop so we are already on
        // MainActor; avoid allocating a Task object every tick.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconcileAfterInactivity()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func resetCountdown(seconds: Int) {
        remainingSeconds = max(seconds, 1)
        totalSeconds = max(seconds, 1)
        hasStarted = false
        unloggedSeconds = 0
        secondsSinceSnapshot = 0
    }

    private func flushElapsedTime(at date: Date = .now) {
        guard unloggedSeconds > 0 else {
            unloggedSeconds = 0
            return
        }
        if let linkedTask {
            taskWriter?(linkedTask, unloggedSeconds)
        }
        focusWriter?(selectedModeID, unloggedSeconds, date)
        unloggedSeconds = 0
    }

    private static func durationKey(for modeID: String) -> String {
        "weekflow.focus.duration.\(modeID)"
    }

    // MARK: - Crash Recovery (P1-8)

    /// Persists the current countdown state so it can survive a crash or
    /// forced termination. Called on every meaningful state change and
    /// periodically while running.
    private func persistSnapshot(at date: Date = .now) {
        secondsSinceSnapshot = 0
        let session = FocusTimerSession(
            modeID: selectedModeID,
            totalSeconds: totalSeconds,
            remainingSeconds: remainingSeconds,
            unloggedSeconds: unloggedSeconds,
            hasStarted: hasStarted,
            isRunning: isRunning,
            linkedTask: linkedTask,
            linkedTaskTitle: linkedTaskTitle,
            lastCheckpointAt: date
        )
        guard let data = try? JSONEncoder().encode(session) else {
            // C-1 fix: log encoding failure (session won't survive restart).
            NSLog("[Weekflow] 专注计时器会话编码失败，重启后无法恢复")
            return
        }
        defaults.set(data, forKey: Self.sessionKey)
    }

    /// Removes the persisted snapshot once a session is finished or cancelled,
    /// so the next launch does not resurrect a completed countdown.
    private func clearSnapshot() {
        secondsSinceSnapshot = 0
        defaults.removeObject(forKey: Self.sessionKey)
    }

    /// Recovers an interrupted focus session persisted by a previous run.
    /// P0-5 fix: only folds offline elapsed time if the timer was actively
    /// running when the snapshot was persisted. A paused session (isRunning == false)
    /// must NOT accumulate offline time.
    private func restorePersistedSession(now: Date = .now) {
        guard let data = defaults.data(forKey: Self.sessionKey),
              let session = try? JSONDecoder().decode(FocusTimerSession.self, from: data) else {
            return
        }
        selectedModeID = session.modeID
        totalSeconds = max(session.totalSeconds, 1)
        remainingSeconds = max(session.remainingSeconds, 0)
        unloggedSeconds = max(session.unloggedSeconds, 0)
        linkedTask = session.linkedTask
        linkedTaskTitle = session.linkedTaskTitle
        hasStarted = session.hasStarted
        // P0-5 fix: only fold offline time if the timer was RUNNING when persisted.
        // For backward compatibility, if isRunning is nil (old snapshot), fall back
        // to hasStarted (old behavior).
        let wasRunning = session.isRunning ?? session.hasStarted
        if wasRunning {
            let offline = max(Int(now.timeIntervalSince(session.lastCheckpointAt)), 0)
            // Cap offline recovery to the same maximum as runtime reconciliation.
            // Prevents hours of offline time from being silently counted as focus.
            let consumed = min(offline, remainingSeconds, Self.maximumReconcileStepSeconds)
            if consumed > 0 {
                remainingSeconds -= consumed
                unloggedSeconds += consumed
            }
            lastTickDate = now
            lastTickInstant = continuousClock.now
        }
        // Remain paused; checkpoint will flush recovered unlogged seconds.
        isRunning = false
    }
}
