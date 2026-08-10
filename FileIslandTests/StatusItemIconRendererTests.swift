import AppKit
import XCTest
@testable import FileIsland

@MainActor
final class StatusItemIconRendererTests: XCTestCase {
    func testNormalizedMenuTemplateHasStandardOpticalBoundsWithoutClipping() throws {
        let source = try XCTUnwrap(NSImage(named: "FileIslandMenuTemplate"))

        let normalized = StatusItemIconRenderer.normalizedTemplate(source)
        let mask = try XCTUnwrap(StatusItemIconRenderer.normalizedMask(source))
        let bounds = try XCTUnwrap(StatusItemIconRenderer.alphaBounds(in: mask))

        XCTAssertEqual(normalized.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(normalized.isTemplate)
        XCTAssertEqual(mask.pixelsWide, 36)
        XCTAssertEqual(mask.pixelsHigh, 36)
        XCTAssertGreaterThanOrEqual(bounds.width, 33)
        XCTAssertGreaterThanOrEqual(bounds.height, 29)
        XCTAssertGreaterThan(bounds.minX, 0)
        XCTAssertGreaterThan(bounds.minY, 0)
        XCTAssertLessThan(bounds.maxX, 36)
        XCTAssertLessThan(bounds.maxY, 36)
    }
}
