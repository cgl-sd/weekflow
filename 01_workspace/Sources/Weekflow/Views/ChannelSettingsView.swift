import SwiftUI

import SwiftUI

enum WorkspaceSettingsSection: String, CaseIterable, Identifiable {
    case general
    case channels
    case calendar

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "通用"
        case .channels: "分类与频道"
        case .calendar: "日历"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .channels: "number"
        case .calendar: "calendar"
        }
    }
}

struct ChannelSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: WeekflowStore
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

    init(
        store: WeekflowStore,
        initialSection: WorkspaceSettingsSection = .channels
    ) {
        self.store = store
        _selectedSection = State(initialValue: initialSection)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                WeekflowButton { dismiss() } label: {
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
                    GeneralSettingsView()
                case .channels:
                    channelSettings
                case .calendar:
                    calendarSettings
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 860, height: 620, alignment: .topLeading)
        .background(WeekflowPalette.canvas)
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
            // Transparent tap layer: clicking anywhere outside the panel dismisses it
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { activeChannelPaletteID = nil }
                .frame(width: availableSize.width, height: availableSize.height)

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
            .offset(x: origin.x, y: origin.y)
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
            .offset(x: origin.x, y: origin.y)
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
    @State private var isColorPalettePresented = false
    @State private var colorPaletteAnchor = CGRect.zero
    @State private var isThemeColorPalettePresented = false
    @State private var themeColorPaletteAnchor = CGRect.zero
    @State private var isChartPalettePresented = false
    @State private var chartPaletteAnchor = CGRect.zero

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
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isColorPalettePresented = false }
                .frame(width: availableSize.width, height: availableSize.height)

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
            .offset(x: panelOrigin.x, y: panelOrigin.y)
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
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { isThemeColorPalettePresented = false }
                .frame(width: availableSize.width, height: availableSize.height)

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
            .offset(x: panelOrigin.x, y: panelOrigin.y)
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

