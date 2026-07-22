import AppKit
import SwiftUI

enum DailyProgressPreferences {
    static let colorTokenKey = "weekflow.dailyProgress.color"
    static let alwaysShowKey = "weekflow.dailyProgress.alwaysShow"
    static let defaultColorToken = TaskChannelRGB(red: 85, green: 201, blue: 135).encodedColorName

    static var currentColor: Color {
        color(for: UserDefaults.standard.string(forKey: colorTokenKey) ?? defaultColorToken)
    }

    static func color(for token: String) -> Color {
        guard let rgb = TaskChannelRGB.resolve(token) else { return WeekflowPalette.complete }
        return Color(
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }

    static func token(for color: Color) -> String {
        guard let rgbColor = NSColor(color).usingColorSpace(.sRGB) else {
            return defaultColorToken
        }
        return TaskChannelRGB(
            red: Int((rgbColor.redComponent * 255).rounded()),
            green: Int((rgbColor.greenComponent * 255).rounded()),
            blue: Int((rgbColor.blueComponent * 255).rounded())
        ).encodedColorName
    }

    static func isVisible(hasProgress: Bool, alwaysShow: Bool) -> Bool {
        hasProgress || alwaysShow
    }
}
