import SwiftUI

struct FocusView: View {
    @Bindable var timer: FocusTimerService
    @State private var pendingMode: FocusMode?
    @State private var isEditingDuration: Bool

    init(timer: FocusTimerService, initiallyEditingDuration: Bool = false) {
        self.timer = timer
        _isEditingDuration = State(initialValue: initiallyEditingDuration)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditingDuration {
                            withAnimation(.easeOut(duration: 0.1)) { isEditingDuration = false }
                        }
                    }
                VStack {
                    focusComponent(countdownSize: min(max(proxy.size.height * 0.13, 78), 104))
                        .frame(width: 520)
                        .padding(.top, max(proxy.size.height * 0.11, 40))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .background(WeekflowPalette.canvas)
        .onChange(of: timer.isRunning) { _, running in
            if running { isEditingDuration = false }
        }
        .confirmationDialog(
            "结束当前专注并切换模式？",
            isPresented: Binding(
                get: { pendingMode != nil },
                set: { if !$0 { pendingMode = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("结束并切换") {
                if let mode = pendingMode { timer.stopAndSelect(mode) }
                pendingMode = nil
            }
            Button("继续当前专注", role: .cancel) { pendingMode = nil }
        }
    }

    private func focusComponent(countdownSize: CGFloat) -> some View {
        let usesExtendedCountdown = timer.formattedRemaining.count >= 6
        return VStack(spacing: 24) {
            Text("专注模式")
                .font(.system(size: 20, weight: .semibold))

            HStack(spacing: 8) {
                ForEach(FocusMode.allCases) { mode in
                    FocusModeButton(
                        mode: mode,
                        durationMinutes: timer.minutes(for: mode),
                        isSelected: timer.selectedMode == mode
                    ) {
                        guard timer.selectedMode != mode else { return }
                        isEditingDuration = false
                        if timer.isRunning {
                            pendingMode = mode
                        } else {
                            timer.select(mode)
                        }
                    }
                }
            }

            ZStack {
                Circle()
                    .stroke(WeekflowPalette.border.opacity(0.55), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: max(1 - timer.progress, 0.001))
                    .stroke(
                        timer.selectedMode.accentColor,
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.9), value: timer.progress)
                Button {
                    guard !timer.isRunning else { return }
                    withAnimation(.easeInOut(duration: 0.16)) { isEditingDuration.toggle() }
                } label: {
                    Text(timer.formattedRemaining)
                        .font(.system(
                            size: countdownSize * (usesExtendedCountdown ? 0.43 : 0.52),
                            weight: .light
                        ))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, usesExtendedCountdown ? 34 : 20)
                        .foregroundStyle(WeekflowPalette.textPrimary)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help(timer.isRunning ? "专注进行中" : "点击修改时长")

                if isEditingDuration {
                    FocusDurationMenu(
                        minutes: Binding(
                            get: { timer.currentDurationMinutes },
                            set: { timer.updateCurrentDurationMinutes($0) }
                        ),
                        onSelection: {
                            withAnimation(.easeOut(duration: 0.1)) {
                                isEditingDuration = false
                            }
                        }
                    )
                    .offset(y: -135)
                    .zIndex(10)
                }
            }
            .frame(width: 250, height: 250)

            HStack(spacing: 14) {
                FocusControlButton(
                    symbol: timer.isRunning ? "pause.fill" : "play.fill",
                    accessibilityTitle: timer.isRunning ? "暂停专注" : (timer.hasStarted ? "继续专注" : "开始专注"),
                    isPrimary: true,
                    primaryColor: timer.selectedMode.accentColor
                ) {
                    timer.toggle()
                }
                FocusControlButton(
                    symbol: "stop.fill",
                    accessibilityTitle: "停止专注",
                    isPrimary: false,
                    primaryColor: timer.selectedMode.accentColor
                ) {
                    isEditingDuration = false
                    timer.stop()
                }
                .disabled(!timer.hasStarted && !timer.isRunning)
            }
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

private struct FocusControlButton: View {
    let symbol: String
    let accessibilityTitle: String
    let isPrimary: Bool
    let primaryColor: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.white : WeekflowPalette.textPrimary)
                .frame(width: 48, height: 48)
                .background(
                    isPrimary
                        ? primaryColor.opacity(isHovering ? 0.84 : 1)
                        : (isHovering ? WeekflowPalette.surfaceSelected : WeekflowPalette.surfaceHover),
                    in: Circle()
                )
                .overlay(
                    Circle().stroke(isPrimary ? Color.clear : WeekflowPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .contentShape(Circle())
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.14), value: isHovering)
        .help(accessibilityTitle)
        .accessibilityLabel(accessibilityTitle)
    }
}

private struct FocusModeButton: View {
    let mode: FocusMode
    let durationMinutes: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 14, weight: .regular))
                Text(mode.title)
                    .font(.system(size: 13, weight: .medium))
                Text("\(durationMinutes)")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? WeekflowPalette.textPrimary : WeekflowPalette.textMuted)
            }
            .frame(width: 112, height: 36)
            .background(
                isSelected
                    ? mode.accentColor.opacity(0.13)
                    : (isHovering ? WeekflowPalette.surfaceHover : WeekflowPalette.surface),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(
                    isSelected ? mode.accentColor.opacity(0.55) : WeekflowPalette.border,
                    lineWidth: 1
                )
            )
            .foregroundStyle(isSelected ? mode.accentColor : WeekflowPalette.textPrimary)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovering = $0 }
    }
}
