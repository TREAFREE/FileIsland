import AVFoundation
import AudioToolbox
import VideoToolbox
import XCTest

@MainActor
final class VideoFixtureFactoryTests: XCTestCase {
    func testCreatesPlayableRotatedMOVWithH264VideoAndAudio() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.mov")

        try await VideoFixtureFactory.writeMovie(
            to: url,
            fileType: .mov,
            width: 160,
            height: 90,
            duration: 0.5,
            withAudio: true,
            rotationDegrees: 90
        )
        let info = try await VideoFixtureFactory.inspect(url)

        XCTAssertTrue(info.isPlayable)
        XCTAssertEqual(info.videoCodec, kCMVideoCodecType_H264)
        XCTAssertNotNil(info.audioCodec)
        XCTAssertEqual(info.displaySize.width, 90, accuracy: 1)
        XCTAssertEqual(info.displaySize.height, 160, accuracy: 1)
        XCTAssertEqual(info.duration, 0.5, accuracy: 0.1)
        XCTAssertGreaterThan(try fileSize(url), 0)
    }

    private func fileSize(_ url: URL) throws -> Int {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }
}
