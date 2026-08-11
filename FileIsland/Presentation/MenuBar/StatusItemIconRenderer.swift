import AppKit

@MainActor
enum StatusItemIconRenderer {
    private static let canvasSize = NSSize(width: 18, height: 18)
    private static let rasterSize = NSSize(width: 36, height: 36)
    private static let visibleSize = NSSize(width: 34, height: 32)

    static func normalizedTemplate(_ source: NSImage) -> NSImage {
        guard let outputBitmap = normalizedMask(source) else {
            return fallbackCopy(of: source)
        }

        let output = NSImage(size: canvasSize)
        output.addRepresentation(outputBitmap)
        output.isTemplate = true
        output.accessibilityDescription = source.accessibilityDescription ?? "File Island"
        return output
    }

    /// Produces the exact monochrome raster installed in the status item.
    /// Keeping this as a bitmap avoids AppKit re-rendering a template image as
    /// an opaque canvas on older/headless macOS renderers.
    static func normalizedMask(_ source: NSImage) -> NSBitmapImageRep? {
        guard
            let sourceBitmap = bitmap(width: Int(rasterSize.width), height: Int(rasterSize.height)),
            render(source, into: sourceBitmap),
            let visibleBounds = alphaBounds(in: sourceBitmap),
            let sourceCGImage = sourceBitmap.cgImage,
            let croppedCGImage = sourceCGImage.cropping(to: coreGraphicsCropRect(
                visibleBounds,
                imageHeight: sourceBitmap.pixelsHigh
            )),
            let outputBitmap = bitmap(width: Int(rasterSize.width), height: Int(rasterSize.height)),
            let context = NSGraphicsContext(bitmapImageRep: outputBitmap)
        else { return nil }

        let destination = NSRect(
            x: (rasterSize.width - visibleSize.width) / 2,
            y: (rasterSize.height - visibleSize.height) / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )

        context.cgContext.clear(CGRect(origin: .zero, size: rasterSize))
        context.cgContext.interpolationQuality = .high
        context.cgContext.draw(croppedCGImage, in: destination)
        outputBitmap.size = canvasSize
        return outputBitmap
    }

    private static func bitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    }

    private static func render(_ image: NSImage, into bitmap: NSBitmapImageRep) -> Bool {
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return false }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(
            CGRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        )
        image.draw(
            in: NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh),
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        return true
    }

    static func alphaBounds(in bitmap: NSBitmapImageRep) -> CGRect? {
        var minimumX = bitmap.pixelsWide
        var minimumY = bitmap.pixelsHigh
        var maximumX = -1
        var maximumY = -1

        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide
            where bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 > 0.03 {
                minimumX = min(minimumX, x)
                minimumY = min(minimumY, y)
                maximumX = max(maximumX, x)
                maximumY = max(maximumY, y)
            }
        }

        guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
        return CGRect(
            x: minimumX,
            y: minimumY,
            width: maximumX - minimumX + 1,
            height: maximumY - minimumY + 1
        )
    }

    private static func coreGraphicsCropRect(_ bounds: CGRect, imageHeight: Int) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: CGFloat(imageHeight) - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func fallbackCopy(of source: NSImage) -> NSImage {
        let image = (source.copy() as? NSImage) ?? source
        image.size = canvasSize
        image.isTemplate = true
        return image
    }
}
