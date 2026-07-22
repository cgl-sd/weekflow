import CoreGraphics
import XCTest
@testable import Weekflow

final class StageTwelveTooltipTests: XCTestCase {
    private let screen = CGRect(x: 100, y: 80, width: 1_000, height: 700)
    private let tooltipSize = CGSize(width: 220, height: 48)

    func testComposerControlsShareOneIconControlAndTooltipGeometry() {
        XCTAssertEqual(WeekflowLayout.composerIconSize, 16)
        XCTAssertEqual(WeekflowLayout.composerControlHeight, 28)
        XCTAssertEqual(WeekflowLayout.composerTooltipHeight, 34)
    }

    func testTooltipIsClampedAtLeftEdge() {
        let placement = FloatingTooltipPositioning.placement(
            anchorFrame: CGRect(x: 101, y: 500, width: 24, height: 24),
            requestedSize: tooltipSize,
            visibleFrame: screen
        )

        XCTAssertEqual(placement.origin.x, screen.minX + FloatingTooltipPositioning.screenInset)
        assertInsideScreen(placement)
    }

    func testTooltipIsClampedAtRightEdge() {
        let placement = FloatingTooltipPositioning.placement(
            anchorFrame: CGRect(x: 1_075, y: 500, width: 24, height: 24),
            requestedSize: tooltipSize,
            visibleFrame: screen
        )

        XCTAssertEqual(
            placement.origin.x + placement.size.width,
            screen.maxX - FloatingTooltipPositioning.screenInset
        )
        assertInsideScreen(placement)
    }

    func testTooltipFlipsAboveAnchorAtBottomEdge() {
        let anchor = CGRect(x: 540, y: 82, width: 24, height: 24)
        let placement = FloatingTooltipPositioning.placement(
            anchorFrame: anchor,
            requestedSize: tooltipSize,
            visibleFrame: screen
        )

        XCTAssertTrue(placement.isAboveAnchor)
        XCTAssertEqual(placement.origin.y, anchor.maxY + FloatingTooltipPositioning.gap)
        assertInsideScreen(placement)
    }

    func testTooltipRemainsBelowAnchorAtTopEdge() {
        let anchor = CGRect(x: 540, y: 750, width: 24, height: 24)
        let placement = FloatingTooltipPositioning.placement(
            anchorFrame: anchor,
            requestedSize: tooltipSize,
            visibleFrame: screen
        )

        XCTAssertFalse(placement.isAboveAnchor)
        XCTAssertEqual(
            placement.origin.y,
            anchor.minY - FloatingTooltipPositioning.gap - tooltipSize.height
        )
        assertInsideScreen(placement)
    }

    func testLongTooltipIsWidthLimitedAndKeptOnScreen() {
        let placement = FloatingTooltipPositioning.placement(
            anchorFrame: CGRect(x: 570, y: 400, width: 24, height: 24),
            requestedSize: CGSize(width: 2_000, height: 120),
            visibleFrame: screen
        )

        XCTAssertEqual(placement.size.width, FloatingTooltipPositioning.maximumWidth)
        assertInsideScreen(placement)
    }

    func testTooltipLargerThanScreenIsConstrainedOnBothAxes() {
        let tinyScreen = CGRect(x: 20, y: 30, width: 180, height: 100)
        let placement = FloatingTooltipPositioning.placement(
            anchorFrame: CGRect(x: 25, y: 35, width: 12, height: 12),
            requestedSize: CGSize(width: 500, height: 400),
            visibleFrame: tinyScreen
        )

        XCTAssertEqual(
            placement.size,
            CGSize(
                width: tinyScreen.width - FloatingTooltipPositioning.screenInset * 2,
                height: tinyScreen.height - FloatingTooltipPositioning.screenInset * 2
            )
        )
        assertInsideScreen(placement, visibleFrame: tinyScreen)
    }

    private func assertInsideScreen(
        _ placement: FloatingTooltipPositioning.Placement,
        visibleFrame: CGRect? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let visibleFrame = visibleFrame ?? screen
        let frame = CGRect(origin: placement.origin, size: placement.size)
        XCTAssertGreaterThanOrEqual(
            frame.minX,
            visibleFrame.minX + FloatingTooltipPositioning.screenInset,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxX,
            visibleFrame.maxX - FloatingTooltipPositioning.screenInset,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            frame.minY,
            visibleFrame.minY + FloatingTooltipPositioning.screenInset,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            frame.maxY,
            visibleFrame.maxY - FloatingTooltipPositioning.screenInset,
            file: file,
            line: line
        )
    }
}
