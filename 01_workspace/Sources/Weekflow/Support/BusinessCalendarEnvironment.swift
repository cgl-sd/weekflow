import SwiftUI

/// P2-⑦: the business calendar is provided through the SwiftUI Environment
/// instead of the process-global `SystemBusinessCalendar.current`. The root view
/// injects the Store's calendar; views read it via `@Environment(\.businessCalendar)`.
/// This removes the hidden global dependency from the view layer (better test
/// isolation and multi-window/preview safety). The default is an autoupdating
/// calendar so previews/tests without an explicit injection still behave sanely.
private struct BusinessCalendarEnvironmentKey: EnvironmentKey {
    static let defaultValue: any BusinessCalendarProviding = BusinessCalendar()
}

extension EnvironmentValues {
    var businessCalendar: any BusinessCalendarProviding {
        get { self[BusinessCalendarEnvironmentKey.self] }
        set { self[BusinessCalendarEnvironmentKey.self] = newValue }
    }
}
