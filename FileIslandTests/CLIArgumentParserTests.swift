import XCTest
@testable import FileIsland

final class CLIArgumentParserTests: XCTestCase {
    func testParsesCapabilitiesInspectAndStructuredConvert() throws {
        XCTAssertEqual(
            try CLIArgumentParser().parse(["capabilities", "--json"]),
            .capabilities
        )
        XCTAssertEqual(
            try CLIArgumentParser().parse(["inspect", "含 空格.png", "--recursive", "--json"]),
            .inspect(paths: ["含 空格.png"], recursive: true)
        )

        let invocation = try CLIArgumentParser().parse([
            "convert", "folder", "--recursive", "--output", "out",
            "--image-format", "jpeg", "--image-max-dimension", "2048",
            "--image-quality", "balanced", "--strip-metadata",
            "--video-resolution", "720p", "--video-target-bytes", "50000000",
            "--audio-format", "flac", "--audio-quality", "high",
            "--strip-audio-metadata",
            "--json"
        ])
        guard case let .convert(options) = invocation else {
            return XCTFail("Expected convert")
        }
        XCTAssertEqual(options.paths, ["folder"])
        XCTAssertEqual(options.outputPath, "out")
        XCTAssertEqual(options.imageIntent?.outputFormat, .jpeg)
        XCTAssertEqual(options.imageIntent?.maxPixelDimension, 2_048)
        XCTAssertEqual(options.imageIntent?.stripMetadata, true)
        XCTAssertEqual(options.videoIntent?.maxResolution, .p720)
        XCTAssertEqual(options.videoIntent?.targetBytes, 50_000_000)
        XCTAssertEqual(options.audioIntent?.outputFormat, .flac)
        XCTAssertEqual(options.audioIntent?.quality, .high)
        XCTAssertEqual(options.audioIntent?.stripMetadata, true)
    }

    func testRejectsUnknownRepeatedAndConflictingOptions() {
        assertParseFails(["capabilities", "--wat"])
        assertParseFails(["inspect", "a", "--json", "--json"])
        assertParseFails([
            "convert", "a", "--output", "out", "--image-preset", "image-for-web",
            "--image-format", "jpeg", "--json"
        ])
        assertParseFails([
            "convert", "a", "--output", "out", "--video-resolution", "720p",
            "--video-target-bytes", "0", "--json"
        ])
        assertParseFails([
            "convert", "a", "--output", "out", "--audio-format", "mp3", "--json"
        ])
    }

    func testDoubleDashKeepsMetacharacterAndDashPrefixedPathsAsValues() throws {
        let invocation = try CLIArgumentParser().parse([
            "inspect", "--json", "--", "-odd;$(touch nope).png"
        ])
        XCTAssertEqual(
            invocation,
            .inspect(paths: ["-odd;$(touch nope).png"], recursive: false)
        )
    }

    private func assertParseFails(_ arguments: [String]) {
        XCTAssertThrowsError(try CLIArgumentParser().parse(arguments))
    }
}
