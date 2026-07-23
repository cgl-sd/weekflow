import Foundation

/// Thread-safe, stack-ordered scoped override storage.
///
/// An explicit override always wins. Scoped values are otherwise resolved by
/// most-recent installation. Releasing a lease removes only its own value, so
/// stores and tests cannot accidentally clear one another's calendar.
final class ScopedOverrideRegistry<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var explicitValue: Value?
    private var scopedValues: [UUID: Value] = [:]
    private var scopedOrder: [UUID] = []

    var explicitOverride: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return explicitValue
        }
        set {
            lock.lock()
            explicitValue = newValue
            lock.unlock()
        }
    }

    var current: Value? {
        lock.lock()
        defer { lock.unlock() }
        if let explicitValue { return explicitValue }
        guard let id = scopedOrder.last else { return nil }
        return scopedValues[id]
    }

    func install(_ value: Value) -> ScopedOverrideLease {
        let id = UUID()
        lock.lock()
        scopedValues[id] = value
        scopedOrder.append(id)
        lock.unlock()
        return ScopedOverrideLease { [weak self] in
            self?.remove(id: id)
        }
    }

    private func remove(id: UUID) {
        lock.lock()
        scopedValues[id] = nil
        scopedOrder.removeAll { $0 == id }
        lock.unlock()
    }
}

final class ScopedOverrideLease: @unchecked Sendable {
    private let release: @Sendable () -> Void
    private let lock = NSLock()
    private var hasReleased = false

    init(release: @Sendable @escaping () -> Void) {
        self.release = release
    }

    func cancel() {
        lock.lock()
        guard !hasReleased else {
            lock.unlock()
            return
        }
        hasReleased = true
        lock.unlock()
        release()
    }

    deinit {
        cancel()
    }
}
