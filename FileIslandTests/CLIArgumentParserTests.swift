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

    func testParsesFastCustomSplitWithCheckedMillisecondConversion() throws {
        let invocation = try CLIArgumentParser().parse([
            "split", "folder", "movie.mp4", "--recursive",
            "--output", "out", "--max-bytes", "100000000",
            "--max-duration-seconds", "300.125",
            "--mode", "fast-keyframe-copy", "--json"
        ])
        guard case let .split(options) = invocation else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(options.paths, ["folder", "movie.mp4"])
        XCTAssertEqual(options.outputPath, "out")
        XCTAssertTrue(options.recursive)
        XCTAssertEqual(options.maxBytes, 100_000_000)
        XCTAssertEqual(options.maxDurationMilliseconds, 300_125)
        XCTAssertEqual(options.mode, .fastKeyframeCopy)
    }

    func testSplitRejectsMissingInvalidRepeatedAndFutureOptions() {
        let base = [
            "split", "movie.mp4", "--output", "out",
            "--mode", "fast-keyframe-copy", "--json"
        ]
        assertParseFails(base)
        assertParseFails(base + ["--max-bytes", "0"])
        assertParseFails(base + ["--max-duration-seconds", "0.0001"])
        assertParseFails(base + ["--max-duration-seconds", "9223372036854776"])
        assertParseFails([
            "split", "movie.mp4", "--output", "out", "--max-bytes", "1",
            "--mode", "precise-compatible", "--json"
        ])
        assertParseFails([
            "split", "movie.mp4", "--output", "out", "--max-bytes", "1",
            "--max-bytes", "2", "--mode", "fast-keyframe-copy", "--json"
        ])
        assertParseFails([
            "split", "movie.mp4", "--output", "out", "--max-bytes", "1",
            "--sharing-rule", "wechat", "--mode", "fast-keyframe-copy", "--json"
        ])
    }

    func testSplitDoubleDashPreservesDashPrefixedPath() throws {
        let invocation = try CLIArgumentParser().parse([
            "split", "movie.mp4", "--output", "out", "--max-duration-seconds", "60",
            "--mode", "fast-keyframe-copy", "--json", "--", "-second;movie.mp4"
        ])
        guard case let .split(options) = invocation else {
            return XCTFail("Expected split")
        }
        XCTAssertEqual(options.paths, ["movie.mp4", "-second;movie.mp4"])
    }

    private func assertParseFails(_ arguments: [String]) {
        XCTAssertThrowsError(try CLIArgumentParser().parse(arguments))
    }
}
