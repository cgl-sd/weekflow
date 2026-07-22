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
    @State private var isColorPaletteInteractionActive = false
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
            WindowOutsideClickMonitor(
                protectedRects: [anchor, CGRect(origin: origin, size: panelSize)],
                monitoredEventMask: .leftMouseUp,
                action: {
                    guard ColorPickerDismissalPolicy.shouldDismiss(
                        isInteractingInsidePanel: isColorPaletteInteractionActive
                    ) else { return }
                    activeChannelPaletteID = nil
                }
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
                interactionChanged: { isColorPaletteInteractionActive = $0 }
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
        isColorPaletteInteractionActive = false
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

private enum ChannelSettingsDraftID {
    static let newChannel = "__new-channel__"
}

private struct GeneralSettingsView: View {
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
    @State private var isColorPaletteInteractionActive = false
    @State private var colorPaletteAnchor = CGRect.zero
    @State private var isThemeColorPalettePresented = false
    @State private var isThemeColorPaletteInteractionActive = false
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
            WindowOutsideClickMonitor(
                protectedRects: [
                    colorPaletteAnchor,
                    CGRect(origin: panelOrigin, size: panelSize)
                ],
                monitoredEventMask: .leftMouseUp,
                action: {
                    guard ColorPickerDismissalPolicy.shouldDismiss(
                        isInteractingInsidePanel: isColorPaletteInteractionActive
                    ) else { return }
                    isColorPalettePresented = false
                }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            CompactColorPalettePanel(
                selectedToken: $colorToken,
                interactionChanged: { isColorPaletteInteractionActive = $0 }
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
            WindowOutsideClickMonitor(
                protectedRects: [
                    themeColorPaletteAnchor,
                    CGRect(origin: panelOrigin, size: panelSize)
                ],
                monitoredEventMask: .leftMouseUp,
                action: {
                    guard ColorPickerDismissalPolicy.shouldDismiss(
                        isInteractingInsidePanel: isThemeColorPaletteInteractionActive
                    ) else { return }
                    isThemeColorPalettePresented = false
                }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .allowsHitTesting(false)

            CompactColorPalettePanel(
                selectedToken: $themeColorToken,
                interactionChanged: { isThemeColorPaletteInteractionActive = $0 }
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

private struct ChartPalettePicker: View {
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

private struct ChartPaletteMenu: View {
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

private struct ChartPaletteMenuRow: View {
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

private struct SettingsLayoutRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) { content }
            .frame(maxWidth: .infinity, minHeight: 32)
    }
}

private struct ChartPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct SettingsHoverControl<Content: View>: View {
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

private struct AppearanceSegmentedControl: View {
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

private struct ColorPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct ThemeColorPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct CompactColorPalettePicker: View {
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

private struct ThemeColorPalettePicker: View {
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
        VStack(spacing: 8) {
            SaturationBrightnessField(selection: selectionBinding)
                .frame(height: WeekflowLayout.colorPickerFieldHeight)
            HueSelectionTrack(selection: selectionBinding)
                .frame(height: WeekflowLayout.colorPickerHueTrackHeight)
        }
        .padding(10)
        .frame(
            width: WeekflowLayout.colorPickerPanelWidth,
            height: WeekflowLayout.colorPickerPanelHeight
        )
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 10))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 10)
                .stroke(WeekflowPalette.borderStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in interactionChanged(true) }
                .onEnded { _ in
                    DispatchQueue.main.async { interactionChanged(false) }
                }
        )
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

enum ColorPickerDismissalPolicy {
    static func shouldDismiss(isInteractingInsidePanel: Bool) -> Bool {
        !isInteractingInsidePanel
    }
}

private struct SaturationBrightnessField: View {
    @Binding var selection: HSBColorSelection

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
                guard size.width > 0, size.height > 0 else { return }
                selection.saturation = min(max(Double(value.location.x / size.width), 0), 1)
                selection.brightness = min(max(1 - Double(value.location.y / size.height), 0), 1)
            }
    }
}

private struct HueSelectionTrack: View {
    @Binding var selection: HSBColorSelection

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
            }
            .pointingHandCursor()
        }
        .accessibilityLabel("色相")
    }

    private func hueGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                selection.hue = min(max(Double(value.location.x / width), 0), 1)
            }
    }
}

private struct ChannelPaletteAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ChannelSettingRow: View {
    let channel: TaskChannel
    @Bindable var store: WeekflowStore
    let showColorPalette: () -> Void
    let showIconMenu: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ChannelIconButton(
                    channelID: currentChannel.id,
                    iconName: currentChannel.resolvedIconName,
                    action: showIconMenu
                )
                    .foregroundStyle(currentChannel.color)
                TextField("频道名称", text: channelBinding(\.title))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)

                ChannelColorPaletteButton(
                    channelID: currentChannel.id,
                    color: currentChannel.color,
                    action: showColorPalette
                )

                Toggle("默认", isOn: channelBinding(\.isDefault))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .pointingHandCursor()
                    .help("设为新任务的默认频道")
                    .accessibilityLabel("默认频道")

                ChannelDeleteButton {
                    store.deleteChannel(id: currentChannel.id)
                }
            }
        }
        .padding(11)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 8))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 8)
                .stroke(WeekflowPalette.border, lineWidth: 1)
        }
    }

    private var currentChannel: TaskChannel {
        store.channel(for: channel.id) ?? channel
    }

    private func channelBinding<Value>(_ keyPath: WritableKeyPath<TaskChannel, Value>) -> Binding<Value> {
        Binding(
            get: { currentChannel[keyPath: keyPath] },
            set: { update(keyPath, to: $0) }
        )
    }

    private func update<Value>(_ keyPath: WritableKeyPath<TaskChannel, Value>, to value: Value) {
        var updated = currentChannel
        updated[keyPath: keyPath] = value
        store.updateChannel(updated)
    }

}

private struct ChannelColorPaletteButton: View {
    let channelID: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 17, height: 17)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.secondaryText)
            }
            .frame(width: 45, height: 26)
            .background(
                isHovering ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .accessibilityLabel("选择频道颜色")
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ChannelPaletteAnchorPreferenceKey.self,
                    value: [channelID: geometry.frame(in: .named("channel-settings"))]
                )
            }
        }
    }
}

private struct ChannelDeleteButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? WeekflowPalette.urgent : WeekflowPalette.secondaryText)
                .frame(width: 28, height: 26)
                .background(
                    isHovering ? WeekflowPalette.urgent.opacity(0.10) : .clear,
                    in: WeekflowRoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .help("删除频道")
        .accessibilityLabel("删除频道")
    }
}

private struct ChannelCreateButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            Label("新建频道", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 30)
                .background(
                    WeekflowPalette.objective.opacity(isHovering ? 0.86 : 1),
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
    }
}

private enum ChannelIconOption: String, CaseIterable, Identifiable {
    case number
    case lock = "lock.fill"
    case briefcase
    case document = "doc.text"
    case research = "books.vertical"
    case study = "graduationcap"
    case folder
    case tag
    case star

    var id: String { rawValue }

    var title: String {
        switch self {
        case .number: "井号"
        case .lock: "锁"
        case .briefcase: "工作"
        case .document: "文稿"
        case .research: "资料"
        case .study: "学习"
        case .folder: "文件夹"
        case .tag: "标签"
        case .star: "星标"
        }
    }
}

private struct ChannelIconAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct ChannelIconButton: View {
    let channelID: String
    let iconName: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .frame(width: 17)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(WeekflowPalette.textMuted)
            }
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 26)
                .background(
                    isHovering ? WeekflowPalette.surfaceHover : WeekflowPalette.appBackground,
                    in: WeekflowRoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .help("选择频道图标")
        .accessibilityLabel("选择频道图标")
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ChannelIconAnchorPreferenceKey.self,
                    value: [channelID: geometry.frame(in: .named("channel-settings"))]
                )
            }
        }
    }
}

private struct ChannelIconSelectionPanel: View {
    let selection: String
    let select: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ChannelIconOption.allCases) { option in
                ChannelIconSelectionRow(
                    option: option,
                    isSelected: option.rawValue == selection,
                    action: { select(option.rawValue) }
                )
            }
        }
        .padding(6)
        .background(WeekflowPalette.surface, in: WeekflowRoundedRectangle(cornerRadius: 7))
        .overlay {
            WeekflowRoundedRectangle(cornerRadius: 7)
                .stroke(WeekflowPalette.borderStrong, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
    }
}

private struct ChannelIconSelectionRow: View {
    let option: ChannelIconOption
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        WeekflowButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: option.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .leading)
                Text(option.title)
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 16, alignment: .trailing)
            }
            .foregroundStyle(WeekflowPalette.textPrimary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(
                isHovering ? WeekflowPalette.surfaceHover : .clear,
                in: WeekflowRoundedRectangle(cornerRadius: 5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .stablePointingHandHover { isHovering = $0 }
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "已选择" : "")
    }
}
