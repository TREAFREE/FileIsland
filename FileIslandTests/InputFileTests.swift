import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class InputFileTests: XCTestCase {
    func testClassifiesCommonImageAndVideoTypesByConformance() {
        XCTAssertEqual(makeFile(type: .jpeg).kind, .image)
        XCTAssertEqual(makeFile(type: .jpeg).format, .jpeg)
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

    func testCodableRoundTripPreservesStableFileFactsAndTypeIdentifier() throws {
        let input = InputFile(
            id: UUID(uuidString: "E61956C3-1FA1-4F64-B854-95D1FCAB51F8")!,
            url: URL(fileURLWithPath: "/tmp/旅行 素材/夏天.mov"),
            type: .quickTimeMovie,
            fileSize: 8_765_432,
            displayName: "夏天 🌊.mov"
        )

        let data = try JSONEncoder().encode(input)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let decoded = try JSONDecoder().decode(InputFile.self, from: data)

        XCTAssertEqual(object["type"] as? String, UTType.quickTimeMovie.identifier)
        XCTAssertEqual(decoded, input)
        XCTAssertEqual(decoded.id, input.id)
        XCTAssertEqual(decoded.url, input.url)
        XCTAssertEqual(decoded.type?.identifier, input.type?.identifier)
        XCTAssertEqual(decoded.fileSize, input.fileSize)
        XCTAssertEqual(decoded.displayName, input.displayName)
    }

    func testCodableRoundTripPreservesAbsentType() throws {
        let input = InputFile(
            id: UUID(uuidString: "9E49C48E-0D52-44B3-886A-AB22AC76FE87")!,
            url: URL(fileURLWithPath: "/tmp/unknown.data"),
            type: nil,
            fileSize: 12,
            displayName: "unknown.data"
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(InputFile.self, from: data)

        XCTAssertEqual(decoded, input)
        XCTAssertNil(decoded.type)
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
