import Foundation
import Observation
import UserNotifications

@MainActor
protocol FocusNotificationScheduling: AnyObject {
    func requestPermission()
    func sendCompletion(mode: FocusMode, minutes: Int)
}

@MainActor
final class SystemFocusNotificationScheduler: FocusNotificationScheduling {
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func sendCompletion(mode: FocusMode, minutes: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(mode.title)结束"
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

    private(set) var selectedMode: FocusMode = .meditation
    private(set) var remainingSeconds: Int
    private(set) var totalSeconds: Int
    private(set) var isRunning = false
    private(set) var hasStarted = false
    private(set) var linkedTask: TaskReference?
    private(set) var linkedTaskTitle: String?
    private(set) var configuredMinutes: [FocusMode: Int]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationScheduler: FocusNotificationScheduling
    @ObservationIgnored private var taskWriter: ((TaskReference, Int) -> Void)?
    @ObservationIgnored private var focusWriter: ((FocusMode, Int, Date) -> Void)?
    @ObservationIgnored private var unloggedSeconds = 0
    @ObservationIgnored private var lastTickDate: Date?

    init(
        defaults: UserDefaults = .standard,
        notificationScheduler: FocusNotificationScheduling = SystemFocusNotificationScheduler()
    ) {
        self.defaults = defaults
        self.notificationScheduler = notificationScheduler
        var durations: [FocusMode: Int] = [:]
        for mode in FocusMode.allCases {
            let stored = defaults.integer(forKey: Self.durationKey(for: mode))
            durations[mode] = stored > 0 ? stored : mode.defaultMinutes
        }
        configuredMinutes = durations
        let initialSeconds = (durations[.meditation] ?? FocusMode.meditation.defaultMinutes) * 60
        remainingSeconds = initialSeconds
        totalSeconds = initialSeconds
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

    func minutes(for mode: FocusMode) -> Int {
        configuredMinutes[mode] ?? mode.defaultMinutes
    }

    func updateMinutes(_ minutes: Int, for mode: FocusMode) {
        guard !isRunning else { return }
        let clamped = min(
            max(minutes, Self.minimumDurationMinutes),
            Self.maximumDurationMinutes
        )
        configuredMinutes[mode] = clamped
        defaults.set(clamped, forKey: Self.durationKey(for: mode))
        if selectedMode == mode {
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
            updateMinutes(clamped, for: selectedMode)
        } else {
            resetCountdown(seconds: clamped * 60)
        }
    }

    func select(_ mode: FocusMode) {
        guard !isRunning else { return }
        guard selectedMode != mode else { return }
        selectedMode = mode
        linkedTask = nil
        linkedTaskTitle = nil
        resetCountdown(seconds: minutes(for: mode) * 60)
    }

    func configureTaskWriter(_ writer: @escaping (TaskReference, Int) -> Void) {
        taskWriter = writer
    }

    func configureFocusWriter(_ writer: @escaping (FocusMode, Int, Date) -> Void) {
        focusWriter = writer
    }

    func linkTask(_ reference: TaskReference, title: String, estimatedMinutes: Int) {
        guard !isRunning else { return }
        linkedTask = reference
        linkedTaskTitle = title
        resetCountdown(seconds: max(estimatedMinutes, 1) * 60)
    }

    func clearLinkedTask() {
        guard !isRunning else { return }
        linkedTask = nil
        linkedTaskTitle = nil
        resetCountdown(seconds: minutes(for: selectedMode) * 60)
    }

    func start(now: Date = .now) {
        if remainingSeconds <= 0 {
            resetCountdown(seconds: minutes(for: selectedMode) * 60)
        }
        notificationScheduler.requestPermission()
        hasStarted = true
        isRunning = true
        lastTickDate = now
        installTimer()
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
        flushElapsedTime()
    }

    func cancel() {
        if isRunning { reconcileAfterInactivity() }
        timer?.invalidate()
        timer = nil
        isRunning = false
        hasStarted = false
        lastTickDate = nil
        flushElapsedTime()
        linkedTask = nil
        linkedTaskTitle = nil
        resetCountdown(seconds: minutes(for: selectedMode) * 60)
    }

    func stop() {
        cancel()
    }

    /// Used by global controls such as the menu bar. Any elapsed work is
    /// settled before the new mode becomes active, so switching never drops
    /// task actual time or focus records.
    func stopAndSelect(_ mode: FocusMode) {
        guard selectedMode != mode else { return }
        if isRunning || hasStarted || linkedTask != nil {
            stop()
        }
        select(mode)
    }

    func advance(by seconds: Int) {
        guard isRunning, seconds > 0 else { return }
        let elapsed = min(seconds, remainingSeconds)
        remainingSeconds -= elapsed
        unloggedSeconds += elapsed
        if let lastTickDate { self.lastTickDate = lastTickDate.addingTimeInterval(TimeInterval(elapsed)) }
        guard remainingSeconds == 0 else { return }
        timer?.invalidate()
        timer = nil
        isRunning = false
        hasStarted = false
        lastTickDate = nil
        flushElapsedTime()
        notificationScheduler.sendCompletion(mode: selectedMode, minutes: totalSeconds / 60)
    }

    func reconcileAfterInactivity(now: Date = .now) {
        guard isRunning, let lastTickDate else { return }
        let elapsed = max(Int(now.timeIntervalSince(lastTickDate)), 0)
        guard elapsed > 0 else { return }
        advance(by: elapsed)
        if isRunning { self.lastTickDate = now }
    }

    private func installTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcileAfterInactivity() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func resetCountdown(seconds: Int) {
        remainingSeconds = max(seconds, 1)
        totalSeconds = max(seconds, 1)
        hasStarted = false
        unloggedSeconds = 0
    }

    private func flushElapsedTime(at date: Date = .now) {
        guard unloggedSeconds > 0 else {
            unloggedSeconds = 0
            return
        }
        let elapsedMinutes = max(Int(ceil(Double(unloggedSeconds) / 60)), 1)
        if let linkedTask {
            taskWriter?(linkedTask, elapsedMinutes)
        }
        focusWriter?(selectedMode, elapsedMinutes, date)
        unloggedSeconds = 0
    }

    private static func durationKey(for mode: FocusMode) -> String {
        "weekflow.focus.duration.\(mode.rawValue)"
    }
}
