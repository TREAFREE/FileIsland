import AppKit
import Foundation
import QuickLookThumbnailing

@MainActor
protocol ThumbnailLoading: Sendable {
    func thumbnail(for url: URL, size: CGSize) async -> NSImage?
}

@MainActor
struct QuickLookThumbnailLoader: ThumbnailLoading {
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail, .icon]
        )
        return try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
            .nsImage
    }
}
