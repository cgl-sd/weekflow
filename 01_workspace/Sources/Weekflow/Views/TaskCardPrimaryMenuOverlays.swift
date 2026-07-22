import SwiftUI

/// Shared task-card menus used by the home board and daily planning. Keeping
/// the menu surface and anchor calculation here prevents the two screens from
/// drifting into different popover styles or positions.
struct TaskCardDurationMenuOverlay: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    @Bindable var store: WeekflowStore
    let cardFrame: CGRect
    let durationButtonFrame: CGRect?
    let estimatedDurationButtonFrame: CGRect?
    let cardWidth: CGFloat
    let viewportBottom: CGFloat
    let minimumPresentationCardBottom: CGFloat?
    let dismiss: () -> Void

    var body: some View {
        let menuWidth = cardWidth * WeekflowLayout.taskDurationMenuWidthFraction
        let menuTop = cardFrame.maxY - WeekflowLayout.taskAnchoredMenuCardOverlap
        let projectedMenuBottom = WeekflowLayout.taskDurationProjectedMenuBottom(
            cardBottom: cardFrame.maxY,
            minimumPresentationCardBottom: minimumPresentationCardBottom
        )
        let menuCenter = CGPoint(
            x: cardFrame.maxX - WeekflowLayout.taskDurationMenuTrailingInset - menuWidth / 2,
            y: menuTop + WeekflowLayout.taskDurationMenuHeight / 2
        )
        let menuFrame = CGRect(
            x: menuCenter.x - menuWidth / 2,
            y: menuTop,
            width: menuWidth,
            height: WeekflowLayout.taskDurationMenuHeight
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame]
                    + [durationButtonFrame, estimatedDurationButtonFrame].compactMap { $0 },
                // SwiftUI buttons commit on mouse-up. Waiting for that same
                // phase prevents an animated/stale anchor from dismissing on
                // mouse-down and making the button reopen the menu on release.
                monitoredEventMask: .leftMouseUp,
                action: dismiss
            )
            .allowsHitTesting(false)

            ScrollDurationPopover(
                minutes: Binding(
                    get: { entry.task.estimatedMinutes },
                    set: { minutes in
                        var task = entry.task
                        task.estimatedMinutes = minutes
                        store.updateTask(task, goalID: entry.goal.id)
                    }
                ),
                range: 0...240,
                step: 15,
                allowsZero: true,
                title: "预计时间",
                width: menuWidth,
                height: WeekflowLayout.taskDurationMenuHeight
            )
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .boxHoverChrome(
                isHovering: true,
                cornerRadius: 8,
                hoverBorder: WeekflowPalette.border,
                hoverShadowOpacity: 0.15,
                hoverShadowRadius: 2,
                hoverShadowY: 3
            )
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        WeekflowPalette.borderStrong.opacity(0.85),
                        lineWidth: 1,
                        antialiased: true
                    )
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            .position(menuCenter)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topTrailing)))
            .preference(
                key: TaskDurationMenuOverflowPreferenceKey.self,
                value: WeekflowLayout.taskDurationPresentationScrollDistance(
                    menuBottom: projectedMenuBottom,
                    viewportBottom: viewportBottom
                )
            )

            TaskDurationMenuPointer()
                .fill(WeekflowPalette.surface)
                .overlay(
                    TaskDurationMenuPointerOutline().stroke(
                        WeekflowPalette.borderStrong.opacity(0.9),
                        lineWidth: 1
                    )
                )
                .frame(
                    width: WeekflowLayout.taskDurationMenuPointerWidth,
                    height: WeekflowLayout.taskDurationMenuPointerHeight
                )
                .position(
                    x: estimatedDurationButtonFrame?.midX
                        ?? menuFrame.maxX - WeekflowLayout.taskDurationMenuPointerCenterTrailingInset,
                    y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
        .id(entry.task.id)
    }
}

struct TaskCardStartTimeMenuOverlay: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    @Bindable var store: WeekflowStore
    let anchorDate: Date
    let cardFrame: CGRect
    let controlFrame: CGRect
    let viewportWidth: CGFloat
    let scrollerTrackWidth: CGFloat
    let viewportBottom: CGFloat
    var allowsUnset = true
    let dismiss: () -> Void

    var body: some View {
        let maximumTrailingX = WeekflowLayout.homeTaskScrollerTrackLeadingX(
            for: viewportWidth,
            trackWidth: scrollerTrackWidth
        )
        let horizontalBounds = WeekflowLayout.taskAnchoredPopoverHorizontalBounds(
            anchorCenterX: controlFrame.midX,
            menuWidth: WeekflowLayout.taskStartTimeMenuWidth,
            cardMinX: cardFrame.minX,
            maximumTrailingX: maximumTrailingX
        )
        let menuWidth = horizontalBounds.upperBound - horizontalBounds.lowerBound
        let menuTop = controlFrame.maxY + WeekflowLayout.taskDurationMenuPointerHeight + 2
        let menuFrame = CGRect(
            x: horizontalBounds.lowerBound,
            y: menuTop,
            width: menuWidth,
            height: WeekflowLayout.taskStartTimeMenuHeight
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame, controlFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            ScrollClockTimePopover(
                selection: entry.task.startTime,
                anchorDate: entry.task.plannedDate ?? anchorDate,
                allowsUnset: allowsUnset
            ) { selection in
                var task = entry.task
                task.startTime = selection
                store.updateTask(task, goalID: entry.goal.id)
            }
            .frame(width: menuWidth, height: WeekflowLayout.taskStartTimeMenuHeight)
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 6))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 6)
                    .fill(WeekflowPalette.surface)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 6)
                    .strokeBorder(WeekflowPalette.borderStrong.opacity(0.85), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            .position(x: menuFrame.midX, y: menuFrame.midY)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            .preference(
                key: TaskDurationMenuOverflowPreferenceKey.self,
                value: WeekflowLayout.taskAnchoredMenuPresentationScrollDistance(
                    menuBottom: menuFrame.maxY,
                    viewportBottom: viewportBottom,
                    menuHeight: WeekflowLayout.taskStartTimeMenuHeight
                )
            )

            TaskCardMenuPointer(anchorX: controlFrame.midX, menuTop: menuFrame.minY)
        }
        .id(entry.task.id)
    }
}

struct TaskCardChannelMenuOverlay: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    @Bindable var store: WeekflowStore
    let cardFrame: CGRect
    let controlFrame: CGRect
    let viewportWidth: CGFloat
    let scrollerTrackWidth: CGFloat
    let viewportBottom: CGFloat
    let dismiss: () -> Void

    var body: some View {
        let menuHeight = WeekflowLayout.taskChannelPopoverHeight(
            channelCount: store.activeChannels.count
        )
        let maximumTrailingX = WeekflowLayout.homeTaskScrollerTrackLeadingX(
            for: viewportWidth,
            trackWidth: scrollerTrackWidth
        )
        let horizontalBounds = WeekflowLayout.taskAnchoredPopoverHorizontalBounds(
            anchorCenterX: controlFrame.midX,
            menuWidth: WeekflowLayout.taskChannelPopoverWidth,
            cardMinX: cardFrame.minX,
            maximumTrailingX: maximumTrailingX
        )
        let menuWidth = horizontalBounds.upperBound - horizontalBounds.lowerBound
        let menuTop = cardFrame.maxY - WeekflowLayout.taskAnchoredMenuCardOverlap
        let menuFrame = CGRect(
            x: horizontalBounds.lowerBound,
            y: menuTop,
            width: menuWidth,
            height: menuHeight
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame, controlFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            TaskChannelPopover(
                channels: store.activeChannels,
                selectedChannelID: entry.task.channelID,
                select: { channelID in
                    var task = entry.task
                    task.channelID = channelID
                    store.updateTask(task, goalID: entry.goal.id)
                },
                manage: {
                    dismiss()
                    DispatchQueue.main.async {
                        CommandRouter.shared.send(.openChannelSettings)
                    }
                }
            )
            .frame(width: menuWidth, height: menuHeight, alignment: .topLeading)
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WeekflowPalette.surface)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 3)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        WeekflowPalette.borderStrong.opacity(0.85),
                        lineWidth: 1,
                        antialiased: true
                    )
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            .position(x: menuFrame.midX, y: menuFrame.midY)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            .preference(
                key: TaskDurationMenuOverflowPreferenceKey.self,
                value: WeekflowLayout.taskAnchoredMenuPresentationScrollDistance(
                    menuBottom: menuFrame.maxY,
                    viewportBottom: viewportBottom,
                    menuHeight: menuHeight
                )
            )

            TaskCardMenuPointer(anchorX: controlFrame.midX, menuTop: menuFrame.minY)
        }
        .id(entry.task.id)
    }
}

struct TaskCardDateMenuOverlay: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    let anchorDate: Date
    let cardFrame: CGRect
    let dateButtonFrame: CGRect?
    let viewportWidth: CGFloat
    let scrollerTrackWidth: CGFloat
    let showsVerticalScroller: Bool
    let viewportBottom: CGFloat
    let moveToDate: (Date) -> Void
    let dismiss: () -> Void

    var body: some View {
        let scrollerTrackLeadingX = WeekflowLayout.homeTaskScrollerTrackLeadingX(
            for: viewportWidth,
            trackWidth: scrollerTrackWidth
        )
        let horizontalBounds = WeekflowLayout.taskDatePopoverHorizontalBounds(
            cardMinX: cardFrame.minX,
            maximumTrailingX: scrollerTrackLeadingX
        )
        let hidesTrailingBorder = showsVerticalScroller
            && abs(horizontalBounds.upperBound - scrollerTrackLeadingX) < 0.5
        let menuWidth = horizontalBounds.upperBound - horizontalBounds.lowerBound
        let menuTop = cardFrame.maxY - WeekflowLayout.taskAnchoredMenuCardOverlap
        let menuCenter = CGPoint(
            x: horizontalBounds.lowerBound + menuWidth / 2,
            y: menuTop + WeekflowLayout.taskDatePopoverMaximumHeight / 2
        )
        let menuFrame = CGRect(
            x: menuCenter.x - menuWidth / 2,
            y: menuTop,
            width: menuWidth,
            height: WeekflowLayout.taskDatePopoverMaximumHeight
        )
        let calendarButtonCenterX = dateButtonFrame?.midX ?? (
            cardFrame.minX
                + WeekflowLayout.taskCardHorizontalPadding
                + WeekflowLayout.taskCardIconHitTarget
                + WeekflowLayout.taskCardIconSpacing
                + WeekflowLayout.taskCardIconSize / 2
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame] + [dateButtonFrame].compactMap { $0 },
                action: dismiss
            )
            .allowsHitTesting(false)

            TaskDatePopover(
                selectedDate: entry.task.plannedDate ?? anchorDate,
                availableWidth: menuWidth,
                exactWidth: menuWidth,
                moveByDays: { offset in
                    let baseDate = entry.task.plannedDate ?? anchorDate
                    guard let targetDate = SystemBusinessCalendar.current.calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: baseDate
                    ) else { return }
                    moveToDate(targetDate)
                },
                moveToDate: moveToDate
            )
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WeekflowPalette.surface)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 3)
            }
            .overlay {
                TaskDateMenuBorder(
                    cornerRadius: 8,
                    hidesTrailingEdge: hidesTrailingBorder
                )
                .stroke(
                    WeekflowPalette.borderStrong.opacity(0.85),
                    lineWidth: 1,
                    antialiased: true
                )
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            .position(menuCenter)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .topLeading)))
            .preference(
                key: TaskDurationMenuOverflowPreferenceKey.self,
                value: WeekflowLayout.taskDatePresentationScrollDistance(
                    menuBottom: menuFrame.maxY,
                    viewportBottom: viewportBottom
                )
            )

            TaskDurationMenuPointer()
                .fill(WeekflowPalette.surface)
                .overlay(
                    TaskDurationMenuPointerOutline().stroke(
                        WeekflowPalette.borderStrong.opacity(0.9),
                        lineWidth: 1
                    )
                )
                .frame(
                    width: WeekflowLayout.taskDurationMenuPointerWidth,
                    height: WeekflowLayout.taskDurationMenuPointerHeight
                )
                .position(
                    x: calendarButtonCenterX,
                    y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
                )
                .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
                .zIndex(3)
        }
        .id(entry.task.id)
    }
}

struct TaskCardPriorityMenuOverlay: View {
    let entry: (goal: WeeklyGoal, task: WeekTask)
    @Bindable var store: WeekflowStore
    let anchorDate: Date
    let cardFrame: CGRect
    let controlFrame: CGRect
    let viewportWidth: CGFloat
    let scrollerTrackWidth: CGFloat
    let viewportBottom: CGFloat
    let dismiss: () -> Void

    var body: some View {
        let menuHeight = WeekflowLayout.taskPriorityPopoverHeight
        let maximumTrailingX = WeekflowLayout.homeTaskScrollerTrackLeadingX(
            for: viewportWidth,
            trackWidth: scrollerTrackWidth
        )
        let horizontalBounds = WeekflowLayout.taskAnchoredPopoverHorizontalBounds(
            anchorCenterX: controlFrame.midX,
            menuWidth: WeekflowLayout.taskPriorityPopoverWidth,
            cardMinX: cardFrame.minX,
            maximumTrailingX: maximumTrailingX
        )
        let menuWidth = horizontalBounds.upperBound - horizontalBounds.lowerBound
        let menuTop = cardFrame.maxY - WeekflowLayout.taskAnchoredMenuCardOverlap
        let menuFrame = CGRect(
            x: horizontalBounds.lowerBound,
            y: menuTop,
            width: menuWidth,
            height: menuHeight
        )

        ZStack(alignment: .topLeading) {
            WindowOutsideClickMonitor(
                protectedRects: [menuFrame, controlFrame],
                action: dismiss
            )
            .allowsHitTesting(false)

            TaskPriorityPopover(selectedPriority: entry.task.priority) { priority in
                store.setTaskPriority(
                    goalID: entry.goal.id,
                    taskID: entry.task.id,
                    priority: priority,
                    on: anchorDate
                )
            }
            .frame(width: menuWidth, height: menuHeight, alignment: .topLeading)
            .clipShape(WeekflowRoundedRectangle(cornerRadius: 8))
            .background {
                WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WeekflowPalette.surface)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 3)
            }
            .overlay {
                WeekflowRoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        WeekflowPalette.borderStrong.opacity(0.85),
                        lineWidth: 1,
                        antialiased: true
                    )
            }
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)
            .position(x: menuFrame.midX, y: menuFrame.midY)
            .zIndex(2)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            .preference(
                key: TaskDurationMenuOverflowPreferenceKey.self,
                value: WeekflowLayout.taskAnchoredMenuPresentationScrollDistance(
                    menuBottom: menuFrame.maxY,
                    viewportBottom: viewportBottom,
                    menuHeight: menuHeight
                )
            )

            TaskCardMenuPointer(anchorX: controlFrame.midX, menuTop: menuFrame.minY)
        }
        .id(entry.task.id)
    }
}

private struct TaskCardMenuPointer: View {
    let anchorX: CGFloat
    let menuTop: CGFloat

    var body: some View {
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
            .position(
                x: anchorX,
                y: menuTop - WeekflowLayout.taskDurationMenuPointerHeight / 2 + 1
            )
            .shadow(color: .black.opacity(0.12), radius: 1, y: -1)
            .zIndex(3)
    }
}
