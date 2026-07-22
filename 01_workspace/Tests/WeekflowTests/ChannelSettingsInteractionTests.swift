import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Weekflow

@MainActor
@Test func dailyProgressPreferencesKeepStableLocalDefaultsAndVisibilityRules() {
    #expect(DailyProgressPreferences.colorTokenKey == "weekflow.dailyProgress.color")
    #expect(DailyProgressPreferences.alwaysShowKey == "weekflow.dailyProgress.alwaysShow")
    #expect(TaskChannelRGB.resolve(DailyProgressPreferences.defaultColorToken) == TaskChannelRGB(red: 85, green: 201, blue: 135))
    #expect(!DailyProgressPreferences.isVisible(hasProgress: false, alwaysShow: false))
    #expect(DailyProgressPreferences.isVisible(hasProgress: true, alwaysShow: false))
    #expect(DailyProgressPreferences.isVisible(hasProgress: false, alwaysShow: true))
    #expect(WorkspaceSettingsSection.allCases.map(\.title) == ["通用", "分类与频道", "日历"])
}

@MainActor
@Test func applicationThemeKeepsAStablePurpleDefaultAndUsesTheSharedColorPicker() throws {
    #expect(AppThemePreferences.colorTokenKey == "weekflow.appearance.themeColor")
    #expect(
        TaskChannelRGB.resolve(AppThemePreferences.defaultColorToken)
            == TaskChannelRGB(red: 154, green: 108, blue: 227)
    )

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Weekflow")
    let settingsSource = try String(
        contentsOf: root.appendingPathComponent("Views/ChannelSettingsView.swift"),
        encoding: .utf8
    )
    let paletteSource = try String(
        contentsOf: root.appendingPathComponent("Support/WeekflowPalette.swift"),
        encoding: .utf8
    )
    let weeklyReviewSource = try String(
        contentsOf: root.appendingPathComponent("Views/WeeklyReviewView.swift"),
        encoding: .utf8
    )
    let _assistantSource_part0 = try String(
        contentsOf: root.appendingPathComponent("Views/AssistantPanelViews.swift"),
        encoding: .utf8
    )
    let _assistantSource_part1 = try String(
        contentsOf: root.appendingPathComponent("Views/AssistantCalendarViews.swift"),
        encoding: .utf8
    )
    let _assistantSource_part2 = try String(
        contentsOf: root.appendingPathComponent("Views/AssistantListViews.swift"),
        encoding: .utf8
    )
    let assistantSource = _assistantSource_part0 + _assistantSource_part1 + _assistantSource_part2
    let homeSource = try String(
        contentsOf: root.appendingPathComponent("Views/HomeBoardComponents.swift"),
        encoding: .utf8
    )

    #expect(settingsSource.contains("Text(\"软件偏好设置\")"))
    #expect(settingsSource.contains("Text(\"主题色\")"))
    #expect(settingsSource.contains("CompactColorPalettePanel("))
    #expect(!settingsSource.contains("主题色预览"))
    #expect(settingsSource.contains("全局进度条颜色 · 无进度时隐藏"))
    #expect(settingsSource.contains("调整任务文字、信息和图标大小"))
    #expect(paletteSource.contains("static var objective: Color { AppThemePreferences.currentColor }"))
    #expect(weeklyReviewSource.contains("WeekflowDailyProgressTrack("))
    #expect(assistantSource.contains("WeekflowDailyProgressTrack("))
    #expect(homeSource.contains(".background(WeekflowPalette.objective"))
}

@MainActor
@Test func continuousColorPickerOnlyDismissesOutsideItsPanel() {
    #expect(!ColorPickerDismissalPolicy.shouldDismiss(isInteractingInsidePanel: true))
    #expect(ColorPickerDismissalPolicy.shouldDismiss(isInteractingInsidePanel: false))
}

@MainActor
@Test func appearancePreferenceSupportsSystemLightAndDarkModes() {
    #expect(AppAppearancePreference.storageKey == "weekflow.appearance")
    #expect(AppAppearancePreference.defaultValue == AppAppearancePreference.system.rawValue)
    #expect(AppAppearancePreference.allCases.map(\.title) == ["跟随系统", "浅色", "深色"])
    #expect(AppAppearancePreference.system.colorScheme == nil)
    #expect(AppAppearancePreference.light.colorScheme == .light)
    #expect(AppAppearancePreference.dark.colorScheme == .dark)
    #expect(AppAppearancePreference.system.applicationAppearance == nil)
    #expect(AppAppearancePreference.light.applicationAppearance?.name == .aqua)
    #expect(AppAppearancePreference.dark.applicationAppearance?.name == .darkAqua)
}

@MainActor
@Test func taskCardTypographyPreferencesKeepHomeTextAndIconGroupsAdjustable() {
    #expect(TaskCardTypographyPreferences.defaultTaskTextSize == 13)
    #expect(TaskCardTypographyPreferences.defaultMetadataSize == 9)
    #expect(TaskCardTypographyPreferences.defaultIconSize == 11.5)
    #expect(TaskCardTypographyPreferences.completionIconSizeAdjustment == 1.5)
    #expect(TaskCardTypographyPreferences.taskTextSize(from: 10) == 11)
    #expect(TaskCardTypographyPreferences.taskTextSize(from: 13.4) == 13)
    #expect(TaskCardTypographyPreferences.taskTextSize(from: 20) == 15)
    #expect(TaskCardTypographyPreferences.metadataSize(from: 7) == 8)
    #expect(TaskCardTypographyPreferences.metadataSize(from: 9.2) == 9)
    #expect(TaskCardTypographyPreferences.metadataSize(from: 9.3) == 9.5)
    #expect(TaskCardTypographyPreferences.metadataSize(from: 20) == 11)
    #expect(TaskCardTypographyPreferences.iconSize(from: 9) == 10)
    #expect(TaskCardTypographyPreferences.iconSize(from: 11.7) == 11.5)
    #expect(TaskCardTypographyPreferences.iconSize(from: 20) == 14)
}

@MainActor
@Test func generalSettingsRendersDailyProgressControlsAtAcceptedSize() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowGeneralSettings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    let view = ChannelSettingsView(store: store, initialSection: .general)
        .frame(width: 860, height: 620)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 860, height: 620)
    let window = NSWindow(
        contentRect: host.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()

    #expect(host.frame.size == NSSize(width: 860, height: 620))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    #expect(bitmap.pixelsWide > 0)
    #expect(bitmap.pixelsHigh > 0)
    try writeGeneralSettingsSnapshotIfRequested(bitmap)
    _ = window
}

@MainActor
@Test func continuousColorSelectionRoundTripsNamedAndCustomColors() {
    let red = HSBColorSelection(token: "red")
    #expect(TaskChannelRGB.resolve(red.encodedToken) == TaskChannelRGB.resolve("red"))

    let vividGreen = HSBColorSelection(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
    #expect(TaskChannelRGB.resolve(vividGreen.encodedToken) == TaskChannelRGB(red: 0, green: 255, blue: 0))

    let custom = HSBColorSelection(token: "rgb:18,52,86")
    #expect(TaskChannelRGB.resolve(custom.encodedToken) == TaskChannelRGB(red: 18, green: 52, blue: 86))
}

@MainActor
@Test func channelColorRGBTokenParsesNamedAndCustomValues() {
    #expect(TaskChannelRGB.resolve("orange") == TaskChannelRGB(red: 211, green: 146, blue: 56))
    #expect(TaskChannelRGB.resolve("rgb:12, 34,255") == TaskChannelRGB(red: 12, green: 34, blue: 255))
    #expect(TaskChannelRGB(red: -1, green: 128, blue: 300).encodedColorName == "rgb:0,128,255")
    #expect(TaskChannelRGB.resolve("rgb:256,0,0") == nil)
    #expect(TaskChannelRGB.resolve("rgb:1,2") == nil)
    #expect(TaskChannelRGB.resolve("unknown") == nil)
}

@MainActor
@Test func legacyChannelsDecodeWithoutIconOrParentMetadata() throws {
    let channel = try JSONDecoder().decode(TaskChannel.self, from: Data("""
    {"id":"legacy","title":"旧频道","colorName":"gray","isPersonal":false,"countsTowardWorkload":true,"isDefault":false}
    """.utf8))

    #expect(channel.iconName == nil)
    #expect(channel.archivedAt == nil)
    #expect(channel.resolvedIconName == "number")
}

@MainActor
@Test func deletingAChannelUsesSoftDeletionAndKeepsTheRecord() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowChannelSoftDelete-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let store = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    store.deleteChannel(id: "research")

    #expect(store.channel(for: "research")?.archivedAt != nil)
    #expect(!store.activeChannels.contains(where: { $0.id == "research" }))
    let reloaded = WeekflowStore(storage: LocalStorage(baseDirectory: folder))
    #expect(reloaded.channel(for: "research")?.archivedAt != nil)
}

@MainActor
@Test func settingsUseContinuousColorFieldAndHueTrack() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let settings = try ["ChannelSettingsView.swift", "SettingsColorPickers.swift", "ChannelSettingComponents.swift"]
            .map { try String(contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/\($0)"), encoding: .utf8) }
            .joined(separator: "\n")
    #expect(settings.contains("SettingsHoverControl"))
    #expect(settings.contains("AppearanceSegmentedControl"))
    #expect(settings.contains("CompactColorPalettePicker"))
    #expect(settings.contains("CompactColorPalettePanel"))
    #expect(settings.contains("SaturationBrightnessField"))
    #expect(settings.contains("HueSelectionTrack"))
    #expect(settings.contains("DragGesture(minimumDistance: 0)"))
    #expect(settings.contains("interactionChanged(true)"))
    #expect(settings.contains("ColorPickerDismissalPolicy.shouldDismiss("))
    #expect(settings.contains("LinearGradient("))
    #expect(settings.contains("ColorPaletteAnchorPreferenceKey"))
    #expect(settings.contains("ChannelIconButton"))
    #expect(settings.contains("ChannelIconSelectionPanel"))
    #expect(settings.contains("ChannelIconSelectionRow"))
    #expect(settings.contains("ChannelIconAnchorPreferenceKey"))
    #expect(settings.contains("ChannelDeleteButton"))
    #expect(settings.contains("store.activeChannels"))
    #expect(!settings.contains("parentID"))
    #expect(!settings.contains("ColorPicker("))
    #expect(!settings.contains("ColorWheelWell"))
    #expect(!settings.contains("ChannelSettingsPalette"))
    #expect(!settings.contains("ChannelColorSwatch"))
    #expect(!settings.contains("LazyVGrid"))
    #expect(!settings.contains("SettingsInteractiveRow"))
    #expect(!settings.contains("RGBField"))
    #expect(settings.contains(".frame(width: availableSize.width, height: availableSize.height)"))
    #expect(settings.contains("monitoredEventMask: .leftMouseUp"))
    #expect(settings.contains("preference.applyToApplication()"))
}

@MainActor
@Test func continuousColorPickerRendersAtReferenceSize() throws {
    let view = CompactColorPalettePanel(
        selectedToken: .constant("rgb:49,154,72")
    )
    .frame(
        width: WeekflowLayout.colorPickerPanelWidth,
        height: WeekflowLayout.colorPickerPanelHeight
    )
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(
        x: 0,
        y: 0,
        width: WeekflowLayout.colorPickerPanelWidth,
        height: WeekflowLayout.colorPickerPanelHeight
    )
    host.layoutSubtreeIfNeeded()

    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    #expect(bitmap.pixelsWide > 0)
    #expect(bitmap.pixelsHigh > 0)
}

@MainActor
@Test func newChannelComposerKeepsIconNameColorAndActionInOrder() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let settings = try ["ChannelSettingsView.swift", "SettingsColorPickers.swift", "ChannelSettingComponents.swift"]
            .map { try String(contentsOf: packageRoot.appendingPathComponent("Sources/Weekflow/Views/\($0)"), encoding: .utf8) }
            .joined(separator: "\n")
    let draftStart = try #require(settings.range(of: "HStack(spacing: 10) {\n                        ChannelIconButton("))
    let draftEnd = try #require(settings.range(of: "Divider()", range: draftStart.upperBound..<settings.endIndex))
    let draft = String(settings[draftStart.lowerBound..<draftEnd.lowerBound])

    let icon = try #require(draft.range(of: "ChannelIconButton("))
    let name = try #require(draft.range(of: "TextField(\"新频道名称\""))
    let color = try #require(draft.range(of: "ChannelColorPaletteButton("))
    let create = try #require(draft.range(of: "ChannelCreateButton("))
    #expect(icon.lowerBound < name.lowerBound)
    #expect(name.lowerBound < color.lowerBound)
    #expect(color.lowerBound < create.lowerBound)
}

@MainActor
@Test func channelSettingChangesPersistImmediatelyWithoutSaveAction() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowChannelSettings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)
    var channel = try #require(store.channel(for: "work"))
    channel.countsTowardWorkload = false // Retained for decoding older local data; no longer used as UI enablement.
    channel.colorName = TaskChannelRGB(red: 18, green: 52, blue: 86).encodedColorName
    store.updateChannel(channel)

    let reloaded = WeekflowStore(storage: storage)
    let saved = try #require(reloaded.channel(for: "work"))
    #expect(saved.countsTowardWorkload == false)
    #expect(saved.colorName == "rgb:18,52,86")
    #expect(TaskChannelRGB.resolve(saved.colorName) == TaskChannelRGB(red: 18, green: 52, blue: 86))
}

@MainActor
@Test func settingDefaultChannelRemainsExclusiveAndPersists() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowDefaultChannel-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let storage = LocalStorage(baseDirectory: folder)
    let store = WeekflowStore(storage: storage)
    var channel = try #require(store.channel(for: "research"))
    channel.isDefault = true
    store.updateChannel(channel)

    let reloaded = WeekflowStore(storage: storage)
    #expect(reloaded.channel(for: "research")?.isDefault == true)
    #expect(reloaded.channels.filter(\.isDefault).map(\.id) == ["research"])
}

private func writeGeneralSettingsSnapshotIfRequested(_ bitmap: NSBitmapImageRep) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: folder.appendingPathComponent("设置-通用-每日进度.png"), options: .atomic)
}
