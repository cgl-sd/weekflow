import SwiftUI

struct FocusMenuBarPanel: View {
    @Bindable var timer: FocusTimerService
    @State private var isEditingDuration = false

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                header
                modeSelector
                countdown
                if let taskTitle = timer.linkedTaskTitle {
                    Label(taskTitle, systemImage: "checkmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WeekflowPalette.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                controls
            }
            .padding(14)

            if isEditingDuration {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { isEditingDuration = false }
                FocusDurationMenu(
                    minutes: Binding(
                        get: { timer.currentDurationMinutes },
                        set: { timer.updateCurrentDurationMinutes($0) }
                    ),
                    width: 154,
                    height: 188,
                    onSelection: {
                        withAnimation(.easeOut(duration: 0.1)) {
                            isEditingDuration = false
                        }
                    }
                )
                .offset(y: -26)
                .zIndex(10)
            }
        }
        .frame(width: 256, height: timer.linkedTaskTitle == nil ? 296 : 318)
        .background(WeekflowPalette.floatingPanelSurface)
        .onChange(of: timer.isRunning) { _, running in
            if running { isEditingDuration = false }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("专注模式")
                    .font(.system(size: 15, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(timer.selectedModeColor)
            }
            Spacer()
            Image(systemName: timer.isRunning ? timer.selectedModeRunningSymbol : timer.selectedModeSymbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(timer.selectedModeColor)
                .symbolEffect(.pulse, options: .repeating, isActive: timer.isRunning)
                .frame(width: 34, height: 34)
                .background(timer.selectedModeColor.opacity(0.12), in: Circle())
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ForEach(FocusModePreferences.modes) { mode in
                WeekflowButton {
                    timer.stopAndSelect(mode.id)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 12, weight: .medium))
                        Text(mode.title)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(timer.selectedModeID == mode.id ? mode.color : WeekflowPalette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        timer.selectedModeID == mode.id
                            ? mode.color.opacity(0.12)
                            : WeekflowPalette.floatingPanelRaisedSurface,
                        in: WeekflowRoundedRectangle(cornerRadius: 7)
                    )
                    .overlay {
                        WeekflowRoundedRectangle(cornerRadius: 7)
                            .stroke(
                                timer.selectedModeID == mode.id
                                    ? mode.color.opacity(0.48)
                                    : WeekflowPalette.border.opacity(0.72),
                                lineWidth: 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private var countdown: some View {
        let usesExtendedCountdown = timer.formattedRemaining.count >= 6
        return ZStack {
            Circle()
                .stroke(WeekflowPalette.border.opacity(0.50), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(1 - timer.progress, 0.001))
                .stroke(
                    timer.selectedModeColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.9), value: timer.progress)
            WeekflowButton {
                guard !timer.isRunning else { return }
                isEditingDuration.toggle()
            } label: {
                Text(timer.formattedRemaining)
                    .font(.system(size: usesExtendedCountdown ? 26 : 31, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: usesExtendedCountdown ? 94 : 106)
                    .contentTransition(.numericText())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .frame(width: 132, height: 132)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            panelControl(
                symbol: timer.isRunning ? "pause.fill" : "play.fill",
                title: timer.isRunning ? "暂停" : (timer.hasStarted ? "继续" : "开始"),
                primary: true,
                disabled: false
            ) { timer.toggle() }
            panelControl(
                symbol: "stop.fill",
                title: "停止",
                primary: false,
                disabled: !timer.hasStarted && !timer.isRunning
            ) { timer.stop() }
        }
    }

    private func panelControl(
        symbol: String,
        title: String,
        primary: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        WeekflowButton(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(primary ? Color.white : WeekflowPalette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    primary ? timer.selectedModeColor : WeekflowPalette.floatingPanelRaisedSurface,
                    in: WeekflowRoundedRectangle(cornerRadius: 7)
                )
                .overlay {
                    WeekflowRoundedRectangle(cornerRadius: 7)
                        .stroke(primary ? Color.clear : WeekflowPalette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
    }

    private var statusText: String {
        if timer.isRunning { return "专注进行中" }
        if timer.hasStarted { return "已暂停" }
        return "准备开始 · \(timer.selectedModeTitle)"
    }
}
