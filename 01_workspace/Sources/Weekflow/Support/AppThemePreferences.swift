import SwiftUI

enum AppThemePreferences {
    static let colorTokenKey = "weekflow.appearance.themeColor"
    static let defaultColorToken = TaskChannelRGB(red: 154, green: 108, blue: 227).encodedColorName

    static var currentColor: Color {
        color(for: UserDefaults.standard.string(forKey: colorTokenKey) ?? defaultColorToken)
    }

    static func color(for token: String) -> Color {
        let rgb = TaskChannelRGB.resolve(token)
            ?? TaskChannelRGB.resolve(defaultColorToken)
            ?? TaskChannelRGB(red: 154, green: 108, blue: 227)
        return Color(
            red: Double(rgb.red) / 255,
            green: Double(rgb.green) / 255,
            blue: Double(rgb.blue) / 255
        )
    }
}
