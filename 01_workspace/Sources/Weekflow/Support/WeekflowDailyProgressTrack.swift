import SwiftUI

struct WeekflowDailyProgressTrack: View {
    let fraction: Double
    let hasProgress: Bool
    var alwaysVisible = false
    let accessibilityLabel: String
    let accessibilityValue: String

    @AppStorage(DailyProgressPreferences.colorTokenKey)
    private var colorToken = DailyProgressPreferences.defaultColorToken
    @AppStorage(DailyProgressPreferences.alwaysShowKey)
    private var alwaysShowPreference = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(showsEmptyTrack
                        ? WeekflowPalette.progressTrackEmpty
                        : WeekflowPalette.border.opacity(0.5))
                    .overlay {
                        if showsEmptyTrack {
                            Capsule().stroke(WeekflowPalette.border.opacity(0.55), lineWidth: 1)
                        }
                    }
                Capsule()
                    .fill(DailyProgressPreferences.color(for: colorToken))
                    .frame(width: proxy.size.width * normalizedFraction)
            }
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: normalizedFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHidden(!isVisible)
    }

    private var normalizedFraction: Double {
        min(max(fraction, 0), 1)
    }

    private var showsEmptyTrack: Bool {
        alwaysVisible || alwaysShowPreference
    }

    private var isVisible: Bool {
        alwaysVisible || DailyProgressPreferences.isVisible(
            hasProgress: hasProgress,
            alwaysShow: alwaysShowPreference
        )
    }
}
