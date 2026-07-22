import Foundation

/// Compatibility layer for persisted channel colors.
///
/// Existing channels keep their named tokens. Custom colors use the stable
/// `rgb:R,G,B` representation in the existing `colorName` field, so no data
/// migration is required.
struct TaskChannelRGB: Equatable, Hashable {
    let red: Int
    let green: Int
    let blue: Int

    init(red: Int, green: Int, blue: Int) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    var encodedColorName: String {
        "rgb:\(red),\(green),\(blue)"
    }

    static func resolve(_ colorName: String) -> TaskChannelRGB? {
        let normalizedName = colorName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let named = namedColors[normalizedName] {
            return named
        }
        guard normalizedName.hasPrefix("rgb:") else { return nil }

        let components = normalizedName.dropFirst(4).split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == 3,
              let red = Int(components[0].trimmingCharacters(in: .whitespaces)),
              let green = Int(components[1].trimmingCharacters(in: .whitespaces)),
              let blue = Int(components[2].trimmingCharacters(in: .whitespaces)),
              (0...255).contains(red),
              (0...255).contains(green),
              (0...255).contains(blue)
        else { return nil }

        return TaskChannelRGB(red: red, green: green, blue: blue)
    }

    private static func clamp(_ component: Int) -> Int {
        min(max(component, 0), 255)
    }

    private static let namedColors: [String: TaskChannelRGB] = [
        "red": .init(red: 217, green: 92, blue: 92),
        "yellow": .init(red: 223, green: 179, blue: 60),
        "blue": .init(red: 79, green: 143, blue: 201),
        "orange": .init(red: 211, green: 146, blue: 56),
        "green": .init(red: 79, green: 157, blue: 117),
        "purple": .init(red: 154, green: 108, blue: 227),
        "gray": .init(red: 141, green: 146, blue: 144)
    ]
}
