import AppKit
import XCTest
@testable import FileIsland

@MainActor
final class StatusItemIconRendererTests: XCTestCase {
    func testNormalizedMenuTemplateHasStandardOpticalBoundsWithoutClipping() throws {
        let source = try XCTUnwrap(NSImage(named: "FileIslandMenuTemplate"))

        let normalized = StatusItemIconRenderer.normalizedTemplate(source)
        let bounds = try visibleBounds(of: normalized, pixelsWide: 36, pixelsHigh: 36)

        XCTAssertEqual(normalized.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(normalized.isTemplate)
        XCTAssertGreaterThanOrEqual(bounds.width, 30)
        XCTAssertGreaterThanOrEqual(bounds.height, 28)
        XCTAssertGreaterThan(bounds.minX, 0)
        XCTAssertGreaterThan(bounds.minY, 0)
        XCTAssertLessThan(bounds.maxX, 36)
        XCTAssertLessThan(bounds.maxY, 36)
    }

    private func visibleBounds(
        of image: NSImage,
        pixelsWide: Int,
        pixelsHigh: Int
    ) throws -> CGRect {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw TestError.bitmapCreationFailed
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        var minimumX = pixelsWide
        var minimumY = pixelsHigh
        var maximumX = -1
        var maximumY = -1
        for y in 0 ..< pixelsHigh {
            for x in 0 ..< pixelsWide where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.05 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else {
            throw TestError.noVisiblePixels
        }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }
}

private enum TestError: Error {
    case bitmapCreationFailed
    case noVisiblePixels
}
