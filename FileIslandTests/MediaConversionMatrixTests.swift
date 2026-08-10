import XCTest
@testable import FileIsland

final class MediaConversionMatrixTests: XCTestCase {
    func testCommonImageInputsCanProduceJPEGAndPNG() {
        let inputs: [InputFileFormat] = [
            .heic, .heif, .jpeg, .png, .webP, .tiff
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
        XCTAssertNil(MediaConversionMatrix.videoBackend(for: [.mp4, .mkv]))
        XCTAssertNil(MediaConversionMatrix.videoBackend(for: []))
    }
}
