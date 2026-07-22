import AppKit
import Carbon.HIToolbox
import Foundation

enum GlobalDateShortcutPreferences {
    static let enabledKey = "globalDateShortcuts.enabled"
    static let stateKey = "globalDateShortcuts.registrationState"
    static let errorKey = "globalDateShortcuts.registrationError"

    // Global shortcuts are intentionally opt-in. These combinations contain
    // both Command and Option and therefore never steal Shift-only editing.
    static let modifierFlags = UInt32(cmdKey | optionKey)
}

enum GlobalDateShortcutRegistrationState: String {
    case disabled
    case active
    case failed
}

struct GlobalDateShortcutDescriptor: Equatable {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
}

protocol GlobalDateShortcutBackend: AnyObject {
    func install(
        descriptors: [GlobalDateShortcutDescriptor],
        onAction: @escaping (UInt32) -> Void
    ) throws
    func uninstall()
}

enum GlobalDateShortcutError: LocalizedError, Equatable {
    case eventHandler(OSStatus)
    case registration(actionID: UInt32, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case let .eventHandler(status):
            "无法监听全局快捷键（系统错误 \(status)）。"
        case let .registration(actionID, status):
            "快捷键 \(actionID) 注册失败，可能已被其他应用占用（系统错误 \(status)）。"
        }
    }
}

/// Owns the complete lifecycle of Weekflow's optional global date shortcuts.
/// Registration is transactional: any individual conflict unregisters the
/// complete set so Weekflow never remains in a partially configured state.
final class GlobalDateShortcutService {
    enum Action: UInt32, CaseIterable {
        case today = 1
        case previousDay = 2
        case nextDay = 3

        var keyCode: UInt32 {
            switch self {
            case .today: UInt32(kVK_Space)
            case .previousDay: UInt32(kVK_LeftArrow)
            case .nextDay: UInt32(kVK_RightArrow)
            }
        }

        var command: AppCommand {
            switch self {
            case .today: .jumpToToday
            case .previousDay: .jumpToPreviousDay
            case .nextDay: .jumpToNextDay
            }
        }
    }

    private let defaults: UserDefaults
    private let backend: GlobalDateShortcutBackend

    init(
        defaults: UserDefaults = .standard,
        backend: GlobalDateShortcutBackend = CarbonGlobalDateShortcutBackend()
    ) {
        self.defaults = defaults
        self.backend = backend
    }

    func refresh() {
        backend.uninstall()
        guard defaults.bool(forKey: GlobalDateShortcutPreferences.enabledKey) else {
            publish(state: .disabled, error: nil)
            return
        }

        let descriptors = Action.allCases.map {
            GlobalDateShortcutDescriptor(
                id: $0.rawValue,
                keyCode: $0.keyCode,
                modifiers: GlobalDateShortcutPreferences.modifierFlags
            )
        }
        do {
            try backend.install(descriptors: descriptors) { actionID in
                guard let action = Action(rawValue: actionID) else { return }
                DispatchQueue.main.async {
                    CommandRouter.shared.send(action.command)
                }
            }
            publish(state: .active, error: nil)
        } catch {
            backend.uninstall()
            publish(
                state: .failed,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    func shutdown() {
        backend.uninstall()
        publish(state: .disabled, error: nil)
    }

    deinit {
        backend.uninstall()
    }

    private func publish(state: GlobalDateShortcutRegistrationState, error: String?) {
        defaults.set(state.rawValue, forKey: GlobalDateShortcutPreferences.stateKey)
        if let error {
            defaults.set(error, forKey: GlobalDateShortcutPreferences.errorKey)
        } else {
            defaults.removeObject(forKey: GlobalDateShortcutPreferences.errorKey)
        }
    }
}

final class CarbonGlobalDateShortcutBackend: GlobalDateShortcutBackend {
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var onAction: ((UInt32) -> Void)?

    func install(
        descriptors: [GlobalDateShortcutDescriptor],
        onAction: @escaping (UInt32) -> Void
    ) throws {
        uninstall()
        self.onAction = onAction
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                return Unmanaged<CarbonGlobalDateShortcutBackend>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .handle(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            uninstall()
            throw GlobalDateShortcutError.eventHandler(status)
        }

        do {
            for descriptor in descriptors {
                var reference: EventHotKeyRef?
                let identifier = EventHotKeyID(signature: Self.signature, id: descriptor.id)
                let registrationStatus = RegisterEventHotKey(
                    descriptor.keyCode,
                    descriptor.modifiers,
                    identifier,
                    GetApplicationEventTarget(),
                    0,
                    &reference
                )
                guard registrationStatus == noErr, let reference else {
                    throw GlobalDateShortcutError.registration(
                        actionID: descriptor.id,
                        status: registrationStatus
                    )
                }
                hotKeys.append(reference)
            }
        } catch {
            uninstall()
            throw error
        }
    }

    func uninstall() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onAction = nil
    }

    private func handle(_ event: EventRef) -> OSStatus {
        var identifier = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &identifier
        )
        guard status == noErr, identifier.signature == Self.signature else { return status }
        onAction?(identifier.id)
        return noErr
    }

    private static let signature: OSType = 0x57464C57 // WFLW
}
