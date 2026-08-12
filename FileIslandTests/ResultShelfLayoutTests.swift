import AppKit
import CoreGraphics
import XCTest
@testable import FileIsland

final class ResultShelfLayoutTests: XCTestCase {
    func testSingleItemIsCenteredInViewport() {
        let leading = ResultShelfLayoutMetrics.leadingInset(
            viewportWidth: 560,
            itemCount: 1
        )

        XCTAssertEqual(leading, 224, accuracy: 0.001)
    }

    func testFewItemsRemainCenteredAsAGroup() {
        let leading = ResultShelfLayoutMetrics.leadingInset(
            viewportWidth: 560,
            itemCount: 3
        )

        XCTAssertEqual(leading, 104, accuracy: 0.001)
    }

    func testOverflowingItemsUseCompactLeadingGutter() {
        let leading = ResultShelfLayoutMetrics.leadingInset(
            viewportWidth: 560,
            itemCount: 8
        )

        XCTAssertEqual(leading, ResultShelfLayoutMetrics.minimumHorizontalInset)
    }

    func testEmptyShelfKeepsMinimumGutter() {
        XCTAssertEqual(
            ResultShelfLayoutMetrics.leadingInset(viewportWidth: 560, itemCount: 0),
            ResultShelfLayoutMetrics.minimumHorizontalInset
        )
    }

    func testScrollerAppearsOnlyWhenTheResultGroupExceedsTheViewport() {
        XCTAssertFalse(
            ResultShelfLayoutMetrics.overflows(viewportWidth: 560, itemCount: 4)
        )
        XCTAssertTrue(
            ResultShelfLayoutMetrics.overflows(viewportWidth: 560, itemCount: 5)
        )
    }

    @MainActor
    func testOverflowScrollerUsesAStableCompactNativePresentation() {
        let scrollView = ResultShelfScrollView(
            frame: CGRect(x: 0, y: 0, width: 560, height: 112)
        )

        XCTAssertEqual(scrollView.scrollerStyle, .legacy)
        XCTAssertFalse(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.horizontalScroller?.controlSize, .small)

        scrollView.documentView = NSView(
            frame: CGRect(x: 0, y: 0, width: 900, height: 96)
        )
        scrollView.hasHorizontalScroller = true
        scrollView.layoutSubtreeIfNeeded()

        guard let scroller = scrollView.horizontalScroller else {
            return XCTFail("Expected an installed horizontal scroller")
        }
        XCTAssertFalse(scroller.isHidden)
        XCTAssertGreaterThan(scroller.frame.height, 0)
        XCTAssertGreaterThanOrEqual(scroller.frame.minY, scrollView.bounds.minY)
        XCTAssertLessThanOrEqual(scroller.frame.maxY, scrollView.bounds.maxY)
    }
}
