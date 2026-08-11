import Foundation
import Testing
@testable import FileIsland

struct FFprobeParserTests {
    @Test
    func metadataParserReadsRotationAudioAndCheckedFileSizeBitrateFallback() throws {
        let payload = Data(
            """
            {
              "streams": [
                {
                  "index": 0,
                  "codec_type": "video",
                  "codec_name": "h264",
                  "width": 1920,
                  "height": 1080,
                  "avg_frame_rate": "30000/1001",
                  "start_time": "1.000000",
                  "side_data_list": [{"rotation": -90}],
                  "tags": {"comment": "Stream note", "handler_name": "VideoHandler"}
                },
                {
                  "index": 1,
                  "codec_type": "audio",
                  "codec_name": "aac",
                  "start_time": "1.010000",
                  "duration": "9.990000"
                }
              ],
              "format": {
                "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
                "duration": "10.000000",
                "start_time": "1.000000",
                "tags": {"title": "Private title", "encoder": "technical"}
              }
            }
            """.utf8
        )

        let metadata = try FFprobeMetadataParser().parse(
            payload,
            inputURL: URL(fileURLWithPath: "/private/tmp/movie.mp4"),
            fileByteCount: 1_000_000
        )

        #expect(metadata.durationMilliseconds == 10_000)
        #expect(metadata.timelineOriginSeconds == Decimal(1))
        #expect(metadata.displayWidth == 1_080)
        #expect(metadata.displayHeight == 1_920)
        #expect(metadata.rotationDegrees == 270)
        #expect(metadata.averageBitrateBitsPerSecond == 800_000)
        #expect(metadata.container == "mp4")
        #expect(metadata.videoCodec == "h264")
        #expect(metadata.audioCodec == "aac")
        #expect(metadata.videoStartMilliseconds == 1_000)
        #expect(metadata.audioStartMilliseconds == 1_010)
        #expect(metadata.audioDurationMilliseconds == 9_990)
        #expect(metadata.userMetadataKeys == ["comment", "title"])
        #expect(abs(metadata.frameDurationMilliseconds - (1_001.0 / 30)) < 0.000_001)
    }

    @Test
    func metadataParserNormalizesEveryRightAngleAndRejectsArbitraryRotation() throws {
        let cases: [(raw: String, expected: Int, width: Int, height: Int)] = [
            ("0", 0, 1_920, 1_080),
            ("90", 90, 1_080, 1_920),
            ("180", 180, 1_920, 1_080),
            ("270", 270, 1_080, 1_920),
            ("-90", 270, 1_080, 1_920),
            ("450", 90, 1_080, 1_920)
        ]

        for testCase in cases {
            let metadata = try FFprobeMetadataParser().parse(
                metadataPayload(rotation: testCase.raw),
                inputURL: URL(fileURLWithPath: "/private/tmp/movie.mp4"),
                fileByteCount: 1_000
            )
            #expect(metadata.rotationDegrees == testCase.expected)
            #expect(metadata.displayWidth == testCase.width)
            #expect(metadata.displayHeight == testCase.height)
        }

        expectParsingFailure(.unsupportedMedia) {
            try FFprobeMetadataParser().parse(
                metadataPayload(rotation: "45"),
                inputURL: URL(fileURLWithPath: "/private/tmp/movie.mp4"),
                fileByteCount: 1_000
            )
        }
    }

    @Test
    func metadataParserFailsClosedForMalformedOrExtensionMismatchedOutput() {
        expectParsingFailure(.malformedOutput) {
            try FFprobeMetadataParser().parse(
                Data("{".utf8),
                inputURL: URL(fileURLWithPath: "/private/tmp/movie.mp4"),
                fileByteCount: 1
            )
        }

        let validShape = Data(
            """
            {"streams":[{"codec_type":"video","codec_name":"h264","width":2,"height":2,"avg_frame_rate":"30/1"}],"format":{"format_name":"mov,mp4","duration":"1"}}
            """.utf8
        )
        expectParsingFailure(.unsupportedMedia) {
            try FFprobeMetadataParser().parse(
                validShape,
                inputURL: URL(fileURLWithPath: "/private/tmp/movie.exe"),
                fileByteCount: 1
            )
        }
    }

    @Test
    func metadataParserUsesTheVideoTimelineInsteadOfAACContainerPadding() throws {
        let payload = Data(
            """
            {
              "streams": [
                {"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"avg_frame_rate":"30/1","start_time":"0.021","duration":"2.046"},
                {"codec_type":"audio","codec_name":"aac","start_time":"0","duration":"2.067"}
              ],
              "format":{"format_name":"mov,mp4","duration":"2.067","bit_rate":"8000000"}
            }
            """.utf8
        )

        let metadata = try FFprobeMetadataParser().parse(
            payload,
            inputURL: URL(fileURLWithPath: "/private/tmp/movie.mp4"),
            fileByteCount: 1_000
        )

        #expect(metadata.durationMilliseconds == 2_046)
        #expect(metadata.videoStartMilliseconds == 21)
        #expect(metadata.audioStartMilliseconds == 0)
        #expect(metadata.audioDurationMilliseconds == 2_067)
    }

    @Test
    func keyframeParserIsIncrementalAndKeepsOnlyOrderedKPackets() throws {
        var parser = FFprobeKeyframeParser()
        try parser.consume(Data("pts_time=1.000000|flags=K__\npts_time=2.000".utf8))
        try parser.consume(Data("000|flags=___\npts_time=5.000000|flags=K__\r\n".utf8))
        let keyframes = try parser.finalize(metadata: makeMetadata())

        #expect(keyframes == [0, 4_000])
    }

    @Test
    func keyframeParserRejectsOutOfOrderAndNonZeroOriginTimelines() throws {
        var outOfOrder = FFprobeKeyframeParser()
        try outOfOrder.consume(
            Data("pts_time=1.000000|flags=K__\npts_time=0.900000|flags=K__\n".utf8)
        )
        expectParsingFailure(.malformedOutput) {
            try outOfOrder.finalize(metadata: makeMetadata())
        }

        var nonZeroOrigin = FFprobeKeyframeParser()
        try nonZeroOrigin.consume(Data("pts_time=1.100000|flags=K__\n".utf8))
        expectParsingFailure(.unsupportedMedia) {
            try nonZeroOrigin.finalize(metadata: makeMetadata())
        }
    }

    private func makeMetadata() -> FFprobeMetadata {
        FFprobeMetadata(
            durationMilliseconds: 10_000,
            timelineOriginSeconds: Decimal(1),
            displayWidth: 1_920,
            displayHeight: 1_080,
            rotationDegrees: 0,
            averageBitrateBitsPerSecond: 8_000_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 1_000,
            audioStartMilliseconds: 1_000,
            audioDurationMilliseconds: 10_000,
            userMetadataKeys: [],
            frameDurationMilliseconds: 1_000 / 30
        )
    }

    private func metadataPayload(rotation: String) -> Data {
        Data(
            """
            {
              "streams": [{
                "codec_type":"video",
                "codec_name":"h264",
                "width":1920,
                "height":1080,
                "avg_frame_rate":"30/1",
                "side_data_list":[{"rotation":"\(rotation)"}]
              }],
              "format":{"format_name":"mov,mp4","duration":"1"}
            }
            """.utf8
        )
    }

    private func expectParsingFailure<T>(
        _ expected: FFprobeParsingError,
        operation: () throws -> T
    ) {
        do {
            _ = try operation()
            Issue.record("Expected parsing failure: \(expected)")
        } catch let error as FFprobeParsingError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
