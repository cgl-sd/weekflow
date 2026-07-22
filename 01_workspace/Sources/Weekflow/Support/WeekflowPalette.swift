import AppKit
import SwiftUI

enum WeekflowPalette {
    static let appBackground = adaptive(
        light: rgb(0.961, 0.965, 0.969),
        dark: rgb(0.082, 0.090, 0.102)
    )
    static let sidebarBackground = adaptive(
        light: rgb(0.945, 0.949, 0.953),
        dark: rgb(0.105, 0.116, 0.130)
    )
    static let surface = adaptive(
        light: rgb(1, 1, 1),
        dark: rgb(0.137, 0.151, 0.169)
    )
    static let surfaceHover = adaptive(
        light: rgb(0.957, 0.961, 0.965),
        dark: rgb(0.169, 0.184, 0.204)
    )
    static let surfaceSelected = adaptive(
        light: rgb(0.914, 0.922, 0.933),
        dark: rgb(0.204, 0.224, 0.251)
    )
    /// A quieter neutral surface for detached utility panels. Unlike the
    /// regular card surface, this deliberately avoids pure white in light mode.
    static let floatingPanelSurface = adaptive(
        light: rgb(0.935, 0.941, 0.947),
        dark: rgb(0.125, 0.137, 0.153)
    )
    static let floatingPanelRaisedSurface = adaptive(
        light: rgb(0.965, 0.969, 0.973),
        dark: rgb(0.165, 0.180, 0.200)
    )
    static let borderDefault = adaptive(
        light: rgb(0.886, 0.894, 0.906),
        dark: rgb(0.247, 0.271, 0.302)
    )
    static let borderStrong = adaptive(
        light: rgb(0.812, 0.827, 0.847),
        dark: rgb(0.333, 0.365, 0.404)
    )

    static let textPrimary = adaptive(
        light: rgb(0.247, 0.251, 0.239),
        dark: rgb(0.910, 0.925, 0.910)
    )
    static let textSecondary = adaptive(
        light: rgb(0.447, 0.459, 0.439),
        dark: rgb(0.700, 0.725, 0.700)
    )
    static let textMuted = adaptive(
        light: rgb(0.643, 0.659, 0.639),
        dark: rgb(0.525, 0.557, 0.529)
    )
    static let iconDefault = adaptive(
        light: rgb(0.553, 0.573, 0.565),
        dark: rgb(0.608, 0.635, 0.612)
    )
    static let iconHover = adaptive(
        light: rgb(0.333, 0.353, 0.341),
        dark: rgb(0.835, 0.855, 0.839)
    )
    static let progressTrackEmpty = adaptive(
        light: rgb(1, 1, 1),
        dark: rgb(0.184, 0.200, 0.220)
    )

    static let complete = Color(red: 0.333, green: 0.788, blue: 0.529)
    /// Application-wide interactive accent. The value is user-configurable in
    /// General Settings and intentionally remains separate from Channel colors.
    static var objective: Color { AppThemePreferences.currentColor }
    static let danger = Color(red: 0.851, green: 0.361, blue: 0.361)
    static let warning = Color(red: 0.827, green: 0.573, blue: 0.220)
    static let focusRing = Color(red: 0.482, green: 0.529, blue: 0.580)
    static let focusMeditation = adaptive(
        light: rgb(0.235, 0.506, 0.357),
        dark: rgb(0.310, 0.584, 0.424)
    )
    static let focusStudy = adaptive(
        light: rgb(0.482, 0.341, 0.690),
        dark: rgb(0.557, 0.416, 0.745)
    )
    static let focusLeisure = adaptive(
        light: rgb(0.655, 0.420, 0.204),
        dark: rgb(0.714, 0.482, 0.271)
    )
    static let overlay = Color.black.opacity(0.22)
    static let taskDetailBackdrop = Color.black.opacity(0.26)

    static let channelOrange = warning
    static let channelPurple = Color(red: 0.604, green: 0.424, blue: 0.890)
    static let channelBlue = Color(red: 0.310, green: 0.561, blue: 0.788)
    static let channelRed = danger
    static let channelYellow = Color(red: 0.875, green: 0.702, blue: 0.235)
    static let channelGray = iconDefault
    static let channelGreen = Color(red: 0.310, green: 0.616, blue: 0.459)

    // Semantic aliases keep every view on the same palette token source.
    static let canvas = appBackground
    static let sidebar = sidebarBackground
    static let button = surface
    static let selected = surfaceSelected
    static let border = borderDefault
    static let primaryText = textPrimary
    static let secondaryText = textSecondary
    static let green = complete
    static let urgent = danger
    static var priority: Color { objective }
    static let lowPriority = channelBlue

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? dark
                : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

extension TaskPriority {
    var showsOnTaskCard: Bool {
        self != .none
    }

    var flagSymbol: String {
        self == .none ? "flag" : "flag.fill"
    }

    var flagColor: Color {
        switch self {
        case .must: WeekflowPalette.urgent
        case .should: WeekflowPalette.priority
        case .none: WeekflowPalette.iconDefault
        case .later: WeekflowPalette.lowPriority
        }
    }
}

extension TaskChannel {
    var color: Color {
        if colorName.lowercased().hasPrefix("rgb:"),
           let rgb = TaskChannelRGB.resolve(colorName) {
            return Color(
                red: Double(rgb.red) / 255,
                green: Double(rgb.green) / 255,
                blue: Double(rgb.blue) / 255
            )
        }

        return switch colorName {
        case "orange": WeekflowPalette.channelOrange
        case "purple": WeekflowPalette.channelPurple
        case "blue": WeekflowPalette.channelBlue
        case "red": WeekflowPalette.channelRed
        case "yellow": WeekflowPalette.channelYellow
        case "green": WeekflowPalette.channelGreen
        default: WeekflowPalette.channelGray
        }
    }
}
