import CoreGraphics
import XCTest
@testable import FileIsland

final class NotchWingLayoutTests: XCTestCase {
    func testRuntimeNotchWidthCreatesEqualUsableWings() {
        let metrics = NotchWingLayout.metrics(islandWidth: 540, notchWidth: 156, horizontalPadding: 14)

        XCTAssertEqual(metrics.leadingWidth, 178, accuracy: 0.001)
        XCTAssertEqual(metrics.trailingWidth, 178, accuracy: 0.001)
        XCTAssertEqual(metrics.occludedWidth, 156, accuracy: 0.001)
    }

    func testOversizedNotchClampsWingsWithoutNegativeGeometry() {
        let metrics = NotchWingLayout.metrics(islandWidth: 120, notchWidth: 180, horizontalPadding: 14)

        XCTAssertEqual(metrics.leadingWidth, 0)
        XCTAssertEqual(metrics.trailingWidth, 0)
        XCTAssertEqual(metrics.occludedWidth, 92)
    }
}
