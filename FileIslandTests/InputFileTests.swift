import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class InputFileTests: XCTestCase {
    func testClassifiesCommonImageAndVideoTypesByConformance() {
        XCTAssertEqual(makeFile(type: .jpeg).kind, .image)
        XCTAssertEqual(makeFile(type: .heic).kind, .image)
        XCTAssertEqual(makeFile(type: .png).kind, .image)
        XCTAssertEqual(makeFile(type: .quickTimeMovie).kind, .video)
        XCTAssertEqual(makeFile(type: .mpeg4Movie).kind, .video)
    }

    func testUnknownTypeFallsBackToOtherAndReadableLabel() {
        let file = makeFile(type: nil)

        XCTAssertEqual(file.kind, .other)
        XCTAssertEqual(file.displayType, "Unknown")
    }

    private func makeFile(type: UTType?) -> InputFile {
        InputFile(
            url: URL(fileURLWithPath: "/tmp/example"),
            type: type,
            fileSize: 1,
            displayName: "example"
        )
    }
}
