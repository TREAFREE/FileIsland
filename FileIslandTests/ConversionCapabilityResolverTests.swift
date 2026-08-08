import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class ConversionCapabilityResolverTests: XCTestCase {
    func testPNGImageBatchGetsImageOptionsOnly() {
        let files = [makeFile("one.png", type: .png), makeFile("two.png", type: .png)]

        let capability = ConversionCapabilityResolver().resolve(files)

        XCTAssertEqual(capability, .image(availableFormats: [.jpeg]))
    }

    func testVideoGetsUnsupportedVideoMessageInsteadOfImageFormats() {
        let capability = ConversionCapabilityResolver().resolve([makeFile("clip.mov", type: .quickTimeMovie)])

        XCTAssertEqual(capability, .unsupported(kind: .video))
    }

    func testMixedBatchIsUnsupported() {
        let files = [makeFile("one.png", type: .png), makeFile("clip.mov", type: .quickTimeMovie)]

        XCTAssertEqual(ConversionCapabilityResolver().resolve(files), .unsupported(kind: .mixed))
    }

    private func makeFile(_ name: String, type: UTType) -> InputFile {
        InputFile(url: URL(fileURLWithPath: "/tmp/\(name)"), type: type, fileSize: 42, displayName: name)
    }
}
