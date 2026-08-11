import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class VideoSplitProbeTests: XCTestCase {
    private static let inputID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000016"
    )!
    private static let inputURL = URL(fileURLWithPath: "/tmp/probe.mp4")

    func testValidFactsPreserveAuditedSourceMetadata() throws {
        let facts = makeFacts()

        XCTAssertEqual(try facts.validated(for: .preciseCompatible), facts)
        XCTAssertEqual(try facts.validated(for: .fastKeyframeCopy), facts)
    }

    func testFastModeRequiresSortedUniqueKeyframesBeginningAtZero() {
        let keyframeCases: [[Int64]] = [
            [1_000],
            [0, 2_000, 1_000],
            [0, 1_000, 1_000],
            [0, 12_001]
        ]
        for keyframes in keyframeCases {
            let facts = makeFacts(keyframeMilliseconds: keyframes)

            XCTAssertThrowsError(try facts.validated(for: .fastKeyframeCopy)) {
                XCTAssertEqual($0 as? VideoSplitProbeError, .invalidKeyframeTimeline)
            }
        }
    }

    func testPreciseModeStillRequiresAnAuditedSafeKeyframeTimeline() {
        XCTAssertThrowsError(
            try makeFacts(keyframeMilliseconds: []).validated(for: .preciseCompatible)
        ) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidKeyframeTimeline)
        }
    }

    func testRejectsInvalidDurationDimensionsBitrateFrameDurationAndMediaIdentity() {
        XCTAssertNoThrow(
            try makeFacts(
                durationMilliseconds: VideoSplitSourceFacts.maximumDurationMilliseconds,
                keyframeMilliseconds: [0]
            ).validated(for: .preciseCompatible)
        )
        XCTAssertThrowsError(try makeFacts(durationMilliseconds: 0).validated(for: .preciseCompatible)) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidDuration)
        }
        XCTAssertThrowsError(
            try makeFacts(durationMilliseconds: VideoSplitSourceFacts.maximumDurationMilliseconds + 1)
                .validated(for: .preciseCompatible)
        ) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidDuration)
        }
        XCTAssertThrowsError(try makeFacts(displayWidth: 0).validated(for: .preciseCompatible)) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidDisplayDimensions)
        }
        XCTAssertThrowsError(try makeFacts(rotationDegrees: 45).validated(for: .preciseCompatible)) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidDisplayRotation)
        }
        XCTAssertThrowsError(try makeFacts(averageBitrateBitsPerSecond: 0).validated(for: .preciseCompatible)) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidAverageBitrate)
        }
        XCTAssertThrowsError(try makeFacts(frameDurationMilliseconds: .nan).validated(for: .preciseCompatible)) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidFrameDuration)
        }
        XCTAssertThrowsError(try makeFacts(container: "../mp4").validated(for: .preciseCompatible)) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .invalidMediaIdentity)
        }
    }

    func testProbeProtocolCanBeInjectedWithoutReadingMedia() async throws {
        let expected = makeFacts(displayWidth: 1_080, displayHeight: 1_920, audioCodec: nil)
        let probe = StubVideoSplitProbe(result: .success(expected))

        let actual = try await probe.probe(makeInput())

        XCTAssertEqual(actual, expected)
    }

    func testFactsMustMatchTheInputIdentityAndLocalURL() {
        let mismatchedID = makeFacts(inputID: UUID())
        XCTAssertThrowsError(
            try mismatchedID.validated(for: .preciseCompatible, matching: makeInput())
        ) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .inputIdentityMismatch)
        }

        let remoteInput = InputFile(
            id: Self.inputID,
            url: URL(string: "https://example.com/probe.mp4")!,
            type: .mpeg4Movie,
            fileSize: 1,
            displayName: "probe.mp4"
        )
        XCTAssertThrowsError(
            try makeFacts().validated(for: .preciseCompatible, matching: remoteInput)
        ) {
            XCTAssertEqual($0 as? VideoSplitProbeError, .inputIdentityMismatch)
        }
    }

    private func makeFacts(
        inputID: UUID = VideoSplitProbeTests.inputID,
        sourceURL: URL = VideoSplitProbeTests.inputURL,
        durationMilliseconds: Int64 = 12_000,
        displayWidth: Int = 1_920,
        displayHeight: Int = 1_080,
        rotationDegrees: Int = 0,
        averageBitrateBitsPerSecond: Int64 = 8_000_000,
        container: String = "mp4",
        videoCodec: String = "h264",
        audioCodec: String? = "aac",
        frameDurationMilliseconds: Double = 1_000 / 30,
        keyframeMilliseconds: [Int64] = [0, 3_000, 6_000, 9_000]
    ) -> VideoSplitSourceFacts {
        VideoSplitSourceFacts(
            inputID: inputID,
            sourceURL: sourceURL,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: 12_000_000),
            durationMilliseconds: durationMilliseconds,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            rotationDegrees: rotationDegrees,
            averageBitrateBitsPerSecond: averageBitrateBitsPerSecond,
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            videoStartMilliseconds: 0,
            audioStartMilliseconds: audioCodec == nil ? nil : 0,
            audioDurationMilliseconds: audioCodec == nil ? nil : durationMilliseconds,
            userMetadataKeys: [],
            frameDurationMilliseconds: frameDurationMilliseconds,
            keyframeMilliseconds: keyframeMilliseconds
        )
    }

    private func makeInput() -> InputFile {
        InputFile(
            id: Self.inputID,
            url: Self.inputURL,
            type: .mpeg4Movie,
            fileSize: 12_000_000,
            displayName: "probe.mp4"
        )
    }
}

private struct StubVideoSplitProbe: VideoSplitProbing {
    let result: Result<VideoSplitSourceFacts, VideoSplitProbeError>

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        try result.get()
    }
}
