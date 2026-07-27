import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum WorkspaceSettingsSection: String, CaseIterable, Identifiable {
    case general
    case channels
    case focusMode
    case calendar

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .channels: "分类与频道"
        case .focusMode: "专注模式"
        case .calendar: "日历"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .channels: "number"
        case .focusMode: "mug"
        case .calendar: "calendar"
        }
    }
}

struct ChannelSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WeekflowStore
    let onDismiss: (() -> Void)?
    @State private var newChannelName = ""
    @State private var newChannelIconName = "number"
    @State private var newChannelColorName = "gray"
    @State private var activeChannelPaletteID: String?
    @State private var channelPaletteAnchors: [String: CGRect] = [:]
    @State private var activeChannelIconID: String?
    @State private var channelIconAnchors: [String: CGRect] = [:]
    @State private var selectedSection: WorkspaceSettingsSection
    @State private var hoveredSection: WorkspaceSettingsSection?
    @State private var isBackHovering = false
    // General section popup state (lifted for full-screen overlay)
    @State private var isGeneralColorPalettePresented = false
    @State private var isGeneralThemePalettePresented = false
    @State private var isGeneralChartPalettePresented = false
    // Focus mode section popup state
    @State private var activeFocusPaletteID: String?
    @State private var focusPaletteAnchors: [String: CGRect] = [:]
    @State private var activeFocusIconID: String?
    @State private var focusIconAnchors: [String: CGRect] = [:]
    @State private var newFocusModeName = ""
    @State private var newFocusModeIconName = "leaf"
    @State private var newFocusModeColorName = "gray"
    @State private var focusModes: [FocusModeConfig] = FocusModePreferences.modes

    init(
        store: WeekflowStore,
        initialSection: WorkspaceSettingsSection = .channels,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.onDismiss = onDismiss
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    WeekflowButton { closeSettings() } label: {
                        Label("返回工作区", systemImage: "chevron.left")
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .background(
                                isBackHovering ? WeekflowPalette.surfaceSelected : .clear,
                                in: WeekflowRoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .stablePointingHandHover { isBackHovering = $0 }
                        .padding(.bottom, 20)
                    Text("工作区").font(.caption.weight(.bold)).foregroundStyle(WeekflowPalette.secondaryText)
                    ForEach(WorkspaceSettingsSection.allCases) { section in
                        settingsRow(section)
                    }
                    Spacer()
                }
                .padding(24)
                .frame(minWidth: 210, maxWidth: 210, maxHeight: .infinity, alignment: .topLeading)
                .background(WeekflowPalette.sidebar)
                Divider()

                Group {
                    switch selectedSection {
                    case .general:
                        GeneralSettingsView(
                            store: store,
                            isColorPalettePresented: $isGeneralColorPalettePresented,
                            isThemeColorPalettePresented: $isGeneralThemePalettePresented,
                            isChartPalettePresented: $isGeneralChartPalettePresented
                        )
                    case .channels:
                        channelSettings
                    case .focusMode:
                        focusModeSettings
                    case .calendar:
                        calendarSettings
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 860, height: 620, alignment: .topLeading)
        .background(WeekflowPalette.canvas)
    }

    private func closeSettings() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private func dismissTopmostPopup() {
        // Close only ONE layer per click (topmost first)
        if activeChannelIconID != nil {
            activeChannelIconID = nil
        } else if activeChannelPaletteID != nil {
            activeChannelPaletteID = nil
        } else if activeFocusIconID != nil {
            activeFocusIconID = nil
        } else if activeFocusPaletteID != nil {
            activeFocusPaletteID = nil
        } else if isGeneralChartPalettePresented {
            isGeneralChartPalettePresented = false
        } else if isGeneralThemePalettePresented {
            isGeneralThemePalettePresented = false
        } else if isGeneralColorPalettePresented {
            isGeneralColorPalettePresented = false
        }
    }

    private func settingsRow(_ section: WorkspaceSettingsSection) -> some View {
        let selected = selectedSection == section
        let highlighted = selected || hoveredSection == section
        return WeekflowButton {
            selectedSection = section
        } label: {
            Label(section.title, systemImage: section.symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(
                    highlighted ? WeekflowPalette.selected : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { hovering in
            hoveredSection = hovering ? section : nil
        }
    }

    private var channelSettings: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("分类与频道").font(.system(size: 25, weight: .bold))
                    Text("频道全部平级显示；名称、图标和颜色会自动保存。")
                        .font(.system(size: 13)).foregroundStyle(WeekflowPalette.secondaryText)
                    HStack(spacing: 10) {
                        ChannelIconButton(
                            channelID: ChannelSettingsDraftID.newChannel,
                            iconName: newChannelIconName,
                            action: { toggleIconMenu(for: ChannelSettingsDraftID.newChannel) }
                        )
                        TextField("新频道名称", text: $newChannelName)
                            .textFieldStyle(.plain)
                            .frame(minWidth: 220)
                            .onSubmit(addChannel)
                        ChannelColorPaletteButton(
                            channelID: ChannelSettingsDraftID.newChannel,
                            color: DailyProgressPreferences.color(for: newChannelColorName),
                            action: { toggleColorPalette(for: ChannelSettingsDraftID.newChannel) }
                        )
                        Spacer(minLength: 0)
                        ChannelCreateButton(action: addChannel)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
                    .overlay {
                        WeekflowRoundedRectangle(cornerRadius: 8)
                            .stroke(WeekflowPalette.border, lineWidth: 1)
                    }
                    Divider()
                    HStack {
                        Text("频道").font(.caption.weight(.bold)).foregroundStyle(WeekflowPalette.secondaryText)
                        Spacer()
                        Text("图标 / 颜色 / 默认 / 删除").font(.caption.weight(.bold)).foregroundStyle(WeekflowPalette.secondaryText)
                    }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.activeChannels) { channel in
                                ChannelSettingRow(
                                    channel: channel,
                                    store: store,
                                    showColorPalette: { toggleColorPalette(for: channel.id) },
                                    showIconMenu: { toggleIconMenu(for: channel.id) }
                                )
                            }
                        }
                        .padding(.trailing, 6)
                        .background(SystemOverlayScroller())
                    }
                    .scrollIndicators(.automatic)
                    Spacer()
                }
                .allowsHitTesting(activeChannelIconID == nil)

                if let channelID = activeChannelPaletteID,
                   let anchor = channelPaletteAnchors[channelID] {
                    channelPaletteOverlay(channelID: channelID, anchor: anchor, availableSize: proxy.size)
                        .zIndex(100)
                }

                if let channelID = activeChannelIconID,
                   let anchor = channelIconAnchors[channelID] {
                    channelIconOverlay(channelID: channelID, anchor: anchor, availableSize: proxy.size)
                        .zIndex(110)
                }
            }
            .coordinateSpace(name: "channel-settings")
            .onPreferenceChange(ChannelPaletteAnchorPreferenceKey.self) { anchors in
                channelPaletteAnchors.merge(anchors) { _, new in new }
            }
            .onPreferenceChange(ChannelIconAnchorPreferenceKey.self) { anchors in
                channelIconAnchors.merge(anchors) { _, new in new }
            }
        }
    }

    private func channelPaletteOverlay(
        channelID: String,
        anchor: CGRect,
        availableSize: CGSize
    ) -> some View {
        let panelSize = CGSize(
            width: WeekflowLayout.colorPickerPanelWidth,
            height: WeekflowLayout.colorPickerPanelHeight
        )
        let origin = CGPoint(
            x: min(max(anchor.maxX - panelSize.width, 6), availableSize.width - panelSize.width - 6),
            y: min(anchor.maxY + 6, availableSize.height - panelSize.height - 6)
        )
        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [anchor, CGRect(origin: origin, size: panelSize)],
                monitoredEventMask: .leftMouseUp,
                action: { activeChannelPaletteID = nil }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            CompactColorPalettePanel(
                selectedToken: Binding(
                    get: {
                        channelID == ChannelSettingsDraftID.newChannel
                            ? newChannelColorName
                            : (store.channel(for: channelID)?.colorName ?? "gray")
                    },
                    set: { token in
                        if channelID == ChannelSettingsDraftID.newChannel {
                            newChannelColorName = token
                            return
                        }
                        guard var channel = store.channel(for: channelID) else { return }
                        channel.colorName = token
                        store.updateChannel(channel)
                    }
                ),
                interactionChanged: { _ in }
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: origin.x + panelSize.width / 2, y: origin.y + panelSize.height / 2)
            .contentShape(Rectangle())
            .zIndex(10)
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
    }

    private func channelIconOverlay(
        channelID: String,
        anchor: CGRect,
        availableSize: CGSize
    ) -> some View {
        let rowHeight: CGFloat = 30
        let panelSize = CGSize(
            width: 184,
            height: CGFloat(ChannelIconOption.allCases.count) * rowHeight + 12
        )
        let origin = CGPoint(
            x: min(max(anchor.minX, 6), availableSize.width - panelSize.width - 6),
            y: min(anchor.maxY + 6, availableSize.height - panelSize.height - 6)
        )
        let panelFrame = CGRect(origin: origin, size: panelSize)

        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [anchor, panelFrame],
                action: { activeChannelIconID = nil }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            ChannelIconSelectionPanel(
                selection: selectedIconName(for: channelID),
                select: { iconName in
                    setIconName(iconName, for: channelID)
                }
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: origin.x + panelSize.width / 2, y: origin.y + panelSize.height / 2)
            .contentShape(Rectangle())
            .zIndex(10)
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
    }

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("日历").font(.system(size: 25, weight: .bold))
            Text("日历接入将在明确本地数据和系统授权边界后提供。")
                .font(.system(size: 13))
                .foregroundStyle(WeekflowPalette.secondaryText)
            Spacer()
        }
    }

    // MARK: - Focus Mode Settings

    private var focusModeSettings: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("专注模式").font(.system(size: 25, weight: .bold))
                    Text("自定义专注模式的名称、颜色和图标。禅定为内置模式不可删除。")
                        .font(.system(size: 13)).foregroundStyle(WeekflowPalette.secondaryText)
                    HStack(spacing: 10) {
                        ChannelIconButton(
                            channelID: FocusSettingsDraftID.newMode,
                            iconName: newFocusModeIconName,
                            action: { toggleFocusIconMenu(for: FocusSettingsDraftID.newMode) }
                        )
                        TextField("新模式名称", text: $newFocusModeName)
                            .textFieldStyle(.plain)
                            .frame(minWidth: 220)
                            .onSubmit(addFocusMode)
                        ChannelColorPaletteButton(
                            channelID: FocusSettingsDraftID.newMode,
                            color: DailyProgressPreferences.color(for: newFocusModeColorName),
                            action: { toggleFocusColorPalette(for: FocusSettingsDraftID.newMode) }
                        )
                        Spacer(minLength: 0)
                        FocusModeCreateButton(action: addFocusMode)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
                    .overlay {
                        WeekflowRoundedRectangle(cornerRadius: 8)
                            .stroke(WeekflowPalette.border, lineWidth: 1)
                    }
                    Divider()
                    HStack {
                        Text("模式").font(.caption.weight(.bold)).foregroundStyle(WeekflowPalette.secondaryText)
                        Spacer()
                        Text("图标 / 颜色 / 删除").font(.caption.weight(.bold)).foregroundStyle(WeekflowPalette.secondaryText)
                    }
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(focusModes) { mode in
                                FocusModeSettingRow(
                                    mode: mode,
                                    showColorPalette: { toggleFocusColorPalette(for: mode.id) },
                                    showIconMenu: { toggleFocusIconMenu(for: mode.id) },
                                    onDelete: { deleteFocusMode(id: mode.id) },
                                    onRename: { title in renameFocusMode(id: mode.id, title: title) }
                                )
                            }
                        }
                        .padding(.trailing, 6)
                        .background(SystemOverlayScroller())
                    }
                    .scrollIndicators(.automatic)
                    Spacer()
                }
                .allowsHitTesting(activeFocusIconID == nil)

                if let modeID = activeFocusPaletteID,
                   let anchor = focusPaletteAnchors[modeID] {
                    focusPaletteOverlay(modeID: modeID, anchor: anchor, availableSize: proxy.size)
                        .zIndex(100)
                }

                if let modeID = activeFocusIconID,
                   let anchor = focusIconAnchors[modeID] {
                    focusIconOverlay(modeID: modeID, anchor: anchor, availableSize: proxy.size)
                        .zIndex(110)
                }
            }
            .coordinateSpace(name: "channel-settings")
            .onPreferenceChange(ChannelPaletteAnchorPreferenceKey.self) { anchors in
                focusPaletteAnchors.merge(anchors) { _, new in new }
            }
            .onPreferenceChange(ChannelIconAnchorPreferenceKey.self) { anchors in
                focusIconAnchors.merge(anchors) { _, new in new }
            }
        }
    }

    private func focusPaletteOverlay(
        modeID: String,
        anchor: CGRect,
        availableSize: CGSize
    ) -> some View {
        let panelSize = CGSize(
            width: WeekflowLayout.colorPickerPanelWidth,
            height: WeekflowLayout.colorPickerPanelHeight
        )
        let origin = CGPoint(
            x: min(max(anchor.maxX - panelSize.width, 6), availableSize.width - panelSize.width - 6),
            y: min(anchor.maxY + 6, availableSize.height - panelSize.height - 6)
        )
        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [anchor, CGRect(origin: origin, size: panelSize)],
                monitoredEventMask: .leftMouseUp,
                action: { activeFocusPaletteID = nil }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            CompactColorPalettePanel(
                selectedToken: Binding(
                    get: {
                        modeID == FocusSettingsDraftID.newMode
                            ? newFocusModeColorName
                            : (FocusModePreferences.mode(for: modeID)?.colorName ?? "gray")
                    },
                    set: { token in
                        if modeID == FocusSettingsDraftID.newMode {
                            newFocusModeColorName = token
                            return
                        }
                        guard var mode = FocusModePreferences.mode(for: modeID) else { return }
                        mode.colorName = token
                        FocusModePreferences.updateMode(mode)
                        focusModes = FocusModePreferences.modes
                    }
                ),
                interactionChanged: { _ in }
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: origin.x + panelSize.width / 2, y: origin.y + panelSize.height / 2)
            .contentShape(Rectangle())
            .zIndex(10)
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
    }

    private func focusIconOverlay(
        modeID: String,
        anchor: CGRect,
        availableSize: CGSize
    ) -> some View {
        let rowHeight: CGFloat = 30
        let panelSize = CGSize(
            width: 184,
            height: CGFloat(FocusIconOption.allCases.count) * rowHeight + 12
        )
        let origin = CGPoint(
            x: min(max(anchor.minX, 6), availableSize.width - panelSize.width - 6),
            y: min(anchor.maxY + 6, availableSize.height - panelSize.height - 6)
        )
        let panelFrame = CGRect(origin: origin, size: panelSize)

        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [anchor, panelFrame],
                action: { activeFocusIconID = nil }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            FocusIconSelectionPanel(
                selection: selectedFocusIconName(for: modeID),
                select: { iconName in
                    setFocusIconName(iconName, for: modeID)
                }
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: origin.x + panelSize.width / 2, y: origin.y + panelSize.height / 2)
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
    }

    private func addFocusMode() {
        FocusModePreferences.addMode(
            title: newFocusModeName,
            colorName: newFocusModeColorName,
            iconName: newFocusModeIconName
        )
        newFocusModeName = ""
        focusModes = FocusModePreferences.modes
    }

    private func deleteFocusMode(id: String) {
        FocusModePreferences.deleteMode(id: id)
        focusModes = FocusModePreferences.modes
    }

    private func renameFocusMode(id: String, title: String) {
        guard var mode = FocusModePreferences.mode(for: id) else { return }
        mode.title = title
        FocusModePreferences.updateMode(mode)
        focusModes = FocusModePreferences.modes
    }

    private func toggleFocusColorPalette(for modeID: String) {
        activeFocusIconID = nil
        activeFocusPaletteID = activeFocusPaletteID == modeID ? nil : modeID
    }

    private func toggleFocusIconMenu(for modeID: String) {
        activeFocusPaletteID = nil
        activeFocusIconID = activeFocusIconID == modeID ? nil : modeID
    }

    private func selectedFocusIconName(for modeID: String) -> String {
        modeID == FocusSettingsDraftID.newMode
            ? newFocusModeIconName
            : (FocusModePreferences.mode(for: modeID)?.iconName ?? "leaf")
    }

    private func setFocusIconName(_ iconName: String, for modeID: String) {
        if modeID == FocusSettingsDraftID.newMode {
            newFocusModeIconName = iconName
            return
        }
        guard var mode = FocusModePreferences.mode(for: modeID) else { return }
        mode.iconName = iconName
        FocusModePreferences.updateMode(mode)
        focusModes = FocusModePreferences.modes
    }

    private func addChannel() {
        store.addChannel(
            title: newChannelName,
            colorName: newChannelColorName,
            iconName: newChannelIconName
        )
        newChannelName = ""
    }

    private func toggleColorPalette(for channelID: String) {
        activeChannelIconID = nil
        activeChannelPaletteID = activeChannelPaletteID == channelID ? nil : channelID
    }

    private func toggleIconMenu(for channelID: String) {
        activeChannelPaletteID = nil
        activeChannelIconID = activeChannelIconID == channelID ? nil : channelID
    }

    private func selectedIconName(for channelID: String) -> String {
        channelID == ChannelSettingsDraftID.newChannel
            ? newChannelIconName
            : (store.channel(for: channelID)?.resolvedIconName ?? "number")
    }

    private func setIconName(_ iconName: String, for channelID: String) {
        if channelID == ChannelSettingsDraftID.newChannel {
            newChannelIconName = iconName
            return
        }
        guard var channel = store.channel(for: channelID) else { return }
        channel.iconName = iconName
        store.updateChannel(channel)
    }
}

enum ChannelSettingsDraftID {
    static let newChannel = "__new-channel__"
}

struct GeneralSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Bindable var store: WeekflowStore
    @Binding var isColorPalettePresented: Bool
    @Binding var isThemeColorPalettePresented: Bool
    @Binding var isChartPalettePresented: Bool
    @AppStorage(AppAppearancePreference.storageKey)
    private var appearanceRawValue = AppAppearancePreference.defaultValue
    @AppStorage(DailyProgressPreferences.colorTokenKey)
    private var colorToken = DailyProgressPreferences.defaultColorToken
    @AppStorage(DailyProgressPreferences.alwaysShowKey)
    private var alwaysShowDailyProgress = false
    @AppStorage(AppThemePreferences.colorTokenKey)
    private var themeColorToken = AppThemePreferences.defaultColorToken
    @AppStorage(ChartPalettePreferences.storageKey)
    private var chartPaletteRawValue = ChartPalettePreferences.defaultPreset
    @AppStorage(TaskCardTypographyPreferences.taskTextSizeKey)
    private var taskTextSize = TaskCardTypographyPreferences.defaultTaskTextSize
    @AppStorage(TaskCardTypographyPreferences.metadataSizeKey)
    private var metadataSize = TaskCardTypographyPreferences.defaultMetadataSize
    @AppStorage(TaskCardTypographyPreferences.iconSizeKey)
    private var iconSize = TaskCardTypographyPreferences.defaultIconSize
    @AppStorage(GlobalDateShortcutPreferences.enabledKey)
    private var globalDateShortcutsEnabled = false
    @AppStorage(GlobalDateShortcutPreferences.stateKey)
    private var globalDateShortcutState = GlobalDateShortcutRegistrationState.disabled.rawValue
    @AppStorage(GlobalDateShortcutPreferences.errorKey)
    private var globalDateShortcutError = ""
    @State private var colorPaletteAnchor = CGRect.zero
    @State private var themeColorPaletteAnchor = CGRect.zero
    @State private var chartPaletteAnchor = CGRect.zero
    @State private var updateCheckState: UpdateCheckState = .idle
    @State private var backupStatus = DatabaseBackupStatus.empty
    @State private var dataOperationMessage: String?
    @State private var pendingImportURL: URL?
    @State private var isDataOperationRunning = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
            Text("通用")
                .font(.system(size: 25, weight: .bold))
            Text("管理应用的通用显示偏好。设置仅保存在这台 Mac 上。")
                .font(.system(size: 13))
                .foregroundStyle(WeekflowPalette.secondaryText)
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("外观")
                    .font(.system(size: 15, weight: .semibold))

                SettingsLayoutRow {
                    Text("显示模式")
                    Spacer()
                    AppearanceSegmentedControl(selection: $appearanceRawValue)
                }

                Text("“跟随系统”会随 macOS 的浅色或深色外观自动切换。")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)
            }
            .padding(18)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.border, lineWidth: 1)
            }
            .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 14) {
                Text("全局日期快捷键")
                    .font(.system(size: 15, weight: .semibold))

                SettingsLayoutRow {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("在其他应用中切换 Weekflow 日期")
                        Text("⌘⌥Space / ⌘⌥← / ⌘⌥→")
                            .font(.system(size: 11))
                            .foregroundStyle(WeekflowPalette.secondaryText)
                    }
                    Spacer()
                    SettingsHoverControl {
                        Toggle("启用全局日期快捷键", isOn: $globalDateShortcutsEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                Text(globalShortcutStatusText)
                    .font(.system(size: 12))
                    .foregroundStyle(globalDateShortcutState == GlobalDateShortcutRegistrationState.failed.rawValue ? .red : WeekflowPalette.secondaryText)
            }
            .padding(18)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.border, lineWidth: 1)
            }
            .frame(maxWidth: 480)
            .onChange(of: globalDateShortcutsEnabled) { _, _ in
                CommandRouter.shared.send(.refreshGlobalShortcuts)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("图表配色")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    ChartPalettePicker(
                        selection: $chartPaletteRawValue,
                        isPresented: $isChartPalettePresented
                    )
                }

                Text("用于每日回顾和周回顾。")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)
            }
            .padding(18)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.border, lineWidth: 1)
            }
            .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 14) {
                Text("每日进度")
                    .font(.system(size: 15, weight: .semibold))

                SettingsLayoutRow {
                    Text("进度条颜色")
                    Spacer()
                    CompactColorPalettePicker(
                        selectedToken: $colorToken,
                        isPresented: $isColorPalettePresented,
                        accessibilityLabel: "进度条颜色"
                    )
                }

                SettingsLayoutRow {
                    Text("始终显示每日进度条")
                    Spacer()
                    SettingsHoverControl {
                        Toggle("始终显示每日进度条", isOn: $alwaysShowDailyProgress)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                Text(alwaysShowDailyProgress
                     ? "全局进度条颜色 · 始终显示"
                     : "全局进度条颜色 · 无进度时隐藏")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)

                progressPreview
            }
            .padding(18)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.border, lineWidth: 1)
            }
            .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 14) {
                Text("软件偏好设置")
                    .font(.system(size: 15, weight: .semibold))

                SettingsLayoutRow {
                    Text("主题色")
                    Spacer()
                    ThemeColorPalettePicker(
                        selectedToken: $themeColorToken,
                        isPresented: $isThemeColorPalettePresented,
                        accessibilityLabel: "主题色"
                    )
                }

                Text("用于主要按钮、选中标记和关键操作图标。")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)

            }
            .padding(18)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.border, lineWidth: 1)
            }
            .frame(maxWidth: 480)

            VStack(alignment: .leading, spacing: 14) {
                Text("任务卡片")
                    .font(.system(size: 15, weight: .semibold))

                SettingsLayoutRow {
                    Text("任务文字字号")
                    Spacer()
                    SettingsHoverControl {
                        Picker("任务文字字号", selection: $taskTextSize) {
                            ForEach([11.0, 12.0, 13.0, 14.0, 15.0], id: \.self) { size in
                                Text("\(Int(size))pt").tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 84)
                    }
                }

                SettingsLayoutRow {
                    Text("任务信息字号")
                    Spacer()
                    SettingsHoverControl {
                        Picker("任务信息字号", selection: $metadataSize) {
                            ForEach([8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0], id: \.self) { size in
                                Text("\(size, specifier: size.rounded() == size ? "%.0f" : "%.1f")pt")
                                    .tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 84)
                    }
                }

                SettingsLayoutRow {
                    Text("底部图标大小")
                    Spacer()
                    SettingsHoverControl {
                        Picker("底部图标大小", selection: $iconSize) {
                            ForEach([10.0, 10.5, 11.0, 11.5, 12.0, 12.5, 13.0, 13.5, 14.0], id: \.self) { size in
                                Text("\(size, specifier: size.rounded() == size ? "%.0f" : "%.1f")pt")
                                    .tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 84)
                    }
                }

                Text("调整任务文字、信息和图标大小。")
                    .font(.system(size: 12))
                    .foregroundStyle(WeekflowPalette.secondaryText)

                HStack {
                    Text("添加任务 / 任务描述")
                        .font(.system(size: TaskCardTypographyPreferences.taskTextSize(from: taskTextSize)))
                    Spacer()
                    Text("09:00  优先  # Channel")
                        .font(.system(size: TaskCardTypographyPreferences.metadataSize(from: metadataSize)))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(
                                size: TaskCardTypographyPreferences.iconSize(from: iconSize)
                                    + TaskCardTypographyPreferences.completionIconSizeAdjustment
                            ))
                        Image(systemName: "calendar")
                        Image(systemName: "timer")
                        Image(systemName: "flag")
                    }
                    .font(.system(size: TaskCardTypographyPreferences.iconSize(from: iconSize)))
                    .foregroundStyle(WeekflowPalette.secondaryText)
                }
            }
            .padding(18)
            .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.border, lineWidth: 1)
            }
            .frame(maxWidth: 480)

            dataManagementCard

            updateSettingsCard

                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(SystemOverlayScroller())
                }
                .scrollIndicators(.automatic)

                if isColorPalettePresented {
                    colorPaletteOverlay(in: proxy.size)
                        .zIndex(100)
                }

                if isThemeColorPalettePresented {
                    themeColorPaletteOverlay(in: proxy.size)
                        .zIndex(105)
                }

                if isChartPalettePresented, chartPaletteAnchor != .zero {
                    chartPaletteOverlay(in: proxy.size)
                        .zIndex(110)
                }
            }
            .coordinateSpace(name: "general-settings")
            .onPreferenceChange(ColorPaletteAnchorPreferenceKey.self) { anchor in
                guard anchor != .zero else { return }
                colorPaletteAnchor = anchor
            }
            .onPreferenceChange(ThemeColorPaletteAnchorPreferenceKey.self) { anchor in
                guard anchor != .zero else { return }
                themeColorPaletteAnchor = anchor
            }
            .onPreferenceChange(ChartPaletteAnchorPreferenceKey.self) { anchor in
                guard anchor != .zero else { return }
                chartPaletteAnchor = anchor
            }
            .onChange(of: isColorPalettePresented) { _, isPresented in
                guard isPresented else { return }
                isThemeColorPalettePresented = false
                isChartPalettePresented = false
            }
            .onChange(of: isThemeColorPalettePresented) { _, isPresented in
                guard isPresented else { return }
                isColorPalettePresented = false
                isChartPalettePresented = false
            }
            .onChange(of: isChartPalettePresented) { _, isPresented in
                guard isPresented else { return }
                isColorPalettePresented = false
                isThemeColorPalettePresented = false
            }
        }
        .task { refreshBackupStatus() }
        .confirmationDialog(
            "导入完整数据归档？",
            isPresented: Binding(
                get: { pendingImportURL != nil },
                set: { if !$0 { pendingImportURL = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("备份当前数据并导入", role: .destructive) { confirmFullDataImport() }
            Button("取消", role: .cancel) { pendingImportURL = nil }
        } message: {
            Text("导入会用归档中的全部目标、任务、规划、频道、日历、专注和总结数据替换当前内容；操作前会先创建可恢复备份。")
        }
    }

    private var globalShortcutStatusText: String {
        switch GlobalDateShortcutRegistrationState(rawValue: globalDateShortcutState) ?? .disabled {
        case .disabled:
            "默认关闭；关闭时 Weekflow 不注册任何系统级快捷键。"
        case .active:
            "已启用并成功注册。"
        case .failed:
            globalDateShortcutError.isEmpty ? "注册失败，请检查快捷键冲突。" : globalDateShortcutError
        }
    }

    private var updateSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("版本与更新")
                .font(.system(size: 15, weight: .semibold))

            SettingsLayoutRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text("检查 GitHub 上的新版本")
                    Text(currentVersionText)
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                }
                Spacer()
                SettingsHoverControl {
                    Button(updateButtonTitle) {
                        checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(updateCheckState.isChecking || WeekflowAppVersion.current == nil)
                    .pointingHandCursor()
                }
            }

            updateStatusView

            Text("仅在点击时访问 GitHub Releases；不会上传任务、计划或其他本地数据。")
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
        }
        .padding(18)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(WeekflowPalette.border, lineWidth: 1)
        }
        .frame(maxWidth: 480)
    }

    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本地数据与备份")
                .font(.system(size: 15, weight: .semibold))

            SettingsLayoutRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text("数据库备份")
                    Text(backupStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(backupStatus.latestFailure == nil ? WeekflowPalette.secondaryText : .orange)
                }
                Spacer()
                SettingsHoverControl {
                    Button("立即备份") { createBackup() }
                        .buttonStyle(.bordered)
                        .disabled(isDataOperationRunning)
                        .pointingHandCursor()
                }
            }

            Divider()

            SettingsLayoutRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text("完整数据归档")
                    Text("包含目标、任务、规划、频道、日历、专注记录、每日总结和活动计时。")
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("导入") { chooseFullDataArchive() }
                        .buttonStyle(.bordered)
                        .disabled(isDataOperationRunning)
                    Button("导出") { exportFullDataArchive() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isDataOperationRunning)
                }
                .pointingHandCursor()
            }

            SettingsLayoutRow {
                VStack(alignment: .leading, spacing: 3) {
                    Text("诊断支持信息")
                    Text("仅包含版本、系统、数据库计数与文件大小；不包含任务标题或正文。")
                        .font(.system(size: 11))
                        .foregroundStyle(WeekflowPalette.secondaryText)
                }
                Spacer()
                Button("导出诊断") { exportDiagnosticSupportBundle() }
                    .buttonStyle(.bordered)
                    .pointingHandCursor()
            }

            if let dataOperationMessage {
                Text(dataOperationMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(dataOperationMessage.hasPrefix("失败") ? .orange : WeekflowPalette.secondaryText)
                    .textSelection(.enabled)
            }

            Text("数据默认仅保存在本机；Weekflow 不会自动上传归档或备份。")
                .font(.system(size: 12))
                .foregroundStyle(WeekflowPalette.secondaryText)
        }
        .padding(18)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(WeekflowPalette.border, lineWidth: 1)
        }
        .frame(maxWidth: 480)
    }

    private var backupStatusText: String {
        if let failure = backupStatus.latestFailure {
            return "最近备份失败：\(failure)"
        }
        if let date = backupStatus.lastSuccessAt {
            return "最近成功 \(date.formatted(date: .abbreviated, time: .shortened)) · 共 \(backupStatus.backupCount) 份"
        }
        return backupStatus.backupCount > 0
            ? "已有 \(backupStatus.backupCount) 份校验通过的备份"
            : "尚未创建备份"
    }

    private func refreshBackupStatus() {
        backupStatus = store.databaseBackupStatus()
    }

    private func createBackup() {
        isDataOperationRunning = true
        dataOperationMessage = "正在创建并校验备份…"
        Task {
            defer {
                isDataOperationRunning = false
                refreshBackupStatus()
            }
            do {
                try await store.createVerifiedBackup()
                dataOperationMessage = "备份已创建并通过完整性校验。"
            } catch {
                dataOperationMessage = "失败：\(error.localizedDescription)"
            }
        }
    }

    private func exportFullDataArchive() {
        let panel = NSSavePanel()
        panel.title = "导出 Weekflow 完整数据"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Weekflow-Data-\(Date.now.formatted(.iso8601.year().month().day())).weekflow.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportFullDataArchive(to: url)
            dataOperationMessage = "完整数据已导出：\(url.lastPathComponent)"
        } catch {
            dataOperationMessage = "失败：\(error.localizedDescription)"
        }
    }

    private func chooseFullDataArchive() {
        let panel = NSOpenPanel()
        panel.title = "选择 Weekflow 完整数据归档"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        pendingImportURL = panel.url
    }

    private func exportDiagnosticSupportBundle() {
        let panel = NSSavePanel()
        panel.title = "导出 Weekflow 诊断支持信息"
        panel.prompt = "导出"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Weekflow-Diagnostics-\(Date.now.formatted(.iso8601.year().month().day())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportDiagnosticSupportBundle(to: url)
            dataOperationMessage = "诊断支持信息已导出：\(url.lastPathComponent)"
        } catch {
            dataOperationMessage = "失败：\(error.localizedDescription)"
        }
    }

    private func confirmFullDataImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        isDataOperationRunning = true
        dataOperationMessage = "正在校验、备份并导入…"
        let accessedSecurityScope = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if accessedSecurityScope { url.stopAccessingSecurityScopedResource() }
                isDataOperationRunning = false
                refreshBackupStatus()
            }
            do {
                try await store.importFullDataArchive(from: url)
                dataOperationMessage = "完整数据导入成功。"
            } catch {
                dataOperationMessage = "失败：\(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var updateStatusView: some View {
        switch updateCheckState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在检查…")
            }
            .font(.system(size: 12))
            .foregroundStyle(WeekflowPalette.secondaryText)
        case let .upToDate(version):
            Label("已是最新版本（\(displayVersion(version))）。", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case let .updateAvailable(version, releaseURL):
            HStack(spacing: 10) {
                Label("发现新版本 \(displayVersion(version))。", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12))
                Button("查看版本") { openURL(releaseURL) }
                    .buttonStyle(.link)
                    .pointingHandCursor()
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        }
    }

    private var currentVersionText: String {
        guard let currentVersion = WeekflowAppVersion.current else {
            return "当前为未打包的开发构建"
        }
        return "当前版本 \(displayVersion(currentVersion))"
    }

    private var updateButtonTitle: String {
        updateCheckState.isChecking ? "检查中" : "检查更新"
    }

    private func checkForUpdates() {
        guard let currentVersion = WeekflowAppVersion.current else {
            updateCheckState = .failed(message: "未打包的开发构建无法比较版本。")
            return
        }
        updateCheckState = .checking
        Task {
            do {
                let result = try await AppUpdateService().check(currentVersion: currentVersion)
                updateCheckState = result.isUpdateAvailable
                    ? .updateAvailable(version: result.latestVersion, releaseURL: result.releaseURL)
                    : .upToDate(version: result.currentVersion)
            } catch is CancellationError {
                updateCheckState = .idle
            } catch {
                updateCheckState = .failed(
                    message: (error as? LocalizedError)?.errorDescription ?? "暂时无法检查更新，请稍后重试。"
                )
            }
        }
    }

    private func displayVersion(_ version: String) -> String {
        version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }

    private func chartPaletteOverlay(in availableSize: CGSize) -> some View {
        let menuSize = CGSize(width: 248, height: 344)
        let pointerHeight = WeekflowLayout.taskDurationMenuPointerHeight
        let surfaceSize = CGSize(width: menuSize.width, height: menuSize.height + pointerHeight)
        let origin = CGPoint(
            x: min(
                max(chartPaletteAnchor.maxX - surfaceSize.width, 6),
                availableSize.width - surfaceSize.width - 6
            ),
            y: min(
                chartPaletteAnchor.maxY + 3,
                availableSize.height - surfaceSize.height - 6
            )
        )
        let pointerCenterX = min(
            max(chartPaletteAnchor.midX - origin.x, WeekflowLayout.taskDurationMenuPointerWidth / 2),
            surfaceSize.width - WeekflowLayout.taskDurationMenuPointerWidth / 2
        )

        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [
                    chartPaletteAnchor,
                    CGRect(origin: origin, size: surfaceSize)
                ],
                action: { isChartPalettePresented = false }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            TaskControlMenuSurface(
                content: AnyView(
                    ChartPaletteMenu(
                        selection: $chartPaletteRawValue,
                        colorScheme: colorScheme
                    )
                ),
                menuSize: menuSize,
                pointerSize: CGSize(
                    width: WeekflowLayout.taskDurationMenuPointerWidth,
                    height: pointerHeight
                ),
                pointerCenterX: pointerCenterX
            )
            .offset(x: origin.x, y: origin.y)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: isChartPalettePresented)
    }

    private func colorPaletteOverlay(in availableSize: CGSize) -> some View {
        let panelSize = CGSize(
            width: WeekflowLayout.colorPickerPanelWidth,
            height: WeekflowLayout.colorPickerPanelHeight
        )
        let panelOrigin = CGPoint(
            x: min(max(colorPaletteAnchor.maxX - panelSize.width, 6), availableSize.width - panelSize.width - 6),
            y: min(colorPaletteAnchor.maxY + 6, availableSize.height - panelSize.height - 6)
        )
        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [
                    colorPaletteAnchor,
                    CGRect(origin: panelOrigin, size: panelSize)
                ],
                monitoredEventMask: .leftMouseUp,
                action: { isColorPalettePresented = false }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            CompactColorPalettePanel(
                selectedToken: $colorToken,
                interactionChanged: { _ in }
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: panelOrigin.x + panelSize.width / 2, y: panelOrigin.y + panelSize.height / 2)
            .contentShape(Rectangle())
            .zIndex(10)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: isColorPalettePresented)
    }

    private func themeColorPaletteOverlay(in availableSize: CGSize) -> some View {
        let panelSize = CGSize(
            width: WeekflowLayout.colorPickerPanelWidth,
            height: WeekflowLayout.colorPickerPanelHeight
        )
        let panelOrigin = CGPoint(
            x: min(
                max(themeColorPaletteAnchor.maxX - panelSize.width, 6),
                availableSize.width - panelSize.width - 6
            ),
            y: min(
                themeColorPaletteAnchor.maxY + 6,
                availableSize.height - panelSize.height - 6
            )
        )
        return ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [
                    themeColorPaletteAnchor,
                    CGRect(origin: panelOrigin, size: panelSize)
                ],
                monitoredEventMask: .leftMouseUp,
                action: { isThemeColorPalettePresented = false }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            CompactColorPalettePanel(
                selectedToken: $themeColorToken,
                interactionChanged: { _ in }
            )
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: panelOrigin.x + panelSize.width / 2, y: panelOrigin.y + panelSize.height / 2)
            .contentShape(Rectangle())
            .zIndex(10)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
        }
        .frame(width: availableSize.width, height: availableSize.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.12), value: isThemeColorPalettePresented)
    }

    private var progressPreview: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(alwaysShowDailyProgress ? WeekflowPalette.progressTrackEmpty : WeekflowPalette.border.opacity(0.5))
                .overlay(Capsule().stroke(WeekflowPalette.border.opacity(0.55), lineWidth: 1))
            Capsule()
                .fill(DailyProgressPreferences.color(for: colorToken))
                .frame(width: 150)
        }
        .frame(width: 360, height: WeekflowLayout.homeDailyProgressHeight)
        .padding(.vertical, 4)
        .accessibilityLabel("每日进度条预览")
    }

}

private enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(version: String, releaseURL: URL)
    case failed(message: String)

    var isChecking: Bool {
        self == .checking
    }
}
