import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

@MainActor
final class ThumbnailLoadingTests: XCTestCase {
    func testImagePreviewUsesFileContentsWhenQuickLookCanOnlyProvideAnIcon() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("fresh-output.jpg")
        try ImageFixtureFactory.writeImage(
            to: imageURL,
            type: .jpeg,
            width: 120,
            height: 60
        )
        let iconOnlyQuickLook = IconOnlyQuickLookThumbnailGenerator()
        let loader = QuickLookThumbnailLoader(quickLookGenerator: iconOnlyQuickLook)

        let loadedThumbnail = await loader.thumbnail(
            for: imageURL,
            size: CGSize(width: 208, height: 128)
        )
        let thumbnail = try XCTUnwrap(loadedThumbnail)

        XCTAssertEqual(thumbnail.size.width / thumbnail.size.height, 2, accuracy: 0.02)
        XCTAssertEqual(iconOnlyQuickLook.requestCount, 0)
    }

    func testImageDecoderIsAllowedToOpenPublishedOutputWithoutFileManagerPreflight() async throws {
        let publishedOutput = URL(
            fileURLWithPath: "/published-output-that-is-not-visible-to-file-manager.jpg"
        )
        let expectedThumbnail = NSImage(size: NSSize(width: 160, height: 90))
        let imageDecoder = RecordingImageThumbnailDecoder(image: expectedThumbnail)
        let quickLook = IconOnlyQuickLookThumbnailGenerator()
        let loader = QuickLookThumbnailLoader(
            imageDecoder: imageDecoder,
            quickLookGenerator: quickLook
        )

        let loadedThumbnail = await loader.thumbnail(
            for: publishedOutput,
            size: CGSize(width: 208, height: 128)
        )

        XCTAssertTrue(loadedThumbnail === expectedThumbnail)
        XCTAssertEqual(imageDecoder.requestedURLs, [publishedOutput])
        XCTAssertEqual(quickLook.requestCount, 0)
    }
}

@MainActor
private final class RecordingImageThumbnailDecoder: ImageThumbnailDecoding {
    private(set) var requestedURLs: [URL] = []
    private let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }

    func thumbnail(
        for url: URL,
        maximumPixelSize: Int,
        scale: CGFloat
    ) async -> NSImage? {
        requestedURLs.append(url)
        return image
    }
}

@MainActor
private final class IconOnlyQuickLookThumbnailGenerator: QuickLookThumbnailGenerating {
    private(set) var requestCount = 0

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        requestCount += 1
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
