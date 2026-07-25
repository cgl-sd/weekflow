import SwiftUI

/// A configurable focus mode entry. Built-in modes (禅定) cannot be deleted;
/// custom modes support user-defined title, color and icon.
struct FocusModeConfig: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var colorName: String
    var iconName: String
    var isBuiltIn: Bool

    var color: Color {
        DailyProgressPreferences.color(for: colorName)
    }

    var runningSymbol: String { "\(iconName).fill" }

    static let builtInMeditation = FocusModeConfig(
        id: "meditation",
        title: "禅定",
        colorName: TaskChannelRGB(red: 60, green: 129, blue: 91).encodedColorName,
        iconName: "leaf",
        isBuiltIn: true
    )

    static let defaultModes: [FocusModeConfig] = [
        builtInMeditation,
        FocusModeConfig(
            id: "study",
            title: "学习",
            colorName: TaskChannelRGB(red: 123, green: 87, blue: 176).encodedColorName,
            iconName: "book.closed",
            isBuiltIn: false
        ),
        FocusModeConfig(
            id: "leisure",
            title: "休闲",
            colorName: TaskChannelRGB(red: 167, green: 107, blue: 52).encodedColorName,
            iconName: "cup.and.saucer",
            isBuiltIn: false
        )
    ]
}

/// Manages the dynamic list of focus modes persisted in UserDefaults.
/// Meditation is always present and cannot be removed.
enum FocusModePreferences {
    static let storageKey = "weekflow.focus.modes.v1"

    static var modes: [FocusModeConfig] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FocusModeConfig].self, from: data),
              !decoded.isEmpty
        else {
            return FocusModeConfig.defaultModes
        }
        // Ensure meditation is always present
        if !decoded.contains(where: { $0.id == "meditation" }) {
            return [FocusModeConfig.builtInMeditation] + decoded
        }
        return decoded
    }

    static func save(_ modes: [FocusModeConfig]) {
        guard let data = try? JSONEncoder().encode(modes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func mode(for id: String) -> FocusModeConfig? {
        modes.first { $0.id == id }
    }

    /// Resolves display title for a mode ID. Falls back to the raw ID for
    /// deleted modes still referenced by old records.
    static func title(for modeID: String) -> String {
        mode(for: modeID)?.title ?? modeID
    }

    /// Resolves display color for a mode ID.
    static func color(for modeID: String) -> Color {
        mode(for: modeID)?.color ?? WeekflowPalette.focusMeditation
    }

    /// Resolves icon symbol for a mode ID.
    static func symbol(for modeID: String) -> String {
        mode(for: modeID)?.iconName ?? "leaf"
    }

    static func addMode(title: String, colorName: String, iconName: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = modes
        let baseID = trimmed.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .applyingTransform(.toLatin, reverse: false) ?? trimmed
        let uniqueID = current.contains(where: { $0.id == baseID })
            ? "\(baseID)-\(UUID().uuidString.prefix(4).lowercased())"
            : baseID
        current.append(FocusModeConfig(
            id: uniqueID,
            title: trimmed,
            colorName: colorName,
            iconName: iconName,
            isBuiltIn: false
        ))
        save(current)
    }

    static func updateMode(_ mode: FocusModeConfig) {
        var current = modes
        guard let index = current.firstIndex(where: { $0.id == mode.id }) else { return }
        current[index] = mode
        save(current)
    }

    static func deleteMode(id: String) {
        // Cannot delete built-in modes
        guard let mode = mode(for: id), !mode.isBuiltIn else { return }
        var current = modes
        current.removeAll { $0.id == id }
        save(current)
    }
}
