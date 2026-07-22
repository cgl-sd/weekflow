import AppKit
import Carbon.HIToolbox

/// Registers the user-selected Shift shortcuts system-wide for Weekflow's day
/// navigation, including while another application is frontmost.
final class GlobalDateShortcutService {
    private enum Action: UInt32, CaseIterable {
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

        var notification: Notification.Name {
            switch self {
            case .today: .weekflowJumpToToday
            case .previousDay: .weekflowJumpToPreviousDay
            case .nextDay: .weekflowJumpToNextDay
            }
        }
    }

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    func install() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let service = Unmanaged<GlobalDateShortcutService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return service.handle(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { return }

        let modifiers = UInt32(shiftKey)
        for action in Action.allCases {
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: action.rawValue)
            if RegisterEventHotKey(
                action.keyCode,
                modifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &reference
            ) == noErr, let reference {
                hotKeys.append(reference)
            }
        }
    }

    deinit {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
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
        guard status == noErr,
              identifier.signature == Self.signature,
              let action = Action(rawValue: identifier.id) else { return status }
        DispatchQueue.main.async {
            WeekflowCommand.post(action.notification)
        }
        return noErr
    }

    private static let signature: OSType = 0x57464C57 // WFLW
}
