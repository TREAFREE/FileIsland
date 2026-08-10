import Foundation

struct FFmpegCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
}

struct FFmpegCommandBuilder: Sendable {
    func makeCommand(
        plan: ConversionPlan,
        input: InputFile,
        outputURL: URL,
        executableURL: URL
    ) throws -> FFmpegCommand {
        guard plan.inputs.contains(where: { $0.id == input.id }),
              MediaConversionMatrix.videoBackend(for: [input.format]) == .ffmpegFallback,
              plan.steps.count == 1,
              case let .video(intent) = plan.steps[0] else {
            throw ConversionError.unsupportedInput
        }
        guard intent.compatibility == .highCompatibility,
              let resolution = intent.maxResolution,
              intent.targetBytes == nil,
              outputURL.pathExtension.lowercased() == "mp4" else {
            throw ConversionError.unsupportedOutput
        }

        let ceiling = longEdgeCeiling(for: resolution)
        let videoBitRate = videoBitRate(for: resolution)
        let scaleFilter = "scale=w=min(iw\\,\(ceiling)):h=min(ih\\,\(ceiling)):force_original_aspect_ratio=decrease:force_divisible_by=2,format=yuv420p"

        return FFmpegCommand(
            executableURL: executableURL,
            arguments: [
                "-hide_banner",
                "-nostdin",
                "-y",
                "-i", input.url.path,
                "-map", "0:v:0",
                "-map", "0:a:0?",
                "-sn",
                "-dn",
                "-vf", scaleFilter,
                "-c:v", "h264_videotoolbox",
                "-b:v", videoBitRate,
                "-profile:v", "high",
                "-pix_fmt", "yuv420p",
                "-tag:v", "avc1",
                "-c:a", "aac",
                "-b:a", "128k",
                "-movflags", "+faststart",
                "-map_metadata", "0",
                "-map_chapters", "-1",
                "-progress", "pipe:1",
                "-stats_period", "0.1",
                "-nostats",
                outputURL.path
            ]
        )
    }

    private func longEdgeCeiling(for resolution: VideoResolution) -> Int {
        switch resolution {
        case .source: 3_840
        case .p1080: 1_920
        case .p720: 1_280
        }
    }

    private func videoBitRate(for resolution: VideoResolution) -> String {
        switch resolution {
        case .source: "8M"
        case .p1080: "5M"
        case .p720: "3M"
        }
    }
}
