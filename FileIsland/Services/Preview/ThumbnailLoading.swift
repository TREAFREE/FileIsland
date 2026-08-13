import AppKit
import Foundation
import ImageIO
@preconcurrency import QuickLookThumbnailing

@MainActor
protocol ThumbnailLoading: Sendable {
    func thumbnail(for url: URL, size: CGSize) async -> NSImage?
}

@MainActor
protocol QuickLookThumbnailGenerating: Sendable {
    func thumbnail(for url: URL, size: CGSize) async -> NSImage?
}

@MainActor
protocol ImageThumbnailDecoding: Sendable {
    func thumbnail(
        for url: URL,
        maximumPixelSize: Int,
        scale: CGFloat
    ) async -> NSImage?
}

@MainActor
struct SystemQuickLookThumbnailGenerator: QuickLookThumbnailGenerating {
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail]
        )
        return try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
            .nsImage
    }
}

@MainActor
struct SystemImageThumbnailDecoder: ImageThumbnailDecoding {
    func thumbnail(
        for url: URL,
        maximumPixelSize: Int,
        scale: CGFloat
    ) async -> NSImage? {
        let cgImage: CGImage? = await Task.detached(
            priority: .utility
        ) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(
                source,
                CGImageSourceGetPrimaryImageIndex(source),
                options as CFDictionary
            )
        }.value
        guard let cgImage else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        )
    }
}

@MainActor
struct QuickLookThumbnailLoader: ThumbnailLoading {
    private let imageDecoder: any ImageThumbnailDecoding
    private let quickLookGenerator: any QuickLookThumbnailGenerating

    init(
        imageDecoder: any ImageThumbnailDecoding = SystemImageThumbnailDecoder(),
        quickLookGenerator: any QuickLookThumbnailGenerating =
            SystemQuickLookThumbnailGenerator()
    ) {
        self.imageDecoder = imageDecoder
        self.quickLookGenerator = quickLookGenerator
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maximumPixelSize = max(
            1,
            Int(ceil(max(size.width, size.height) * scale))
        )
        if let image = await imageDecoder.thumbnail(
            for: url,
            maximumPixelSize: maximumPixelSize,
            scale: scale
        ) {
            return image
        }

        return await quickLookGenerator.thumbnail(for: url, size: size)
    }
}
