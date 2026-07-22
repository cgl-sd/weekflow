import SwiftUI

struct ChannelSettingRow: View {
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

struct ChannelColorPaletteButton: View {
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

struct ChannelDeleteButton: View {
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

struct ChannelCreateButton: View {
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

enum ChannelIconOption: String, CaseIterable, Identifiable {
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

struct ChannelIconAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct ChannelIconButton: View {
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

struct ChannelIconSelectionPanel: View {
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

struct ChannelIconSelectionRow: View {
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
