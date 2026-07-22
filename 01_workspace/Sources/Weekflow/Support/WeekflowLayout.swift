import CoreGraphics

/// Locked dimensions used by both the app shell and visual regression tests.
///
/// Keep these values centralized so a local layout tweak cannot silently change
/// the accepted window, board, or assistant geometry.
enum WeekflowLayout {
    static let windowWidth: CGFloat = 1_080
    static let windowHeight: CGFloat = 700
    static let sidebarWidth: CGFloat = 210
    static let sidebarDividerWidth: CGFloat = 1
    static let assistantRailWidth: CGFloat = 48
    static let assistantPanelWidth: CGFloat = 260
    static let colorPickerPanelWidth: CGFloat = 248
    static let colorPickerPanelHeight: CGFloat = 250
    static let colorPickerFieldHeight: CGFloat = 190
    static let colorPickerHueTrackHeight: CGFloat = 28
    static let scrollbarGutterWidth: CGFloat = 10
    static let boardVisibleDayCount: CGFloat = 3
    static let homeDayColumnSpacing: CGFloat = 24
    static let homeBoardLeadingPadding: CGFloat = 16
    static let homeBoardTrailingPadding: CGFloat = 10
    static let homeRenderedDayOverscan = 1
    static let dayColumnScrollbarGutter = scrollbarGutterWidth
    static let homeTaskScrollbarGutter: CGFloat = 20
    static let taskCardMinimumWidth: CGFloat = 140
    static let taskTimerMinimumWidth: CGFloat = 50
    static let taskTimerComparisonMinimumWidth: CGFloat = 102
    static let taskCardMetadataVisualSize: CGFloat = 9
    static let taskCardIconSize: CGFloat = 11.5
    static let taskPopoverIconSize: CGFloat = 11.5
    static let taskCardIconHitTarget: CGFloat = 25
    static let taskCardPriorityBadgeHeight: CGFloat = 16
    static let taskCardIconSpacing: CGFloat = 2
    static let taskCardTitleFontSize: CGFloat = 13
    static let homeAddTaskFontSize: CGFloat = 13
    static let homeAddTaskHeight: CGFloat = 38
    static let homeDayWeekdayFontSize: CGFloat = 23
    static let homeDayDateFontSize: CGFloat = 16
    static let homeDailyProgressHeight: CGFloat = 9
    static let homeDailyProgressWidthFraction: CGFloat = 0.90
    static let homeDailyProgressVerticalPadding: CGFloat = 3
    static let taskCardChannelFontSize = taskCardMetadataVisualSize
    static let taskCardChannelMaximumWidth: CGFloat = 110
    static let taskCardTimerFontSize = taskCardMetadataVisualSize
    static let taskCardStartTimeFontSize = taskCardMetadataVisualSize
    static let taskCardSubtaskFontSize: CGFloat = 11
    static let taskCardSubtaskRowHeight: CGFloat = 24
    static let taskCardPriorityFontSize = taskCardMetadataVisualSize
    static let taskCardTimerControlWidth: CGFloat = 102
    static let taskCardMetadataHitTargetHeight: CGFloat = 32
    static let taskCardHorizontalPadding: CGFloat = 12
    static let taskCardVerticalPadding: CGFloat = 6
    static let taskCardMinimumHeight: CGFloat = 84
    static let homeTaskCardHeight: CGFloat = 90
    static let homeVisibleTaskCardCapacity = 5
    static let homeTaskCardSpacing: CGFloat = 8
    static let homeTaskListBottomPadding: CGFloat = 0
    static let taskCardTitleTopPadding: CGFloat = 2
    static let taskCardFooterTopPadding: CGFloat = 4
    static let taskCardFooterLeadingInset: CGFloat = 0

    static var collapsedSidebarBoardWidthGain: CGFloat {
        sidebarWidth + sidebarDividerWidth
    }

    static func homeTaskCardHeight(subtaskCount: Int, timerExpanded: Bool = false) -> CGFloat {
        homeTaskCardHeight
            + CGFloat(max(subtaskCount, 0)) * taskCardSubtaskRowHeight
            + (timerExpanded ? taskTimerExpandedAdditionalHeight : 0)
    }
    static let taskTimerInlinePanelHeight: CGFloat = 44
    static let taskTimerControlSize = taskCardIconHitTarget
    static let taskTimerDividerHeight: CGFloat = 1
    static let taskTimerDividerPointerWidth: CGFloat = 12
    static let taskTimerDividerPointerHeight: CGFloat = 6
    static let taskTimerPanelVerticalPadding: CGFloat = 2
    static let taskTimerPanelHorizontalPadding: CGFloat = 6
    static let taskTimerPanelInnerHorizontalPadding: CGFloat = 2
    static let taskTimerColumnWidth: CGFloat = 52
    static let taskDurationMenuHeight: CGFloat = 240
    static let taskStartTimeMenuWidth: CGFloat = 176
    static let taskStartTimeMenuHeight: CGFloat = 244
    static let taskDurationMenuWidthFraction: CGFloat = 0.5
    static let taskDurationMenuTrailingInset: CGFloat = 12
    static let taskDurationMenuPointerWidth: CGFloat = 14
    static let taskDurationMenuPointerHeight: CGFloat = 8
    static let taskAnchoredMenuCardOverlap: CGFloat = 6
    static let taskDurationMenuViewportBottomClearance: CGFloat = 4
    static let taskDurationPresentationAnimationDuration: Double = 0.16
    /// Aligns the pointer tip with the center of the inline panel's estimated-time column.
    static let taskDurationMenuPointerCenterTrailingInset = taskTimerPanelHorizontalPadding
        + taskTimerPanelInnerHorizontalPadding
        + taskTimerColumnWidth / 2
        - taskDurationMenuTrailingInset
    static let taskTimerExpandedAdditionalHeight = taskTimerDividerHeight
        + taskTimerInlinePanelHeight
        + taskTimerPanelVerticalPadding * 2
    static let taskDurationPresentationMaximumShift = taskTimerExpandedAdditionalHeight
        + taskDurationMenuHeight
        + taskDurationMenuViewportBottomClearance
    static let weeklyTaskPoolCardHeight: CGFloat = 74
    static let weeklyAssignedTaskCardMinimumHeight: CGFloat = 70
    static let primaryActionHeight: CGFloat = 44
    static let workCutoffControlHeight: CGFloat = 34
    static let workCutoffPopoverWidth = taskStartTimeMenuWidth
    static let workCutoffPopoverHeight = taskStartTimeMenuHeight
    static let dailyWorkspaceColumnSpacing: CGFloat = 0
    static let dailyWorkspaceColumnTopInset: CGFloat = 18
    static let dailyWorkspaceColumnHorizontalInset: CGFloat = 18
    static let dailyWorkspaceHeaderHeight: CGFloat = 66
    static let dailyWorkspaceContentSpacing: CGFloat = 10
    static let taskAttributePopoverWidth: CGFloat = 196
    static let taskChannelPopoverWidth = taskAttributePopoverWidth
    static let taskChannelPopoverRowHeight: CGFloat = 32
    static let taskChannelPopoverListHeight: CGFloat = 160
    static let taskChannelPopoverMaximumHeight: CGFloat = 246
    static let taskChannelPopoverChromeHeight: CGFloat = 86
    static let taskFilterPopoverWidth: CGFloat = 220
    static let taskFilterPopoverListMaximumHeight: CGFloat = 220
    static let taskFilterPopoverMaximumHeight: CGFloat = 312
    static let dateJumpPopoverWidth: CGFloat = 240
    static let dateJumpPopoverMaximumHeight: CGFloat = 304
    static let workspaceViewPopoverWidth: CGFloat = 200
    static let workspaceViewPopoverMaximumHeight: CGFloat = 211
    static let composerDatePopoverWidth: CGFloat = 220
    static let composerControlHeight: CGFloat = 28
    static let composerIconSize: CGFloat = 16
    static let composerTooltipHeight: CGFloat = 34
    static let composerDatePopoverMaximumHeight: CGFloat = 400
    static let composerDurationPopoverWidth: CGFloat = 120
    static let composerDurationPopoverMaximumHeight: CGFloat = 270
    static let composerChannelPopoverWidth: CGFloat = 235
    static let composerChannelPopoverListMaximumHeight: CGFloat = 200
    static let composerChannelPopoverMaximumHeight: CGFloat = 286
    static let composerGoalPopoverWidth: CGFloat = 235
    static let composerGoalPopoverListMaximumHeight: CGFloat = 220
    static let composerGoalPopoverMaximumHeight: CGFloat = 260
    static let composerPriorityPopoverWidth: CGFloat = 158
    static let composerPriorityPopoverMaximumHeight: CGFloat = 142
    static let taskDatePopoverWidth: CGFloat = 260
    static let taskDatePopoverMinimumWidth: CGFloat = 128
    static let taskDatePopoverCardInset: CGFloat = 2
    static let taskDatePopoverHorizontalOffset: CGFloat = 8
    static let taskDatePopoverMaximumHeight: CGFloat = 326
    static let taskDateMenuViewportBottomClearance = taskDurationMenuViewportBottomClearance
    static let taskPriorityPopoverWidth: CGFloat = 176
    static let taskPriorityPopoverMaximumHeight: CGFloat = 190
    static let taskPriorityPopoverHeaderHeight: CGFloat = 34
    static let taskPriorityPopoverRowHeight: CGFloat = 34
    static let taskPriorityPopoverHeight: CGFloat = 183
    static let taskDetailMinimumWidth: CGFloat = 660
    static let taskDetailMinimumHeight: CGFloat = 590
    static let taskDetailSheetWidth: CGFloat = 700
    static let taskDetailSheetHeight: CGFloat = 650
    static let taskDetailExpandedWidth: CGFloat = 1_000
    static let taskDetailExpandedHeight: CGFloat = 660
    static let taskDetailCornerRadius: CGFloat = 10
    static let taskDetailAttributeMenuWidth: CGFloat = 240
    static let taskDetailChannelMenuWidth: CGFloat = 208
    static let taskDetailPriorityMenuWidth: CGFloat = 188
    static let taskDetailDateMenuWidth: CGFloat = 220
    static let taskDetailCalendarMenuHeight: CGFloat = 244
    static let taskDetailStartTimeControlWidth: CGFloat = 92
    static let taskDetailTimeColumnWidth: CGFloat = 58
    static let taskDetailTimeColumnSpacing: CGFloat = 16
    static let taskDetailTimingWidth = taskDetailStartTimeControlWidth
        + taskDetailTimeColumnSpacing * 2
        + taskDetailTimeColumnWidth * 2

    /// The stable content guide shared by the add row, task cards, and the
    /// trailing overlay scroller.
    static func homeCardContentWidth(for columnWidth: CGFloat) -> CGFloat {
        max(columnWidth, taskCardMinimumWidth)
    }

    /// Exactly three columns share a workspace after the two inter-column
    /// gaps have been removed. The homepage and daily workflows use this same
    /// guide so their primary sections stay aligned at every supported width.
    static func threeColumnWidth(for viewportWidth: CGFloat, columnSpacing: CGFloat) -> CGFloat {
        max(
            (viewportWidth - columnSpacing * (boardVisibleDayCount - 1)) / boardVisibleDayCount,
            150
        )
    }

    static func homeDayColumnWidth(for viewportWidth: CGFloat, columnSpacing: CGFloat) -> CGFloat {
        threeColumnWidth(for: viewportWidth, columnSpacing: columnSpacing)
    }

    /// Keeps the visible three-day window plus a one-day buffer on each side.
    /// Fractional positions briefly render one extra day so dragging never
    /// exposes an uninstantiated column.
    static func homeRenderedDayRange(
        totalDayCount: Int,
        visibleDayIndex: Double
    ) -> Range<Int> {
        guard totalDayCount > 0 else { return 0..<0 }
        let clampedIndex = min(max(visibleDayIndex, 0), Double(totalDayCount - 1))
        let firstVisibleIndex = Int(floor(clampedIndex))
        let lastVisibleIndex = min(
            Int(ceil(clampedIndex)) + Int(boardVisibleDayCount) - 1,
            totalDayCount - 1
        )
        let lowerBound = max(firstVisibleIndex - homeRenderedDayOverscan, 0)
        let upperBound = min(lastVisibleIndex + homeRenderedDayOverscan + 1, totalDayCount)
        return lowerBound..<upperBound
    }

    /// Task cards match the add row until the vertical scroller is needed, at
    /// which point only the scrolling cards give the scroller its own gutter.
    static func homeTaskCardWidth(for columnWidth: CGFloat, showsVerticalScroller: Bool) -> CGFloat {
        let contentWidth = homeCardContentWidth(for: columnWidth)
        guard showsVerticalScroller else { return contentWidth }
        return max(contentWidth - homeTaskScrollbarGutter, taskCardMinimumWidth)
    }

    static func homeShowsVerticalScroller(taskCount: Int) -> Bool {
        taskCount > homeVisibleTaskCardCapacity
    }

    static func homeShowsVerticalScroller(
        taskCount: Int,
        expandedAdditionalHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> Bool {
        guard taskCount > 0 else { return false }
        let baseHeight = CGFloat(taskCount) * homeTaskCardHeight
            + CGFloat(max(taskCount - 1, 0)) * homeTaskCardSpacing
        return homeShowsVerticalScroller(taskCount: taskCount)
            || baseHeight + expandedAdditionalHeight > viewportHeight + 0.5
    }

    static func taskDurationMenuOverflow(remainingCardHeights: [CGFloat]) -> CGFloat {
        taskFloatingMenuOverflow(
            menuHeight: taskDurationMenuHeight,
            bottomClearance: taskDurationMenuViewportBottomClearance,
            remainingCardHeights: remainingCardHeights
        )
    }

    static func taskDateMenuOverflow(remainingCardHeights: [CGFloat]) -> CGFloat {
        taskFloatingMenuOverflow(
            menuHeight: taskDatePopoverMaximumHeight,
            bottomClearance: taskDateMenuViewportBottomClearance,
            remainingCardHeights: remainingCardHeights
        )
    }

    static func taskChannelPopoverHeight(channelCount: Int) -> CGFloat {
        let listHeight = min(
            CGFloat(max(channelCount, 0) + 1) * taskChannelPopoverRowHeight + 8,
            taskChannelPopoverListHeight
        )
        return min(taskChannelPopoverChromeHeight + listHeight, taskChannelPopoverMaximumHeight)
    }

    static func taskAnchoredMenuOverflow(
        menuHeight: CGFloat,
        remainingCardHeights: [CGFloat]
    ) -> CGFloat {
        taskFloatingMenuOverflow(
            menuHeight: menuHeight,
            bottomClearance: taskDateMenuViewportBottomClearance,
            remainingCardHeights: remainingCardHeights
        )
    }

    static func taskFloatingMenuOverflow(
        menuHeight: CGFloat,
        bottomClearance: CGFloat,
        remainingCardHeights: [CGFloat]
    ) -> CGFloat {
        // The scrollable reserve must include the same bottom clearance that
        // the presentation scroll request asks for. Otherwise AppKit clamps
        // the last few cards at the document boundary before the requested
        // clearance can be reached.
        let requiredPresentationHeight = menuHeight + bottomClearance
        guard !remainingCardHeights.isEmpty else {
            return requiredPresentationHeight
        }
        let remainingStackHeight = remainingCardHeights.reduce(0, +)
            + CGFloat(remainingCardHeights.count) * homeTaskCardSpacing
        return max(requiredPresentationHeight - remainingStackHeight, 0)
    }

    /// Returns the complete one-stage scroll distance for any task card.
    /// The result already includes the viewport clearance; callers must not
    /// add the timer panel height or any card-position-specific adjustment.
    static func taskDurationPresentationScrollDistance(
        menuBottom: CGFloat,
        viewportBottom: CGFloat
    ) -> CGFloat {
        let requiredShift = menuBottom
            + taskDurationMenuViewportBottomClearance
            - viewportBottom
        guard requiredShift > 0.5 else { return 0 }
        return min(
            requiredShift,
            taskDurationPresentationMaximumShift
        )
    }

    static func taskDurationProjectedMenuBottom(
        cardBottom: CGFloat,
        minimumPresentationCardBottom: CGFloat?
    ) -> CGFloat {
        max(cardBottom, minimumPresentationCardBottom ?? cardBottom)
            - taskAnchoredMenuCardOverlap
            + taskDurationMenuHeight
    }


    static func taskDatePresentationScrollDistance(
        menuBottom: CGFloat,
        viewportBottom: CGFloat
    ) -> CGFloat {
        taskPresentationScrollDistance(
            presentationBottom: menuBottom,
            viewportBottom: viewportBottom,
            bottomClearance: taskDateMenuViewportBottomClearance,
            maximumShift: taskDatePopoverMaximumHeight + taskDateMenuViewportBottomClearance
        )
    }

    static func taskAnchoredMenuPresentationScrollDistance(
        menuBottom: CGFloat,
        viewportBottom: CGFloat,
        menuHeight: CGFloat
    ) -> CGFloat {
        taskPresentationScrollDistance(
            presentationBottom: menuBottom,
            viewportBottom: viewportBottom,
            bottomClearance: taskDateMenuViewportBottomClearance,
            maximumShift: menuHeight + taskDateMenuViewportBottomClearance
        )
    }

    static func taskTimerPresentationScrollDistance(
        cardBottom: CGFloat,
        viewportBottom: CGFloat
    ) -> CGFloat {
        taskPresentationScrollDistance(
            presentationBottom: cardBottom,
            viewportBottom: viewportBottom,
            bottomClearance: taskDurationMenuViewportBottomClearance,
            maximumShift: taskTimerExpandedAdditionalHeight
                + taskDurationMenuViewportBottomClearance
        )
    }

    private static func taskPresentationScrollDistance(
        presentationBottom: CGFloat,
        viewportBottom: CGFloat,
        bottomClearance: CGFloat,
        maximumShift: CGFloat
    ) -> CGFloat {
        let measuredOverflow = presentationBottom - viewportBottom
        guard measuredOverflow > 0.5 else { return 0 }
        return min(measuredOverflow + bottomClearance, maximumShift)
    }

    static func homeTaskScrollViewportWidth(for columnWidth: CGFloat) -> CGFloat {
        homeCardContentWidth(for: columnWidth)
    }

    /// The leading edge of the complete native scroller track reserved by a
    /// home-day column. This is intentionally different from the narrower
    /// visible thumb/scroller metric.
    static func homeTaskScrollerTrackLeadingX(
        for viewportWidth: CGFloat,
        trackWidth: CGFloat
    ) -> CGFloat {
        max(viewportWidth - min(max(trackWidth, 0), viewportWidth), 0)
    }

    /// The full-month chooser stays centered on the complete task card while
    /// respecting the card's horizontal bounds at every supported column size.
    static func taskDatePopoverWidth(for cardWidth: CGFloat) -> CGFloat {
        min(
            taskDatePopoverWidth,
            max(cardWidth - taskDatePopoverCardInset * 2, taskDatePopoverMinimumWidth)
        )
    }

    /// Keeps the shifted date bubble out of the complete native scroller track.
    static func taskDatePopoverHorizontalBounds(
        cardMinX: CGFloat,
        maximumTrailingX: CGFloat
    ) -> ClosedRange<CGFloat> {
        let leading = cardMinX + taskDatePopoverHorizontalOffset
        return leading...max(leading, maximumTrailingX)
    }

    static func taskAnchoredPopoverHorizontalBounds(
        anchorCenterX: CGFloat,
        menuWidth: CGFloat,
        cardMinX: CGFloat,
        maximumTrailingX: CGFloat
    ) -> ClosedRange<CGFloat> {
        let minimumLeadingX = cardMinX + taskDatePopoverHorizontalOffset
        let resolvedWidth = min(menuWidth, max(maximumTrailingX - minimumLeadingX, 0))
        let maximumLeadingX = max(maximumTrailingX - resolvedWidth, minimumLeadingX)
        let desiredLeadingX = anchorCenterX - resolvedWidth / 2
        let leadingX = min(max(desiredLeadingX, minimumLeadingX), maximumLeadingX)
        return leadingX...(leadingX + resolvedWidth)
    }
}
