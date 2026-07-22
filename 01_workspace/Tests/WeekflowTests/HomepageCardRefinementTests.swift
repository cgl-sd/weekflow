import AppKit
import SwiftUI
import Testing
@testable import Weekflow

@Test func homepageRendersOnlyVisibleDaysAndOneDayBuffers() {
    #expect(
        WeekflowLayout.homeRenderedDayRange(totalDayCount: 14, visibleDayIndex: 7)
            == 6..<11
    )
    #expect(
        WeekflowLayout.homeRenderedDayRange(totalDayCount: 14, visibleDayIndex: 7.5)
            == 6..<12
    )
    #expect(
        WeekflowLayout.homeRenderedDayRange(totalDayCount: 14, visibleDayIndex: 0)
            == 0..<4
    )
    #expect(
        WeekflowLayout.homeRenderedDayRange(totalDayCount: 14, visibleDayIndex: 11)
            == 10..<14
    )
}

@Test func collapsedSidebarAddsAColumnWithoutExpandingColumnsAndSubtasksExpandCardsByRows() {
    #expect(
        WeekflowLayout.collapsedSidebarBoardWidthGain
            == WeekflowLayout.sidebarWidth + WeekflowLayout.sidebarDividerWidth
    )
    #expect(
        WeekflowLayout.homeTaskCardHeight(subtaskCount: 0)
            == WeekflowLayout.homeTaskCardHeight
    )
    #expect(
        WeekflowLayout.homeTaskCardHeight(subtaskCount: 3)
            == WeekflowLayout.homeTaskCardHeight
                + WeekflowLayout.taskCardSubtaskRowHeight * 3
    )
    #expect(
        WeekflowLayout.homeTaskCardHeight(subtaskCount: 1, timerExpanded: true)
            == WeekflowLayout.homeTaskCardHeight
                + WeekflowLayout.taskCardSubtaskRowHeight
                + WeekflowLayout.taskTimerExpandedAdditionalHeight
    )
}

@Test func dailyTaskProgressAppearsAfterTheFirstCompletedTask() {
    let planned = WeekTask(title: "待完成", estimatedMinutes: 30, status: .planned)
    let completed = WeekTask(title: "已完成", estimatedMinutes: 30, status: .completed)

    let emptyProgress = DailyTaskProgress(tasks: [])
    #expect(emptyProgress.fraction == 0)
    #expect(!emptyProgress.isVisible)

    let untouchedProgress = DailyTaskProgress(tasks: [planned, planned])
    #expect(untouchedProgress.fraction == 0)
    #expect(!untouchedProgress.isVisible)

    let partialProgress = DailyTaskProgress(tasks: [completed, planned, planned])
    #expect(partialProgress.totalTaskCount == 3)
    #expect(partialProgress.completedTaskCount == 1)
    #expect(partialProgress.fraction == 1.0 / 3.0)
    #expect(partialProgress.isVisible)

    let completeProgress = DailyTaskProgress(tasks: [completed, completed])
    #expect(completeProgress.fraction == 1)
    #expect(completeProgress.isVisible)
}

@MainActor
@Test func homepageCardAndAddRowShareAStableContentGuide() {
    let workspaceWidth = WeekflowLayout.windowWidth
        - WeekflowLayout.sidebarWidth
        - WeekflowLayout.assistantRailWidth
    let acceptedViewportWidth = workspaceWidth
        - WeekflowLayout.homeBoardLeadingPadding
        - WeekflowLayout.homeBoardTrailingPadding
    let acceptedColumnWidth = WeekflowLayout.homeDayColumnWidth(
        for: acceptedViewportWidth,
        columnSpacing: WeekflowLayout.homeDayColumnSpacing
    )
    let contentWidth = WeekflowLayout.homeCardContentWidth(for: acceptedColumnWidth)

    #expect(WeekflowLayout.homeBoardLeadingPadding == 16)
    #expect(WeekflowLayout.homeBoardTrailingPadding == 10)
    #expect(WeekflowLayout.homeDayColumnSpacing == 24)
    #expect(contentWidth == acceptedColumnWidth)
    #expect(WeekflowLayout.homeTaskCardWidth(for: acceptedColumnWidth, showsVerticalScroller: false) == contentWidth)
    #expect(
        WeekflowLayout.homeTaskCardWidth(for: acceptedColumnWidth, showsVerticalScroller: true)
            == contentWidth - WeekflowLayout.homeTaskScrollbarGutter
    )
    #expect(WeekflowLayout.homeTaskScrollbarGutter == 20)
    #expect(WeekflowLayout.homeTaskListBottomPadding == 0)
    #expect(WeekflowLayout.homeVisibleTaskCardCapacity == 5)
    #expect(WeekflowLayout.homeTaskScrollViewportWidth(for: acceptedColumnWidth) == contentWidth)

    #expect(WeekflowLayout.homeTaskCardHeight == 90)
    #expect(WeekflowLayout.homeTaskCardHeight >= WeekflowLayout.taskCardMinimumHeight)
    let fiveCardStackHeight = WeekflowLayout.homeTaskCardHeight
        * CGFloat(WeekflowLayout.homeVisibleTaskCardCapacity)
        + WeekflowLayout.homeTaskCardSpacing
            * CGFloat(WeekflowLayout.homeVisibleTaskCardCapacity - 1)
    #expect(fiveCardStackHeight == 482)
    #expect(!WeekflowLayout.homeShowsVerticalScroller(taskCount: 5))
    #expect(WeekflowLayout.homeShowsVerticalScroller(taskCount: 6))
    #expect(!WeekflowLayout.homeShowsVerticalScroller(
        taskCount: 5,
        expandedAdditionalHeight: 0,
        viewportHeight: fiveCardStackHeight
    ))
    #expect(WeekflowLayout.homeShowsVerticalScroller(
        taskCount: 5,
        expandedAdditionalHeight: WeekflowLayout.taskTimerExpandedAdditionalHeight,
        viewportHeight: fiveCardStackHeight
    ))
    #expect(!WeekflowLayout.homeShowsVerticalScroller(
        taskCount: 3,
        expandedAdditionalHeight: WeekflowLayout.taskTimerExpandedAdditionalHeight
            + WeekflowLayout.taskDurationMenuOverflow(
                remainingCardHeights: [WeekflowLayout.homeTaskCardHeight, WeekflowLayout.homeTaskCardHeight]
            ),
        viewportHeight: 500
    ))
    #expect(WeekflowLayout.homeShowsVerticalScroller(
        taskCount: 3,
        expandedAdditionalHeight: WeekflowLayout.taskTimerExpandedAdditionalHeight
            + WeekflowLayout.taskDurationMenuOverflow(remainingCardHeights: []),
        viewportHeight: 500
    ))
    #expect(WeekflowLayout.taskDurationMenuOverflow(
        remainingCardHeights: [WeekflowLayout.homeTaskCardHeight, WeekflowLayout.homeTaskCardHeight]
    ) == 48)
    #expect(WeekflowLayout.taskDurationMenuOverflow(remainingCardHeights: [])
        == WeekflowLayout.taskDurationMenuHeight
            + WeekflowLayout.taskDurationMenuViewportBottomClearance)
    #expect(WeekflowLayout.taskDurationMenuOverflow(
        remainingCardHeights: Array(repeating: WeekflowLayout.homeTaskCardHeight, count: 3)
    ) == 0)
    #expect(WeekflowLayout.taskDurationPresentationScrollDistance(
        menuBottom: 949,
        viewportBottom: 1_000
    ) == 0)
    #expect(WeekflowLayout.taskDurationPresentationScrollDistance(
        menuBottom: 997,
        viewportBottom: 1_000
    ) == 1)
    #expect(WeekflowLayout.taskDurationPresentationScrollDistance(
        menuBottom: 996,
        viewportBottom: 1_000
    ) == 0)
    #expect(WeekflowLayout.taskDurationProjectedMenuBottom(
        cardBottom: 500,
        minimumPresentationCardBottom: nil
    ) == 500
        - WeekflowLayout.taskAnchoredMenuCardOverlap
        + WeekflowLayout.taskDurationMenuHeight)
    #expect(WeekflowLayout.taskDurationProjectedMenuBottom(
        cardBottom: 500,
        minimumPresentationCardBottom: 549
    ) == 549
        - WeekflowLayout.taskAnchoredMenuCardOverlap
        + WeekflowLayout.taskDurationMenuHeight)
    #expect(WeekflowLayout.taskDurationPresentationScrollDistance(
        menuBottom: 1_001,
        viewportBottom: 1_000
    ) == 1 + WeekflowLayout.taskDurationMenuViewportBottomClearance)
    #expect(WeekflowLayout.taskDurationPresentationScrollDistance(
        menuBottom: 1_120,
        viewportBottom: 1_000
    ) == 120 + WeekflowLayout.taskDurationMenuViewportBottomClearance)
    #expect(abs(
        WeekflowLayout.taskDurationPresentationScrollDistance(
            menuBottom: 1_000.4,
            viewportBottom: 1_000
        ) - (0.4 + WeekflowLayout.taskDurationMenuViewportBottomClearance)
    ) < 0.001)
    #expect(WeekflowLayout.taskDurationPresentationScrollDistance(
        menuBottom: 1_500,
        viewportBottom: 1_000
    ) == WeekflowLayout.taskDurationPresentationMaximumShift)
    #expect(WeekflowLayout.taskDateMenuOverflow(remainingCardHeights: [])
        == WeekflowLayout.taskDatePopoverMaximumHeight
            + WeekflowLayout.taskDateMenuViewportBottomClearance)
    #expect(WeekflowLayout.taskDateMenuOverflow(
        remainingCardHeights: [WeekflowLayout.homeTaskCardHeight, WeekflowLayout.homeTaskCardHeight]
    ) == 134)
    #expect(WeekflowLayout.taskDatePresentationScrollDistance(
        menuBottom: 1_500,
        viewportBottom: 1_000
    ) == WeekflowLayout.taskDatePopoverMaximumHeight
        + WeekflowLayout.taskDateMenuViewportBottomClearance)
    #expect(WeekflowLayout.taskTimerPresentationScrollDistance(
        cardBottom: 1_001,
        viewportBottom: 1_000
    ) == 1 + WeekflowLayout.taskDurationMenuViewportBottomClearance)
    #expect(WeekflowLayout.taskTimerPresentationScrollDistance(
        cardBottom: 1_500,
        viewportBottom: 1_000
    ) == WeekflowLayout.taskTimerExpandedAdditionalHeight
        + WeekflowLayout.taskDurationMenuViewportBottomClearance)
    #expect(
        WeekflowLayout.homeTaskCardWidth(
            for: 292,
            showsVerticalScroller: true
        ) == 292 - WeekflowLayout.homeTaskScrollbarGutter
    )
    let viewportWidth: CGFloat = 925
    let columnSpacing: CGFloat = 24
    let columnWidth = WeekflowLayout.homeDayColumnWidth(
        for: viewportWidth,
        columnSpacing: columnSpacing
    )
    #expect(abs(columnWidth * 3 + columnSpacing * 2 - viewportWidth) < 0.001)
    #expect(contentWidth >= WeekflowLayout.taskCardMinimumWidth)
    #expect(WeekflowLayout.taskCardMetadataVisualSize == 9)
    #expect(WeekflowLayout.taskCardIconSize == 11.5)
    #expect(WeekflowLayout.taskCardIconSize > WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskPopoverIconSize == 11.5)
    #expect(WeekflowLayout.taskCardIconHitTarget == 25)
    #expect(WeekflowLayout.taskCardPriorityBadgeHeight == 16)
    #expect(WeekflowLayout.taskCardIconSpacing == 2)
    #expect(WeekflowLayout.homeAddTaskHeight == 38)
    #expect(WeekflowLayout.homeDayWeekdayFontSize == 23)
    #expect(WeekflowLayout.homeDayDateFontSize == 16)
    #expect(WeekflowLayout.taskCardTitleFontSize == WeekflowLayout.homeAddTaskFontSize)
    #expect(WeekflowLayout.taskCardTitleFontSize == 13)
    #expect(WeekflowLayout.taskCardStartTimeFontSize == WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.taskCardSubtaskFontSize == 11)
    #expect(WeekflowLayout.taskCardPriorityFontSize == WeekflowLayout.taskCardMetadataVisualSize)
    #expect(WeekflowLayout.homeDailyProgressHeight == 9)
    #expect(WeekflowLayout.homeDailyProgressWidthFraction == 0.90)
    #expect(WeekflowLayout.homeDailyProgressVerticalPadding == 3)
    #expect(WeekflowLayout.taskCardMinimumHeight == 84)
    #expect(WeekflowLayout.taskCardTitleTopPadding == 2)
    #expect(WeekflowLayout.taskCardFooterTopPadding == 4)
    #expect(WeekflowLayout.taskCardFooterLeadingInset == 0)
    #expect(WeekflowLayout.taskCardTimerControlWidth == 102)
    #expect(WeekflowLayout.taskDurationMenuWidthFraction == 0.5)
    #expect(WeekflowLayout.taskDurationMenuTrailingInset == 12)
    #expect(WeekflowLayout.taskTimerInlinePanelHeight == 44)
    #expect(WeekflowLayout.taskTimerDividerPointerWidth == 12)
    #expect(WeekflowLayout.taskTimerDividerPointerHeight == 6)
    #expect(WeekflowLayout.taskTimerColumnWidth == 52)
    #expect(WeekflowLayout.taskDurationPresentationAnimationDuration == 0.16)
    #expect(WeekflowLayout.taskDurationMenuViewportBottomClearance == 4)
    #expect(WeekflowLayout.taskTimerPanelHorizontalPadding < WeekflowLayout.taskCardHorizontalPadding)
    #expect(
        WeekflowLayout.taskDurationMenuPointerCenterTrailingInset == 22
    )

    let scrollerTrackLeadingX = WeekflowLayout.homeTaskScrollerTrackLeadingX(
        for: 240,
        trackWidth: 15
    )
    #expect(scrollerTrackLeadingX == 225)

    let dateBoundsWithoutScroller = WeekflowLayout.taskDatePopoverHorizontalBounds(
        cardMinX: 0,
        maximumTrailingX: scrollerTrackLeadingX
    )
    #expect(dateBoundsWithoutScroller.lowerBound == 8)
    #expect(dateBoundsWithoutScroller.upperBound == 225)

    let dateBoundsWithScroller = WeekflowLayout.taskDatePopoverHorizontalBounds(
        cardMinX: 0,
        maximumTrailingX: scrollerTrackLeadingX
    )
    #expect(dateBoundsWithScroller.lowerBound == 8)
    #expect(dateBoundsWithScroller.upperBound == 225)
    #expect(dateBoundsWithoutScroller == dateBoundsWithScroller)

    let leftAnchoredBounds = WeekflowLayout.taskAnchoredPopoverHorizontalBounds(
        anchorCenterX: 42,
        menuWidth: WeekflowLayout.taskChannelPopoverWidth,
        cardMinX: 0,
        maximumTrailingX: scrollerTrackLeadingX
    )
    #expect(leftAnchoredBounds.lowerBound == 8)
    #expect(leftAnchoredBounds.upperBound == 204)

    let rightAnchoredBounds = WeekflowLayout.taskAnchoredPopoverHorizontalBounds(
        anchorCenterX: 210,
        menuWidth: WeekflowLayout.taskPriorityPopoverWidth,
        cardMinX: 0,
        maximumTrailingX: scrollerTrackLeadingX
    )
    #expect(rightAnchoredBounds.lowerBound == 49)
    #expect(rightAnchoredBounds.upperBound == 225)
    #expect(WeekflowLayout.taskChannelPopoverHeight(channelCount: 0) == 126)
    #expect(WeekflowLayout.taskChannelPopoverHeight(channelCount: 10) == 246)
    #expect(WeekflowLayout.taskPriorityPopoverHeaderHeight == 34)
    #expect(WeekflowLayout.taskPriorityPopoverRowHeight == 34)
    #expect(WeekflowLayout.taskPriorityPopoverHeight == 183)
}

@Test func homepageDatePopoverRestoresAFullMonthWithinTheTaskCard() {
    for cardWidth in [WeekflowLayout.taskCardMinimumWidth, 174, 226] {
        let popoverWidth = WeekflowLayout.taskDatePopoverWidth(for: cardWidth)
        #expect(popoverWidth + WeekflowLayout.taskDatePopoverCardInset * 2 <= cardWidth)
        #expect(popoverWidth <= WeekflowLayout.taskDatePopoverWidth)
    }
    #expect(WeekflowLayout.taskDatePopoverWidth == 260)
    #expect(WeekflowLayout.taskDatePopoverCardInset == 2)
    #expect(WeekflowLayout.taskDatePopoverMaximumHeight == 326)
}

@MainActor
@Test func homepageDatePopoverRendersQuickMovesAndAFullMonthAtTheAcceptedSize() {
    let cardWidth: CGFloat = 174
    let popover = TaskDatePopover(
        selectedDate: .now,
        availableWidth: cardWidth,
        moveByDays: { _ in },
        moveToDate: { _ in }
    )
    let host = NSHostingView(rootView: popover)
    let size = host.fittingSize

    #expect(size.width == WeekflowLayout.taskDatePopoverWidth(for: cardWidth))
    #expect(size.width <= cardWidth)
    #expect(size.height == WeekflowLayout.taskDatePopoverMaximumHeight)
}

@MainActor
@Test func pointingHandCursorRegionDoesNotInterceptTaskCardClicks() {
    let cursorRegion = PointingHandCursorView(
        frame: CGRect(x: 0, y: 0, width: 120, height: 80)
    )
    #expect(cursorRegion.hitTest(CGPoint(x: 40, y: 30)) == nil)
    #expect(PointingHandCursorView.trackingOptions.contains(.mouseMoved))
    #expect(PointingHandCursorView.trackingOptions.contains(.mouseEnteredAndExited))
    #expect(PointingHandCursorView.trackingOptions.contains(.inVisibleRect))
    #expect(PointingHandCursorView.trackingOptions.contains(.activeInKeyWindow))
}

@MainActor
@Test func stablePointingHandHoverRegionOwnsHoverAndCursorWithoutInterceptingClicks() {
    var hoverValues: [Bool] = []
    let cursorRegion = StablePointingHandHoverView { hoverValues.append($0) }
    cursorRegion.frame = CGRect(x: 0, y: 0, width: 120, height: 40)

    #expect(cursorRegion.hitTest(CGPoint(x: 20, y: 20)) == nil)
    #expect(StablePointingHandHoverView.trackingOptions.contains(.mouseEnteredAndExited))
    #expect(StablePointingHandHoverView.trackingOptions.contains(.mouseMoved))
    #expect(StablePointingHandHoverView.trackingOptions.contains(.cursorUpdate))
    #expect(StablePointingHandHoverView.trackingOptions.contains(.inVisibleRect))
    #expect(StablePointingHandHoverView.trackingOptions.contains(.activeInKeyWindow))

    let pointerEvent = NSEvent.mouseEvent(
        with: .mouseMoved,
        location: CGPoint(x: 20, y: 20),
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 0,
        pressure: 0
    )!
    let previousCursor = NSCursor.current
    defer { previousCursor.set() }

    cursorRegion.mouseEntered(with: pointerEvent)
    #expect(hoverValues == [true])
    if #unavailable(macOS 15.0) {
        #expect(NSCursor.current == .pointingHand)
    }
    cursorRegion.mouseExited(with: pointerEvent)
    #expect(hoverValues == [true, false])
}

@MainActor
@Test func sidebarRowMountsOneFullSizeStableHoverRegion() {
    let host = NSHostingView(
        rootView: SidebarRow(item: .home, selection: .constant(.focus))
    )
    host.frame = CGRect(x: 0, y: 0, width: 180, height: 32)
    host.layoutSubtreeIfNeeded()

    let hoverRegions = descendantViews(of: host).compactMap { view in
        view as? StablePointingHandHoverView
    }
    #expect(hoverRegions.count == 1)
    #expect(hoverRegions.first?.bounds.isEmpty == false)
    #expect(hoverRegions.first?.bounds.width == host.bounds.width)
    #expect((hoverRegions.first?.bounds.height ?? 0) >= 28)
}

@MainActor
@Test func everyWeekflowButtonInstallsTheStablePointingHandRegion() {
    let host = NSHostingView(rootView: Weekflow.Button("测试按钮") {})
    host.frame = CGRect(x: 0, y: 0, width: 120, height: 40)
    host.layoutSubtreeIfNeeded()

    let cursorRegions = descendantViews(of: host).compactMap { view in
        view as? PointingHandCursorView
    }
    if #available(macOS 15.0, *) {
        #expect(cursorRegions.isEmpty)
    } else {
        #expect(cursorRegions.count == 1)
        #expect(cursorRegions.first?.bounds.isEmpty == false)
        #expect(cursorRegions.first?.hitTest(CGPoint(x: 10, y: 10)) == nil)
    }
}

@MainActor
@Test func continuousPointingHandSurfaceSuppressesNestedCursorRegions() {
    let host = NSHostingView(
        rootView: VStack {
            Weekflow.Button("按钮一") {}
            Weekflow.Button("按钮二") {}
        }
        .pointingHandCursor()
    )
    host.frame = CGRect(x: 0, y: 0, width: 160, height: 100)
    host.layoutSubtreeIfNeeded()

    let cursorRegions = descendantViews(of: host).compactMap { view in
        view as? PointingHandCursorView
    }
    if #available(macOS 15.0, *) {
        #expect(cursorRegions.isEmpty)
    } else {
        #expect(cursorRegions.count == 1)
        #expect(cursorRegions.first?.bounds.isEmpty == false)
    }
}

@MainActor
@Test func sidebarTaskCardAndAddTaskEachOwnExactlyOneCursorRegion() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowCursorOwnership-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = WeekflowStore.testing(storage: LocalStorage(baseDirectory: folder))
    let entry = try #require(store.todayTasks.first)

    let expectedLegacyRegionCount = if #available(macOS 15.0, *) { 0 } else { 1 }

    #expect(pointingHandRegionCount(
        in: SidebarRow(item: .home, selection: .constant(.focus)),
        size: CGSize(width: 210, height: 32)
    ) == expectedLegacyRegionCount)
    #expect(pointingHandRegionCount(
        in: HomeAddTaskButton(action: {}),
        size: CGSize(width: 240, height: WeekflowLayout.homeAddTaskHeight)
    ) == expectedLegacyRegionCount)
    #expect(pointingHandRegionCount(
        in: SunsamaTaskCard(entry: entry, store: store),
        size: CGSize(width: 240, height: WeekflowLayout.taskCardMinimumHeight)
    ) == expectedLegacyRegionCount)
}

@MainActor
@Test func pointingHandRegionUsesWindowScreenCoordinatesForFinalCursorResolution() {
    guard #unavailable(macOS 15.0) else { return }

    let host = NSHostingView(
        rootView: Color.clear
            .frame(width: 180, height: 90)
            .pointingHandCursor(coversDescendants: true)
    )
    let window = NSWindow(
        contentRect: CGRect(x: 240, y: 180, width: 180, height: 90),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    host.frame = window.contentView?.bounds ?? .zero
    host.layoutSubtreeIfNeeded()

    let cursorRegion = descendantViews(of: host)
        .compactMap { $0 as? PointingHandCursorView }
        .first
    let localCenter = CGPoint(
        x: cursorRegion?.bounds.midX ?? 0,
        y: cursorRegion?.bounds.midY ?? 0
    )
    let windowCenter = cursorRegion?.convert(localCenter, to: nil) ?? .zero
    let screenCenter = window.convertPoint(toScreen: windowCenter)

    #expect(cursorRegion != nil)
    #expect(cursorRegion?.containsScreenPoint(screenCenter) == true)
    #expect(cursorRegion?.containsScreenPoint(
        CGPoint(x: screenCenter.x + 500, y: screenCenter.y + 500)
    ) == false)
}

@MainActor
@Test func pointingHandWindowOwnershipChangesOnlyAtInteractiveBoundaries() {
    let firstWindow = CursorRectTrackingWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let secondWindow = CursorRectTrackingWindow(
        contentRect: CGRect(x: 220, y: 0, width: 200, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let controller = PointingHandCursorWindowController()

    controller.update(matchingWindow: firstWindow)
    controller.update(matchingWindow: firstWindow)
    #expect(firstWindow.disableCursorRectsCallCount == 1)
    #expect(firstWindow.enableCursorRectsCallCount == 0)

    controller.update(matchingWindow: secondWindow)
    #expect(firstWindow.enableCursorRectsCallCount == 1)
    #expect(secondWindow.disableCursorRectsCallCount == 1)

    controller.update(matchingWindow: nil)
    #expect(secondWindow.enableCursorRectsCallCount == 1)
    #expect(controller.protectedWindow == nil)
}

@MainActor
private final class CursorRectTrackingWindow: NSWindow {
    private(set) var disableCursorRectsCallCount = 0
    private(set) var enableCursorRectsCallCount = 0

    override func disableCursorRects() {
        disableCursorRectsCallCount += 1
        super.disableCursorRects()
    }

    override func enableCursorRects() {
        enableCursorRectsCallCount += 1
        super.enableCursorRects()
    }
}

@MainActor
private func descendantViews(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendantViews)
}

@MainActor
private func pointingHandRegionCount<V: View>(in view: V, size: CGSize) -> Int {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    return descendantViews(of: host).compactMap { $0 as? PointingHandCursorView }.count
}

@MainActor
@Test func taskCardPresentationToggleAndOutsideClickRulesRemainStable() {
    #expect(TaskCardPresentationRules.shouldPresentAfterToggle(isCurrentlyPresented: false))
    #expect(!TaskCardPresentationRules.shouldPresentAfterToggle(isCurrentlyPresented: true))
    #expect(TaskCardPresentationRules.shouldPresentDurationAfterToggle(
        isTimerExpanded: false,
        isMenuPresented: false
    ))
    #expect(!TaskCardPresentationRules.shouldPresentDurationAfterToggle(
        isTimerExpanded: true,
        isMenuPresented: false
    ))
    #expect(!TaskCardPresentationRules.shouldPresentDurationAfterToggle(
        isTimerExpanded: false,
        isMenuPresented: true
    ))
    // Menu triggers are SwiftUI buttons, so the shared outside-click monitor
    // must settle on mouse-up as well. Otherwise a quick second click can
    // dismiss on press and reopen the same menu on release.
    #expect(OutsideClickProbeView.monitoredEventMask == .leftMouseUp)
    #expect(TaskCardPresentationRules.shouldLockPersistentPriorityBadge(
        menuIsCurrentlyPresented: false,
        priorityShowsPersistently: true,
        expandedControlsAreVisible: false
    ))
    #expect(!TaskCardPresentationRules.shouldLockPersistentPriorityBadge(
        menuIsCurrentlyPresented: false,
        priorityShowsPersistently: false,
        expandedControlsAreVisible: false
    ))
    #expect(!TaskCardPresentationRules.shouldLockPersistentPriorityBadge(
        menuIsCurrentlyPresented: false,
        priorityShowsPersistently: true,
        expandedControlsAreVisible: true
    ))

    let protectedRect = CGRect(x: 20, y: 30, width: 120, height: 80)
    #expect(!OutsideClickProbeView.shouldDismiss(
        clickAt: CGPoint(x: 40, y: 50),
        protectedRect: protectedRect
    ))
    #expect(OutsideClickProbeView.shouldDismiss(
        clickAt: CGPoint(x: 10, y: 50),
        protectedRect: protectedRect
    ))
    #expect(!OutsideClickProbeView.shouldDismiss(
        clickAt: CGPoint(x: 180, y: 50),
        protectedRects: [
            protectedRect,
            CGRect(x: 160, y: 30, width: 80, height: 40)
        ]
    ))
    #expect(!OutsideClickProbeView.shouldDismiss(
        mouseDownBeganInsideProtectedRect: true,
        mouseUpAt: CGPoint(x: 10, y: 50),
        protectedRects: [protectedRect]
    ))
    #expect(!OutsideClickProbeView.shouldDismiss(
        mouseDownBeganInsideProtectedRect: false,
        mouseUpAt: CGPoint(x: 40, y: 50),
        protectedRects: [protectedRect]
    ))
    #expect(OutsideClickProbeView.shouldDismiss(
        mouseDownBeganInsideProtectedRect: false,
        mouseUpAt: CGPoint(x: 10, y: 50),
        protectedRects: [protectedRect]
    ))

    let mouseUpMonitor = WindowOutsideClickMonitor(
        protectedRect: protectedRect,
        monitoredEventMask: .leftMouseUp,
        action: {}
    )
    let mouseUpMonitorHost = NSHostingView(
        rootView: mouseUpMonitor.frame(width: 320, height: 240)
    )
    mouseUpMonitorHost.frame = CGRect(x: 0, y: 0, width: 320, height: 240)
    mouseUpMonitorHost.layoutSubtreeIfNeeded()
    let mouseUpProbe = descendantViews(of: mouseUpMonitorHost)
        .compactMap { $0 as? OutsideClickProbeView }
        .first
    #expect(mouseUpProbe?.monitoredEventMask == .leftMouseUp)
}

@Test func homepageChannelPresentationUsesCompactMetricsAndCanFitAFullLabel() {
    #expect(WeekflowLayout.taskChannelPopoverWidth == 196)
    #expect(WeekflowLayout.taskPriorityPopoverWidth == 176)
    #expect(WeekflowLayout.taskPriorityPopoverWidth < WeekflowLayout.taskChannelPopoverWidth)
    #expect(WeekflowLayout.taskDatePopoverWidth > WeekflowLayout.taskChannelPopoverWidth)
    #expect(WeekflowLayout.taskChannelPopoverRowHeight == 32)
    #expect(WeekflowLayout.taskChannelPopoverListHeight == 160)

    let representativeLabel = "跨团队研究成果汇报" as NSString
    let naturalWidth = representativeLabel.size(withAttributes: [
        .font: NSFont.systemFont(ofSize: WeekflowLayout.taskCardChannelFontSize, weight: .regular)
    ]).width
    #expect(naturalWidth * 0.65 <= WeekflowLayout.taskCardChannelMaximumWidth)
}

@MainActor
@Test func homepageManyTaskColumnAndCompactChannelPopoverRenderAtAcceptedSizes() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowHomepageRefinement-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 12)))
    let fixture = WeekflowDevelopmentFixture.stageOne(referenceDate: sunday, calendar: calendar)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: fixture
    )
    let boardWidth = WeekflowLayout.windowWidth
        - WeekflowLayout.sidebarWidth
        - WeekflowLayout.assistantRailWidth
    let columnWidth = WeekflowLayout.homeDayColumnWidth(
        for: boardWidth
            - WeekflowLayout.homeBoardLeadingPadding
            - WeekflowLayout.homeBoardTrailingPadding,
        columnSpacing: WeekflowLayout.homeDayColumnSpacing
    )
    let board = HomeBoardView(
        store: store,
        visibleDayIndex: .constant(7),
        selectedChannelID: "all",
        addTaskOnDate: { _ in },
        openTask: { _ in },
        showCalendar: {},
        referenceDate: sunday
    )
    .frame(width: boardWidth, height: 676, alignment: .topLeading)
    .background(WeekflowPalette.appBackground)

    let boardHost = NSHostingView(rootView: board)
    boardHost.frame = NSRect(x: 0, y: 0, width: boardWidth, height: 676)
    let boardWindow = makeSnapshotWindow(for: boardHost)
    boardHost.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    boardHost.layoutSubtreeIfNeeded()
    #expect(boardHost.frame.size == NSSize(width: boardWidth, height: 676))
    let taskScrollViews = descendantScrollViews(in: boardHost).filter(\.hasVerticalScroller)
    #expect(!taskScrollViews.isEmpty)
    for scrollView in taskScrollViews {
        #expect(scrollView.contentInsets.top == 0)
        #expect(scrollView.contentInsets.left == 0)
        #expect(scrollView.contentInsets.bottom == 0)
        #expect(scrollView.contentInsets.right == 0)
        #expect(scrollView.scrollerInsets.top == 0)
        #expect(scrollView.scrollerInsets.left == 0)
        #expect(scrollView.scrollerInsets.bottom == 0)
        #expect(scrollView.scrollerInsets.right == 0)
        #expect(scrollView.scrollerStyle == .legacy)
        #expect(!scrollView.autohidesScrollers)
        let scroller = try #require(scrollView.verticalScroller)
        #expect(!scroller.isHidden)
        #expect(abs(scroller.frame.maxX - scrollView.bounds.minX - columnWidth) < 0.5)
        #expect(scroller.frame.maxX > scrollView.bounds.maxX)
        #expect(type(of: scroller) == NSScroller.self)
    }
    try writeHomepageViewSnapshotIfRequested(boardHost, name: "首页卡片对齐与滚动稳定")

    let popover = TaskChannelPopover(
        channels: store.channels,
        selectedChannelID: "research",
        select: { _ in },
        manage: {}
    )
    let popoverHost = NSHostingView(rootView: popover)
    let popoverSize = popoverHost.fittingSize
    popoverHost.frame = NSRect(origin: .zero, size: popoverSize)
    let popoverWindow = makeSnapshotWindow(for: popoverHost)
    popoverHost.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    popoverHost.layoutSubtreeIfNeeded()
    #expect(popoverHost.frame.width == WeekflowLayout.taskChannelPopoverWidth)
    #expect(popoverHost.frame.height <= 250)
    try writeHomepageViewSnapshotIfRequested(popoverHost, name: "Channel紧凑弹层")

    _ = boardWindow
    _ = popoverWindow
}

@MainActor
@Test func homepageExactlyFiveTasksDoesNotInstallAVerticalScroller() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("WeekflowHomepageFiveCards-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let referenceDate = Calendar.current.startOfDay(for: .now)
    let store = WeekflowStore(
        storage: LocalStorage(baseDirectory: folder),
        developmentFixture: .regression(referenceDate: referenceDate)
    )
    let boardWidth = WeekflowLayout.windowWidth
        - WeekflowLayout.sidebarWidth
        - WeekflowLayout.assistantRailWidth
    let board = HomeBoardView(
        store: store,
        visibleDayIndex: .constant(7),
        selectedChannelID: "all",
        addTaskOnDate: { _ in },
        openTask: { _ in },
        showCalendar: {},
        referenceDate: referenceDate
    )
    .frame(width: boardWidth, height: 676, alignment: .topLeading)
    let host = NSHostingView(rootView: board)
    host.frame = NSRect(x: 0, y: 0, width: boardWidth, height: 676)
    let window = makeSnapshotWindow(for: host)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    host.layoutSubtreeIfNeeded()

    let scrollViews = descendantScrollViews(in: host)
    #expect(!scrollViews.isEmpty)
    #expect(scrollViews.allSatisfy { !$0.hasVerticalScroller })
    #expect(scrollViews.allSatisfy { scrollView in
        guard let documentView = scrollView.documentView else { return true }
        return documentView.frame.height <= scrollView.contentSize.height + 0.5
    })
    _ = window
}

@MainActor
private func makeSnapshotWindow(for view: NSView) -> NSWindow {
    let window = NSWindow(
        contentRect: view.frame,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    return window
}

@MainActor
private func writeHomepageViewSnapshotIfRequested(_ view: NSView, name: String) throws {
    guard let outputPath = ProcessInfo.processInfo.environment["WEEKFLOW_SNAPSHOT_DIR"] else { return }
    let folder = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw HomepageSnapshotError.encodingFailed
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw HomepageSnapshotError.encodingFailed
    }
    try png.write(to: folder.appendingPathComponent("\(name).png"), options: .atomic)
}

private enum HomepageSnapshotError: Error {
    case encodingFailed
}

@MainActor
private func descendantScrollViews(in view: NSView) -> [NSScrollView] {
    var result: [NSScrollView] = []
    if let scrollView = view as? NSScrollView {
        result.append(scrollView)
    }
    for subview in view.subviews {
        result.append(contentsOf: descendantScrollViews(in: subview))
    }
    return result
}
