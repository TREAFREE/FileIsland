import CoreGraphics
import XCTest
@testable import FileIsland

final class IslandLayoutTests: XCTestCase {
    func testExpandedFramePreservesHorizontalCenterOnNegativeOriginScreen() {
        let geometry = makeGeometry(
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        )

        let compact = IslandLayout.frame(in: geometry, mode: .compact)
        let expanded = IslandLayout.frame(in: geometry, mode: .expanded)

        XCTAssertEqual(compact.midX, geometry.frame.midX, accuracy: 0.001)
        XCTAssertEqual(expanded.midX, geometry.frame.midX, accuracy: 0.001)
        XCTAssertEqual(compact.midX, expanded.midX, accuracy: 0.001)
    }

    func testFrameUsesAvailableTopEdgeAndRemainsInsideScreen() {
        let geometry = makeGeometry(
            frame: CGRect(x: 120, y: -900, width: 1440, height: 900)
        )

        let frame = IslandLayout.frame(in: geometry, mode: .expanded, topGap: 10)

        XCTAssertEqual(frame.maxY, geometry.visibleFrame.maxY - 10, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(frame.minX, geometry.visibleFrame.minX)
        XCTAssertLessThanOrEqual(frame.maxX, geometry.visibleFrame.maxX)
        XCTAssertGreaterThanOrEqual(frame.minY, geometry.visibleFrame.minY)
    }

    func testNarrowScreenClampsIslandWidth() {
        let geometry = makeGeometry(
            frame: CGRect(x: 0, y: 0, width: 240, height: 180)
        )

        let frame = IslandLayout.frame(in: geometry, mode: .expanded)

        XCTAssertEqual(
            frame.width,
            geometry.visibleFrame.width - (IslandLayout.horizontalMargin * 2),
            accuracy: 0.001
        )
    }

    func testCompactPhysicalNotchUsesDynamicGapAndProportionalWings() {
        let geometry = IslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 932),
            visibleFrame: CGRect(x: 0, y: 61, width: 1440, height: 842),
            safeAreaTop: 28,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 904, width: 642, height: 28),
            auxiliaryTopRightArea: CGRect(x: 798, y: 904, width: 642, height: 28)
        )

        let compact = IslandLayout.frame(in: geometry, mode: .compact)

        let physicalNotchWidth: CGFloat = 798 - 642
        let expectedWidth = physicalNotchWidth
            + (28 * IslandLayout.compactWingToNotchHeightRatio * 2)
        XCTAssertEqual(compact.width, expectedWidth, accuracy: 0.001)
        XCTAssertEqual(compact.height, 28, accuracy: 0.001)
        XCTAssertEqual(compact.midX, geometry.frame.midX, accuracy: 0.001)
        XCTAssertEqual(compact.maxY, geometry.frame.maxY, accuracy: 0.001)
    }

    func testExpandedPhysicalNotchStaysAttachedToPhysicalScreenTop() {
        let geometry = IslandScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 932),
            visibleFrame: CGRect(x: 0, y: 61, width: 1440, height: 842),
            safeAreaTop: 28,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 904, width: 642, height: 28),
            auxiliaryTopRightArea: CGRect(x: 798, y: 904, width: 642, height: 28)
        )

        let expanded = IslandLayout.frame(in: geometry, mode: .expanded)

        XCTAssertEqual(expanded.midX, geometry.frame.midX, accuracy: 0.001)
        XCTAssertEqual(expanded.maxY, geometry.frame.maxY, accuracy: 0.001)
    }

    private func makeGeometry(frame: CGRect) -> IslandScreenGeometry {
        IslandScreenGeometry(
            frame: frame,
            visibleFrame: frame,
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
    }
}
