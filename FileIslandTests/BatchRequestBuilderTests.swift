import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class BatchRequestBuilderTests: XCTestCase {
    func testBuildsEveryGroupAndValidatedPlans() throws {
        let output = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let scan = try scanResult([
            ("photos/a.jpg", UTType.jpeg),
            ("native/a.mov", UTType.quickTimeMovie),
            ("fallback/a.mkv", UTType(filenameExtension: "mkv")),
            ("audio/a.mp3", UTType(filenameExtension: "mp3")),
            ("notes/readme.txt", UTType.plainText)
        ])

        let request = try BatchRequestBuilder().makeRequest(
            scan: scan,
            imageIntent: imageIntent(.png),
            videoIntent: videoIntent(targetBytes: 20_000_000),
            audioIntent: AudioIntent(outputFormat: .m4a, quality: .balanced, stripMetadata: true),
            outputDirectory: output
        )

        XCTAssertEqual(request.group(.image).inputs.count, 1)
        XCTAssertEqual(request.group(.nativeVideo).inputs.count, 1)
        XCTAssertEqual(request.group(.fallbackVideo).inputs.count, 1)
        XCTAssertEqual(request.group(.audio).inputs.count, 1)
        XCTAssertEqual(request.group(.unsupported).inputs.count, 1)
        XCTAssertNotNil(request.group(.image).plan)
        XCTAssertNotNil(request.group(.nativeVideo).plan)
        XCTAssertNotNil(request.group(.fallbackVideo).plan)
        XCTAssertNotNil(request.group(.audio).plan)
        XCTAssertNil(request.group(.unsupported).plan)
        XCTAssertEqual(request.processCount, 4)
        XCTAssertEqual(request.skippedCount, 0)
        XCTAssertEqual(request.failClosedCount, 1)
    }

    func testRemovesTargetSizeFromFallbackPlanButKeepsItForNativePlan() throws {
        let scan = try scanResult([
            ("native.mp4", UTType.mpeg4Movie),
            ("fallback.webm", UTType(filenameExtension: "webm"))
        ])
        let request = try BatchRequestBuilder().makeRequest(
            scan: scan,
            imageIntent: nil,
            videoIntent: videoIntent(targetBytes: 50_000_000),
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        )

        XCTAssertEqual(request.group(.nativeVideo).plan?.videoIntent?.targetBytes, 50_000_000)
        XCTAssertNil(request.group(.fallbackVideo).plan?.videoIntent?.targetBytes)
    }

    func testMissingIntentExplicitlySkipsSupportedGroup() throws {
        let scan = try scanResult([
            ("a.png", UTType.png),
            ("b.mov", UTType.quickTimeMovie)
        ])
        let request = try BatchRequestBuilder().makeRequest(
            scan: scan,
            imageIntent: imageIntent(.jpeg),
            videoIntent: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        )

        XCTAssertEqual(request.processCount, 1)
        XCTAssertEqual(request.skippedCount, 1)
        XCTAssertEqual(request.failClosedCount, 0)
        XCTAssertNil(request.group(.nativeVideo).plan)
    }

    func testSameFormatWithoutRealProcessingIntentIsSkipped() throws {
        let scan = try scanResult([("a.jpg", UTType.jpeg)])

        let noOp = try BatchRequestBuilder().makeRequest(
            scan: scan,
            imageIntent: ImageIntent(
                outputFormat: .jpeg,
                maxPixelDimension: nil,
                targetBytes: nil,
                qualityPreference: .balanced,
                stripMetadata: false
            ),
            videoIntent: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        )
        let resize = try BatchRequestBuilder().makeRequest(
            scan: scan,
            imageIntent: ImageIntent(
                outputFormat: .jpeg,
                maxPixelDimension: 1280,
                targetBytes: nil,
                qualityPreference: .balanced,
                stripMetadata: false
            ),
            videoIntent: nil,
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        )

        XCTAssertEqual(noOp.processCount, 0)
        XCTAssertEqual(noOp.skippedCount, 1)
        XCTAssertEqual(resize.processCount, 1)
        XCTAssertNotNil(resize.group(.image).plan)
    }

    private func scanResult(_ fixtures: [(String, UTType?)]) throws -> InputScanResult {
        let root = URL(fileURLWithPath: "/tmp/input", isDirectory: true)
        let selection = InputSelection.folder(root)
        return InputScanResult(
            selections: [selection],
            inputs: try fixtures.map { path, type in
                let url = root.appendingPathComponent(path)
                return BatchInput(
                    file: InputFile(url: url, type: type, fileSize: 10, displayName: url.lastPathComponent),
                    selection: selection,
                    relativePath: try SafeRelativePath(path)
                )
            }
        )
    }

    private func imageIntent(_ format: ImageOutputFormat) -> ImageIntent {
        ImageIntent(
            outputFormat: format,
            maxPixelDimension: nil,
            targetBytes: nil,
            qualityPreference: .balanced,
            stripMetadata: true
        )
    }

    private func videoIntent(targetBytes: Int64?) -> VideoIntent {
        VideoIntent(
            compatibility: .highCompatibility,
            maxResolution: .source,
            targetBytes: targetBytes,
            qualityPreference: .balanced
        )
    }
}

private extension ConversionPlan {
    var videoIntent: VideoIntent? {
        guard case let .video(intent) = steps.first else { return nil }
        return intent
    }
}
