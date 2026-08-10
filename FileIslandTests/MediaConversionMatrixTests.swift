import XCTest
@testable import FileIsland

final class MediaConversionMatrixTests: XCTestCase {
    func testCommonImageInputsCanProduceJPEGAndPNG() {
        let inputs: [InputFileFormat] = [
            .heic, .heif, .jpeg, .png, .webP, .tiff, .gif, .bmp, .avif
        ]

        XCTAssertEqual(
            MediaConversionMatrix.imageOutputFormats(for: inputs),
            [.jpeg, .png]
        )
    }

    func testUnknownOrEmptyImageSelectionsHaveNoOutput() {
        XCTAssertEqual(MediaConversionMatrix.imageOutputFormats(for: []), [])
        XCTAssertEqual(MediaConversionMatrix.imageOutputFormats(for: [.other]), [])
    }

    func testNativeAndFallbackVideoBackendsStayDistinct() {
        XCTAssertEqual(
            MediaConversionMatrix.videoBackend(for: [.mov, .mp4, .m4v]),
            .native
        )
        XCTAssertEqual(
            MediaConversionMatrix.videoBackend(for: [.mkv, .webM]),
            .ffmpegFallback
        )
        XCTAssertEqual(
            MediaConversionMatrix.videoBackend(for: [.avi, .mpeg, .ts, .flv, .threeGP, .wmv]),
            .ffmpegFallback
        )
        XCTAssertNil(MediaConversionMatrix.videoBackend(for: [.mp4, .mkv]))
        XCTAssertNil(MediaConversionMatrix.videoBackend(for: []))
    }

    func testAuditedAudioMatrixDoesNotClaimMP3Output() {
        XCTAssertEqual(
            MediaConversionMatrix.audioInputFormats,
            [.mp3, .wav, .aiff, .m4a, .aac, .flac, .ogg, .opus, .ac3]
        )
        XCTAssertEqual(
            MediaConversionMatrix.audioOutputFormats,
            [.m4a, .wav, .flac, .aiff]
        )
        XCTAssertTrue(MediaConversionMatrix.supportsAudioConversion(from: .mp3, to: .m4a))
    }
}
