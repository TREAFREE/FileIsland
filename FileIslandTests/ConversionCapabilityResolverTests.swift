import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class ConversionCapabilityResolverTests: XCTestCase {
    func testPNGImageBatchGetsJPEGAndPNGProcessingOptions() {
        let files = [makeFile("one.png", type: .png), makeFile("two.png", type: .png)]

        let capability = ConversionCapabilityResolver().resolve(files)

        XCTAssertEqual(capability, .image(availableFormats: [.jpeg, .png]))
    }

    func testMixedCommonImageBatchGetsJPEGAndPNGOptions() {
        let capability = ConversionCapabilityResolver().resolve([
            makeFile("one.heif", type: .heif),
            makeFile("two.jpg", type: .jpeg),
            makeFile("three.webp", type: .webP),
            makeFile("four.tiff", type: .tiff)
        ])

        XCTAssertEqual(capability, .image(availableFormats: [.jpeg, .png]))
    }

    func testMOVAndMP4BatchGetsVideoOptionsOnly() {
        let capability = ConversionCapabilityResolver().resolve([
            makeFile("clip.mov", type: .quickTimeMovie),
            makeFile("second.mp4", type: .mpeg4Movie)
        ])

        XCTAssertEqual(
            capability,
            .video(
                availableResolutions: [.source, .p1080, .p720],
                supportsTargetSize: true
            )
        )
    }

    func testM4VJoinsNativeVideoBatchAndSupportsTargetSize() {
        let capability = ConversionCapabilityResolver().resolve([
            makeFile("clip.m4v", type: nil),
            makeFile("second.mp4", type: .mpeg4Movie)
        ])

        XCTAssertEqual(
            capability,
            .video(
                availableResolutions: [.source, .p1080, .p720],
                supportsTargetSize: true
            )
        )
    }

    func testMKVAndWebMBatchGetsFallbackOptionsWithoutTargetSize() {
        let capability = ConversionCapabilityResolver().resolve([
            makeFile("clip.mkv", type: UTType(filenameExtension: "mkv")!),
            makeFile("second.webm", type: UTType(filenameExtension: "webm")!)
        ])

        XCTAssertEqual(
            capability,
            .video(
                availableResolutions: [.source, .p1080, .p720],
                supportsTargetSize: false
            )
        )
    }

    func testMixedBatchIsUnsupported() {
        let files = [makeFile("one.png", type: .png), makeFile("clip.mov", type: .quickTimeMovie)]

        XCTAssertEqual(ConversionCapabilityResolver().resolve(files), .unsupported(kind: .mixed))
    }

    private func makeFile(_ name: String, type: UTType?) -> InputFile {
        InputFile(url: URL(fileURLWithPath: "/tmp/\(name)"), type: type, fileSize: 42, displayName: name)
    }
}
