import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("FFmpeg video split command builder")
struct FFmpegVideoSplitCommandBuilderTests {
    @Test("Builds a structured copy-only segment command and stable artifacts")
    func buildsAuditedCommand() throws {
        let plan = try makePlan(
            boundaries: [0, 1_023, 2_046, 3_100],
            stripMetadata: true
        )
        let staging = URL(fileURLWithPath: "/private/tmp/File Island 分段", isDirectory: true)
        let executable = URL(fileURLWithPath: "/Applications/File Island.app/Contents/MacOS/ffmpeg")

        let result = try FFmpegVideoSplitCommandBuilder().makeCommand(
            plan: plan,
            stagingDirectory: staging,
            executableURL: executable
        )

        #expect(result.command.executableURL == executable)
        #expect(result.command.arguments.contains("copy"))
        #expect(result.command.arguments.contains("segment"))
        #expect(result.command.arguments.contains("pipe:1"))
        #expect(value(after: "-segment_times", in: result.command.arguments) == "1.023,2.046")
        #expect(value(after: "-map_metadata", in: result.command.arguments) == "-1")
        #expect(result.command.arguments.last?.hasSuffix("part-%02d.mp4") == true)
        #expect(!result.command.arguments.contains("sh"))
        #expect(!result.command.arguments.contains("-c:v"))
        #expect(result.stagedArtifacts.map(\.id.role) == [
            .videoSegment(ordinal: 1, total: 3),
            .videoSegment(ordinal: 2, total: 3),
            .videoSegment(ordinal: 3, total: 3)
        ])
        #expect(result.stagedArtifacts.map(\.fileURL.lastPathComponent) == [
            ".fileisland-00000000-0000-0000-0000-00000000016b-part-01.mp4",
            ".fileisland-00000000-0000-0000-0000-00000000016b-part-02.mp4",
            ".fileisland-00000000-0000-0000-0000-00000000016b-part-03.mp4"
        ])
    }

    @Test("A one-segment plan omits segment times and can retain metadata")
    func buildsOneSegmentCommand() throws {
        let plan = try makePlan(boundaries: [0, 900], stripMetadata: false)
        let result = try FFmpegVideoSplitCommandBuilder().makeCommand(
            plan: plan,
            stagingDirectory: URL(fileURLWithPath: "/private/tmp/split", isDirectory: true),
            executableURL: URL(fileURLWithPath: "/tmp/ffmpeg")
        )

        #expect(!result.command.arguments.contains("-segment_times"))
        #expect(value(after: "-map_metadata", in: result.command.arguments) == "0")
        #expect(result.stagedArtifacts.count == 1)
    }

    @Test("Precise, verified-rule, unsupported-container, and non-file inputs fail closed")
    func rejectsUnsupportedPlans() throws {
        let staging = URL(fileURLWithPath: "/private/tmp/split", isDirectory: true)
        let executable = URL(fileURLWithPath: "/tmp/ffmpeg")
        let builder = FFmpegVideoSplitCommandBuilder()

        var precise = try makePlan(boundaries: [0, 1_000], stripMetadata: true)
        precise = VideoSplitPlan(
            id: precise.id,
            input: precise.input,
            sourceFileIdentity: precise.sourceFileIdentity,
            intent: VideoSplitIntent(
                source: .custom,
                mode: .preciseCompatible,
                constraints: precise.intent.constraints,
                stripMetadata: true
            ),
            ruleSnapshot: nil,
            segments: precise.segments.map {
                VideoSegmentPlan(
                    index: $0.index,
                    startMilliseconds: $0.startMilliseconds,
                    endMilliseconds: $0.endMilliseconds,
                    outputRelativePath: $0.outputRelativePath,
                    estimatedBytes: $0.estimatedBytes,
                    requiresReencoding: true
                )
            }
        )
        #expect(throws: FFmpegVideoSplitCommandBuilderError.unsupportedPlan) {
            try builder.makeCommand(
                plan: precise,
                stagingDirectory: staging,
                executableURL: executable
            )
        }

        let unsupported = try makePlan(
            boundaries: [0, 1_000],
            stripMetadata: true,
            filenameExtension: "mkv"
        )
        #expect(throws: FFmpegVideoSplitCommandBuilderError.unsupportedContainer) {
            try builder.makeCommand(
                plan: unsupported,
                stagingDirectory: staging,
                executableURL: executable
            )
        }

        let valid = try makePlan(boundaries: [0, 1_000], stripMetadata: true)
        #expect(throws: FFmpegVideoSplitCommandBuilderError.invalidExecutable) {
            try builder.makeCommand(
                plan: valid,
                stagingDirectory: staging,
                executableURL: URL(string: "https://example.com/ffmpeg")!
            )
        }
        #expect(throws: FFmpegVideoSplitCommandBuilderError.invalidStagingDirectory) {
            try builder.makeCommand(
                plan: valid,
                stagingDirectory: URL(fileURLWithPath: "/", isDirectory: true),
                executableURL: executable
            )
        }
    }

    private func makePlan(
        boundaries: [Int64],
        stripMetadata: Bool,
        filenameExtension: String = "mp4"
    ) throws -> VideoSplitPlan {
        let inputID = UUID(uuidString: "00000000-0000-0000-0000-000000000161")!
        let planID = UUID(uuidString: "00000000-0000-0000-0000-00000000016B")!
        let input = InputFile(
            id: inputID,
            url: URL(fileURLWithPath: "/private/tmp/旅行 Movie.mp4"),
            type: .mpeg4Movie,
            fileSize: 400_000,
            displayName: "旅行 Movie.mp4"
        )
        let segmentCount = boundaries.count - 1
        let segments = try (0..<segmentCount).map { offset in
            VideoSegmentPlan(
                index: offset + 1,
                startMilliseconds: boundaries[offset],
                endMilliseconds: boundaries[offset + 1],
                outputRelativePath: try SafeRelativePath(
                    "旅行 Movie — Split/旅行 Movie-part-\(offset + 1).\(filenameExtension)"
                ),
                estimatedBytes: 100_000,
                requiresReencoding: false
            )
        }
        return VideoSplitPlan(
            id: planID,
            input: input,
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: 200_000,
                    maxDurationMilliseconds: 2_000,
                    safetyRatio: 0.9,
                    requiredContainer: nil,
                    requiredVideoCodec: nil,
                    requiredAudioCodec: nil
                ),
                stripMetadata: stripMetadata
            ),
            ruleSnapshot: nil,
            segments: segments
        )
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
