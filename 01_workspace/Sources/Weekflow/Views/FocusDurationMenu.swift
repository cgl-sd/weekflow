import SwiftUI

/// Application-owned focus duration menu shared by the full focus scene and
/// the menu-bar window. The bottom pointer is centered on the countdown text.
struct FocusDurationMenu: View {
    @Binding var minutes: Int
    var width: CGFloat = 164
    var height: CGFloat = 210
    var onSelection: () -> Void = {}

    var body: some View {
        VStack(spacing: -1) {
            ScrollDurationPopover(
                minutes: Binding(
                    get: { minutes },
                    set: { value in
                        minutes = value
                        onSelection()
                    }
                ),
                range: FocusTimerService.minimumDurationMinutes...FocusTimerService.maximumDurationMinutes,
                step: FocusTimerService.durationStepMinutes,
                allowsZero: false,
                title: "专注时长",
                width: width,
                height: height
            )
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8)
                    .stroke(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, y: 2)

            TaskDurationMenuPointer()
                .fill(WeekflowPalette.surface)
                .overlay {
                    TaskDurationMenuPointerOutline()
                        .stroke(WeekflowPalette.borderStrong.opacity(0.9), lineWidth: 1)
                }
                .frame(
                    width: WeekflowLayout.taskDurationMenuPointerWidth,
                    height: WeekflowLayout.taskDurationMenuPointerHeight
                )
                .rotationEffect(.degrees(180))
                .zIndex(2)
        }
        .fixedSize()
        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .bottom)))
    }
}
