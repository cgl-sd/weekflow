import Foundation

/// Debounce utility for text input persistence. Delays execution until a quiet
/// period has elapsed, preventing excessive writes during rapid typing (P1-7).
///
/// Usage:
/// ```swift
/// let debouncer = PersistenceDebouncer(interval: .milliseconds(300))
/// func titleChanged(_ newTitle: String) {
///     debouncer.schedule { persistTitle(newTitle) }
/// }
/// ```
@MainActor
final class PersistenceDebouncer {
    private let interval: Duration
    private var pendingTask: Task<Void, Never>?
    private var pendingAction: (@MainActor () -> Void)?

    /// Creates a debouncer with the given quiet-period interval.
    /// - Parameter interval: Default is 300 ms, suitable for text input.
    init(interval: Duration = .milliseconds(300)) {
        self.interval = interval
    }

    /// Schedules `action` to run after the quiet period. If called again before
    /// the period elapses, the previous pending action is cancelled.
    func schedule(_ action: @escaping @MainActor () -> Void) {
        pendingTask?.cancel()
        pendingAction = action
        pendingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.interval)
            guard !Task.isCancelled else { return }
            let action = self.pendingAction
            self.pendingAction = nil
            self.pendingTask = nil
            action?()
        }
    }

    /// Immediately executes any pending action and cancels the timer (P3-12 fix).
    /// Used when the view disappears or the user commits the edit explicitly.
    func flush() {
        pendingTask?.cancel()
        pendingTask = nil
        let action = pendingAction
        pendingAction = nil
        action?()
    }

    /// Cancels any pending action without executing it.
    /// Used during app termination where the final state is persisted separately.
    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        pendingAction = nil
    }

    /// Whether a debounced action is currently pending.
    var isPending: Bool { pendingTask != nil }
}
