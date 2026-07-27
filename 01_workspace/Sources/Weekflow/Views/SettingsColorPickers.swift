import SwiftUI

struct ChartPalettePicker: View {
    @Binding var selection: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var selectedPreset: ChartPalettePreset {
        ChartPalettePreferences.preset(for: selection)
    }

    var body: some View {
        WeekflowButton { isPresented.toggle() } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(selectedPreset.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                HStack(spacing: 3) {
                    ForEach(Array(selectedPreset.taskColors(for: colorScheme).prefix(5).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 9)
            .frame(width: 172, height: 38, alignment: .leading)
            .background(WeekflowPalette.surfaceHover, in: WeekflowRoundedRectangle(cornerRadius: 7))
            .overlay(WeekflowRoundedRectangle(cornerRadius: 7).stroke(WeekflowPalette.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChartPaletteAnchorPreferenceKey.self,
                    value: proxy.frame(in: .named("general-settings"))
                )
            }
        )
        .onDisappear {
            isPresented = false
        }
        .accessibilityLabel("图表配色")
        .accessibilityValue(selectedPreset.title)
    }
}

struct ChartPaletteMenu: View {
    @Binding var selection: String
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 3) {
            ForEach(ChartPalettePreset.allCases) { preset in
                ChartPaletteMenuRow(
                    preset: preset,
                    isSelected: ChartPalettePreferences.preset(for: selection) == preset,
                    colorScheme: colorScheme,
                    action: { selection = preset.rawValue }
                )
            }
        }
        .padding(8)
    }
}

struct ChartPaletteMenuRow: View {
    let preset: ChartPalettePreset
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textPrimary)
                    Text(preset.usageTitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(WeekflowPalette.textMuted)
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(Array(preset.taskColors(for: colorScheme).prefix(5).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 8, height: 8)
                    }
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textSecondary)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 12)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(
                isSelected
                    ? WeekflowPalette.surfaceSelected
                    : (isHovering ? WeekflowPalette.surfaceHover : .clear),
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
    }
}

struct SettingsLayoutRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) { content }
            .frame(maxWidth: .infinity, minHeight: 32)
    }
}

struct ChartPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct SettingsHoverControl<Content: View>: View {
    let content: Content
    @State private var isHovering = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                isHovering ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
            .pointingHandCursor(coversDescendants: true)
            .stablePointingHandHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.1), value: isHovering)
    }
}

struct AppearanceSegmentedControl: View {
    @Binding var selection: String
    @State private var hoveredPreference: AppAppearancePreference?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppAppearancePreference.allCases) { preference in
                let selected = selection == preference.rawValue
                WeekflowButton {
                    selection = preference.rawValue
                    preference.applyToApplication()
                } label: {
                    Text(preference.title)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .foregroundStyle(WeekflowPalette.primaryText)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(
                            selected
                                ? WeekflowPalette.surfaceSelected
                                : (hoveredPreference == preference ? WeekflowPalette.surfaceHover : .clear),
                            in: WeekflowRoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .stablePointingHandHover { hovering in
                    hoveredPreference = hovering ? preference : nil
                }
            }
        }
        .padding(2)
        .frame(width: 260)
        .background(WeekflowPalette.appBackground, in: WeekflowRoundedRectangle(cornerRadius: 7))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 7)
                .stroke(WeekflowPalette.border, lineWidth: 1)
        }
    }
}

struct ColorPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct ThemeColorPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct CompactColorPalettePicker: View {
    @Binding var selectedToken: String
    @Binding var isPresented: Bool
    let accessibilityLabel: String
    @State private var isHovering = false

    var body: some View {
        WeekflowButton {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                WeekflowRoundedRectangle(cornerRadius: 4)
                    .fill(DailyProgressPreferences.color(for: selectedToken))
                    .frame(width: 25, height: 17)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.secondaryText)
            }
            .frame(width: 48, height: 26)
            .background(
                isHovering || isPresented ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ColorPaletteAnchorPreferenceKey.self,
                    value: geometry.frame(in: .named("general-settings"))
                )
            }
        }
    }
}

struct ThemeColorPalettePicker: View {
    @Binding var selectedToken: String
    @Binding var isPresented: Bool
    let accessibilityLabel: String
    @State private var isHovering = false

    var body: some View {
        WeekflowButton {
            isPresented.toggle()
        } label: {
            HStack(spacing: 5) {
                WeekflowRoundedRectangle(cornerRadius: 4)
                    .fill(AppThemePreferences.color(for: selectedToken))
                    .frame(width: 25, height: 17)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.secondaryText)
            }
            .frame(width: 48, height: 26)
            .background(
                isHovering || isPresented ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ThemeColorPaletteAnchorPreferenceKey.self,
                    value: geometry.frame(in: .named("general-settings"))
                )
            }
        }
    }
}

struct CompactColorPalettePanel: View {
    @Binding var selectedToken: String
    let interactionChanged: (Bool) -> Void
    @State private var selection: HSBColorSelection

    init(
        selectedToken: Binding<String>,
        interactionChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _selectedToken = selectedToken
        self.interactionChanged = interactionChanged
        _selection = State(initialValue: HSBColorSelection(token: selectedToken.wrappedValue))
    }

    var body: some View {
        ZStack {
            // Own the whole floating surface so mouse events never fall
            // through to settings controls underneath the palette.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}

            VStack(spacing: 8) {
                SaturationBrightnessField(
                    selection: selectionBinding,
                    interactionChanged: interactionChanged
                )
                .frame(height: WeekflowLayout.colorPickerFieldHeight)
                HueSelectionTrack(
                    selection: selectionBinding,
                    interactionChanged: interactionChanged
                )
                .frame(height: WeekflowLayout.colorPickerHueTrackHeight)
            }
            .padding(10)
        }
        .frame(
            width: WeekflowLayout.colorPickerPanelWidth,
            height: WeekflowLayout.colorPickerPanelHeight
        )
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 10))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 10)
                .stroke(WeekflowPalette.borderStrong, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        .onChange(of: selectedToken) { _, token in
            guard token != selection.encodedToken else { return }
            selection = HSBColorSelection(token: token)
        }
    }

    private var selectionBinding: Binding<HSBColorSelection> {
        Binding(
            get: { selection },
            set: { newSelection in
                selection = newSelection
                selectedToken = newSelection.encodedToken
            }
        )
    }
}

struct SaturationBrightnessField: View {
    @Binding var selection: HSBColorSelection
    var interactionChanged: (Bool) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Color(hue: selection.hue, saturation: 1, brightness: 1)
                LinearGradient(
                    colors: [.white, .white.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.black.opacity(0), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .stroke(.white, lineWidth: 3)
                    .background(Circle().stroke(.black.opacity(0.36), lineWidth: 1))
                    .shadow(color: .black.opacity(0.32), radius: 2, y: 1)
                    .frame(width: 21, height: 21)
                    .position(markerPosition(in: proxy.size))

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(selectionGesture(in: proxy.size))
            }
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong.opacity(0.72), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .pointingHandCursor()
        }
        .accessibilityLabel("颜色明暗与饱和度")
    }

    private func markerPosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(CGFloat(selection.saturation) * size.width, 10.5), size.width - 10.5),
            y: min(max(CGFloat(1 - selection.brightness) * size.height, 10.5), size.height - 10.5)
        )
    }

    private func selectionGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                interactionChanged(true)
                guard size.width > 0, size.height > 0 else { return }
                selection.saturation = min(max(Double(value.location.x / size.width), 0), 1)
                selection.brightness = min(max(1 - Double(value.location.y / size.height), 0), 1)
            }
            .onEnded { _ in interactionChanged(false) }
    }
}

struct HueSelectionTrack: View {
    @Binding var selection: HSBColorSelection
    var interactionChanged: (Bool) -> Void = { _ in }

    private let hueColors: [Color] = [
        Color(hue: 0, saturation: 1, brightness: 1),
        Color(hue: 1.0 / 6.0, saturation: 1, brightness: 1),
        Color(hue: 2.0 / 6.0, saturation: 1, brightness: 1),
        Color(hue: 3.0 / 6.0, saturation: 1, brightness: 1),
        Color(hue: 4.0 / 6.0, saturation: 1, brightness: 1),
        Color(hue: 5.0 / 6.0, saturation: 1, brightness: 1),
        Color(hue: 1, saturation: 1, brightness: 1)
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: hueColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Circle()
                    .fill(Color(hue: selection.hue, saturation: 1, brightness: 1))
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(color: .black.opacity(0.34), radius: 2, y: 1)
                    .frame(width: 24, height: 24)
                    .position(
                        x: min(max(CGFloat(selection.hue) * proxy.size.width, 12), proxy.size.width - 12),
                        y: proxy.size.height / 2
                    )

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(hueGesture(width: proxy.size.width))
            }
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 7))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 7)
                    .stroke(WeekflowPalette.borderStrong.opacity(0.72), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .pointingHandCursor()
        }
        .accessibilityLabel("色相")
    }

    private func hueGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                interactionChanged(true)
                guard width > 0 else { return }
                selection.hue = min(max(Double(value.location.x / width), 0), 1)
            }
            .onEnded { _ in interactionChanged(false) }
    }
}

struct ChannelPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
