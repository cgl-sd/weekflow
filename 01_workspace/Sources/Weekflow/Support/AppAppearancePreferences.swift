import AppKit
import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    static let storageKey = "weekflow.appearance"
    static let defaultValue = AppAppearancePreference.system.rawValue

    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var applicationAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    func applyToApplication() {
        NSApp.appearance = applicationAppearance
        NSApp.windows.forEach { window in
            window.appearance = applicationAppearance
            window.contentView?.needsDisplay = true
        }
    }
}
