import SwiftUI

enum ChartPalettePreferences {
    static let storageKey = "weekflow.charts.palette"
    static let defaultPreset = ChartPalettePreset.classic.rawValue

    static func preset(for rawValue: String) -> ChartPalettePreset {
        if let preset = ChartPalettePreset(rawValue: rawValue) { return preset }
        switch rawValue {
        case "sage": return .colorBrewer
        case "dusk": return .brightDark
        default: return .classic
        }
    }
}

enum ChartPalettePreset: String, CaseIterable, Identifiable {
    case classic
    case rainbow
    case colorBrewer
    case pastel
    case warm
    case ocean
    case brightDark
    case neonDark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "经典分类"
        case .rainbow: "彩虹"
        case .colorBrewer: "柔和分类"
        case .pastel: "明亮粉彩"
        case .warm: "暖阳"
        case .ocean: "海洋渐变"
        case .brightDark: "深色高亮"
        case .neonDark: "深色霓虹"
        }
    }

    var usageTitle: String {
        switch self {
        case .classic: "通用 · 清晰分类"
        case .rainbow: "通用 · 多类别"
        case .colorBrewer: "通用 · 柔和均衡"
        case .pastel: "浅色 · 轻量柔和"
        case .warm: "暖色 · 橙红金黄"
        case .ocean: "冷色 · 连续层次"
        case .brightDark: "深色 · 高对比"
        case .neonDark: "深色 · 高亮多彩"
        }
    }

    var isOptimizedForDarkMode: Bool {
        self == .brightDark || self == .neonDark
    }

    var taskColors: [Color] { taskColors(for: .light) }

    func taskColors(for colorScheme: ColorScheme) -> [Color] {
        colorScheme == .dark ? darkTaskColors : lightTaskColors
    }

    var focusColors: [Color] {
        FocusMode.allCases.map(\.accentColor)
    }

    func taskSummaryColor(for colorScheme: ColorScheme) -> Color {
        taskColors(for: colorScheme).first ?? WeekflowPalette.iconDefault
    }

    var taskSummaryColor: Color { taskSummaryColor(for: .light) }
    var focusSummaryColor: Color { FocusMode.meditation.accentColor }

    func taskColor(
        channelID: String?,
        channels: [TaskChannel],
        colorScheme: ColorScheme = .light
    ) -> Color {
        let colors = taskColors(for: colorScheme)
        guard let channelID,
              let index = channels.firstIndex(where: { $0.id == channelID }) else {
            return colors.last ?? WeekflowPalette.iconDefault
        }
        return colors[index % colors.count]
    }

    func focusColor(_ mode: FocusMode) -> Color {
        mode.accentColor
    }

    private var lightTaskColors: [Color] {
        switch self {
        case .classic:
            [hex(0x4E79A7), hex(0xF28E2B), hex(0xE15759), hex(0x76B7B2), hex(0x59A14F), hex(0xEDC948), hex(0xB07AA1), hex(0xFF9DA7)]
        case .rainbow:
            [hex(0xE15759), hex(0xF28E2B), hex(0xEDC948), hex(0x59A14F), hex(0x4ECDC4), hex(0x4E79A7), hex(0x9C6ADE), hex(0xD45087)]
        case .colorBrewer:
            [hex(0x66C2A5), hex(0xFC8D62), hex(0x8DA0CB), hex(0xE78AC3), hex(0xA6D854), hex(0xFFD92F), hex(0xE5C494), hex(0xB3B3B3)]
        case .pastel:
            [hex(0xA6CEE3), hex(0xB2DF8A), hex(0xFB9A99), hex(0xFDBF6F), hex(0xCAB2D6), hex(0xFFFF99), hex(0xF4CAE4), hex(0xCCEBC5)]
        case .warm:
            [hex(0xD1495B), hex(0xE76F51), hex(0xF4A261), hex(0xE9C46A), hex(0xC97C5D), hex(0xB56576), hex(0xD98C6A), hex(0xF2CC8F)]
        case .ocean:
            [hex(0x414487), hex(0x2A788E), hex(0x22A884), hex(0x7AD151), hex(0xFDE725), hex(0x3B528B), hex(0x5EC962), hex(0x21918C)]
        case .brightDark:
            [hex(0x56B4E9), hex(0xF5A623), hex(0xFF6B8A), hex(0x63D6C5), hex(0xA78BFA), hex(0xFFD166), hex(0x7BD88F), hex(0xF783C2)]
        case .neonDark:
            [hex(0x00CFE8), hex(0xF03BC7), hex(0x8CDD32), hex(0xF5C842), hex(0x806EF5), hex(0xFF6262), hex(0x2DD4A7), hex(0xFF8A3D)]
        }
    }

    private var darkTaskColors: [Color] {
        switch self {
        case .classic:
            [hex(0x74A9E6), hex(0xFFAD57), hex(0xFF7A7D), hex(0x82D7D1), hex(0x83C977), hex(0xFFE066), hex(0xC9A0DC), hex(0xFFB3BE)]
        case .rainbow:
            [hex(0xFF6B6B), hex(0xFFA94D), hex(0xFFE066), hex(0x8CE99A), hex(0x66D9E8), hex(0x74C0FC), hex(0xB197FC), hex(0xF783C2)]
        case .colorBrewer:
            [hex(0x7ED8BD), hex(0xFFAA82), hex(0xAAB8E8), hex(0xF0A4D4), hex(0xBCE86C), hex(0xFFE46B), hex(0xF2D4AE), hex(0xD0D0D0)]
        case .pastel:
            [hex(0xB9E5F5), hex(0xC8EEA8), hex(0xFFB7B5), hex(0xFFD18E), hex(0xDCC7F2), hex(0xFFF7A8), hex(0xFFD0E7), hex(0xD9F3D2)]
        case .warm:
            [hex(0xFF7185), hex(0xFF8B6B), hex(0xFFB56B), hex(0xFFE07A), hex(0xE69A7E), hex(0xDE83A0), hex(0xF2A27E), hex(0xFFE0A3)]
        case .ocean:
            [hex(0x8C8CFF), hex(0x57C7E3), hex(0x4FE0C1), hex(0x9BE564), hex(0xFFF06A), hex(0x71A7FF), hex(0x72E189), hex(0x52D6D0)]
        case .brightDark:
            [hex(0x5CC8FF), hex(0xFFB454), hex(0xFF6B9D), hex(0x63E6BE), hex(0xB197FC), hex(0xFFD166), hex(0x8CE99A), hex(0xF783C2)]
        case .neonDark:
            [hex(0x00E5FF), hex(0xFF4ECD), hex(0xB8FF5A), hex(0xFFD84D), hex(0x9B8CFF), hex(0xFF6B6B), hex(0x3DFFC0), hex(0xFF9A4D)]
        }
    }

    private func hex(_ value: Int) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
