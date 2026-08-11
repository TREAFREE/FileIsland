import Foundation
import XCTest
@testable import FileIsland

final class FFmpegDiagnosticParserTests: XCTestCase {
    func testParsesFragmentedDurationAndAudioStream() {
        var parser = FFmpegDiagnosticParser(sensitivePaths: [])

        parser.consume(Data("Input #0, matroska\n  Duration: 00:01:".utf8))
        parser.consume(Data("02.50, start: 0.0\n  Stream #0:0: Video: vp9, yuv420p, 180x320, 30 fps\n  Stream #0:1: Audio: opus\n".utf8))

        XCTAssertEqual(parser.metadata.duration ?? 0, 62.5, accuracy: 0.001)
        XCTAssertTrue(parser.metadata.hasAudio)
        XCTAssertEqual(parser.metadata.displaySize, CGSize(width: 180, height: 320))
    }

    func testBoundsDiagnosticAndRedactsLocalPaths() {
        let secret = "/Users/person/Private/input file.mkv"
        var parser = FFmpegDiagnosticParser(
            sensitivePaths: [secret],
            maximumDiagnosticCharacters: 80
        )

        parser.consume(Data((String(repeating: "x", count: 120) + secret).utf8))

        XCTAssertLessThanOrEqual(parser.diagnostic.count, 80)
        XCTAssertFalse(parser.diagnostic.contains(secret))
        XCTAssertTrue(parser.diagnostic.contains("<path>"))
    }

    func testAppliesDisplayMatrixRotationToSourceGeometry() {
        var parser = FFmpegDiagnosticParser(sensitivePaths: [])

        parser.consume(Data("Stream #0:0: Video: h264, yuv420p, 1920x1080\n".utf8))
        parser.consume(Data("displaymatrix: rotation of -90.00 degrees\n".utf8))

        XCTAssertEqual(parser.metadata.orientedDisplaySize, CGSize(width: 1080, height: 1920))
    }

    func testDiscardsAnOversizedLineAndRecoversAtTheNextNewline() {
        var parser = FFmpegDiagnosticParser(sensitivePaths: [])

        parser.consume(Data(String(repeating: "x", count: 128 * 1_024).utf8))
        parser.consume(Data(
            "ignored\n  Duration: 00:00:03.25, start: 0.0\n  Stream #0:0: Video: h264, yuv420p, 640x360\n".utf8
        ))

        XCTAssertEqual(parser.metadata.duration ?? 0, 3.25, accuracy: 0.001)
        XCTAssertEqual(parser.metadata.displaySize, CGSize(width: 640, height: 360))
    }
}
