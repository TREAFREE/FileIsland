import Foundation

enum FFmpegVideoSplitCommandBuilderError: Error, Equatable, Sendable {
    case unsupportedPlan
    case invalidStagingDirectory
    case invalidExecutable
    case unsupportedContainer
}

struct FFmpegVideoSplitCommand: Equatable, Sendable {
    let command: FFmpegCommand
    let stagedArtifacts: [StagedOutputArtifact]
}

/// Builds the single, structured FFmpeg invocation used by the audited
/// keyframe-copy split path. User-provided command fragments never cross this
/// boundary.
struct FFmpegVideoSplitCommandBuilder: Sendable {
    func makeCommand(
        plan: VideoSplitPlan,
        stagingDirectory: URL,
        executableURL: URL
    ) throws -> FFmpegVideoSplitCommand {
        do {
            try VideoSplitDomainValidator.validate(plan: plan)
        } catch {
            throw FFmpegVideoSplitCommandBuilderError.unsupportedPlan
        }

        guard plan.input.kind == .video,
              plan.intent.mode == .fastKeyframeCopy,
              plan.intent.source == .custom,
              plan.ruleSnapshot == nil,
              !plan.segments.isEmpty,
              plan.segments.count <= 999,
              plan.segments.allSatisfy({ !$0.requiresReencoding }),
              plan.segments.last?.endMilliseconds != nil else {
            throw FFmpegVideoSplitCommandBuilderError.unsupportedPlan
        }
        guard executableURL.isFileURL else {
            throw FFmpegVideoSplitCommandBuilderError.invalidExecutable
        }
        guard stagingDirectory.isFileURL,
              stagingDirectory.standardizedFileURL.path != "/" else {
            throw FFmpegVideoSplitCommandBuilderError.invalidStagingDirectory
        }

        let extensions = Set(
            plan.segments.map {
                URL(fileURLWithPath: $0.outputRelativePath.string)
                    .pathExtension.lowercased()
            }
        )
        guard extensions.count == 1, let filenameExtension = extensions.first else {
            throw FFmpegVideoSplitCommandBuilderError.unsupportedContainer
        }
        let segmentFormat: String
        switch filenameExtension {
        case "mp4":
            segmentFormat = "mp4"
        case "mov":
            segmentFormat = "mov"
        default:
            throw FFmpegVideoSplitCommandBuilderError.unsupportedContainer
        }

        let digitCount = max(2, String(plan.segments.count).count)
        let filePrefix = ".fileisland-\(plan.id.uuidString.lowercased())-part"
        let outputPattern = stagingDirectory.appendingPathComponent(
            "\(filePrefix)-%0\(digitCount)d.\(filenameExtension)",
            isDirectory: false
        )

        let stagedArtifacts = plan.segments.map { segment in
            let index = String(format: "%0*d", digitCount, segment.index)
            return StagedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: plan.input.id,
                    role: .videoSegment(
                        ordinal: segment.index,
                        total: plan.segments.count
                    )
                ),
                fileURL: stagingDirectory.appendingPathComponent(
                    "\(filePrefix)-\(index).\(filenameExtension)",
                    isDirectory: false
                )
            )
        }

        var arguments = [
            "-hide_banner",
            "-nostdin",
            "-n",
            "-i", plan.input.url.path,
            "-map", "0:v:0",
            "-map", "0:a:0?",
            "-sn",
            "-dn",
            "-c", "copy",
            "-map_metadata", plan.intent.stripMetadata ? "-1" : "0",
            "-map_chapters", "-1",
            "-f", "segment",
            "-segment_format", segmentFormat,
            "-reference_stream", "v:0",
            "-segment_time_delta", "0.001",
            "-segment_start_number", "1",
            "-reset_timestamps", "1",
            "-individual_header_trailer", "1",
            "-write_empty_segments", "0"
        ]

        let splitTimes = plan.segments.dropLast().map {
            Self.secondsString(milliseconds: $0.endMilliseconds)
        }
        if !splitTimes.isEmpty {
            arguments.append(contentsOf: ["-segment_times", splitTimes.joined(separator: ",")])
        }
        arguments.append(contentsOf: [
            "-progress", "pipe:1",
            "-stats_period", "0.1",
            "-nostats",
            outputPattern.path
        ])

        return FFmpegVideoSplitCommand(
            command: FFmpegCommand(
                executableURL: executableURL,
                arguments: arguments
            ),
            stagedArtifacts: stagedArtifacts
        )
    }

    private static func secondsString(milliseconds: Int64) -> String {
        let seconds = milliseconds / 1_000
        let remainder = milliseconds % 1_000
        return "\(seconds).\(String(format: "%03lld", remainder))"
    }
}
