import Foundation

struct FFmpegAudioCommandBuilder: Sendable {
    func makeCommand(
        plan: ConversionPlan,
        input: InputFile,
        outputURL: URL,
        executableURL: URL
    ) throws -> FFmpegCommand {
        guard plan.inputs.contains(where: { $0.id == input.id }),
              plan.steps.count == 1,
              case let .audio(intent) = plan.steps[0],
              MediaConversionMatrix.supportsAudioConversion(
                  from: input.format,
                  to: intent.outputFormat
              ),
              outputURL.pathExtension.lowercased() == intent.outputFormat.filenameExtension else {
            throw ConversionError.unsupportedInput
        }

        var arguments = [
            "-hide_banner", "-nostdin", "-y",
            "-i", input.url.path,
            "-map", "0:a:0",
            "-vn", "-sn", "-dn"
        ]
        arguments += codecArguments(for: intent)
        arguments += intent.stripMetadata
            ? ["-map_metadata", "-1", "-map_chapters", "-1"]
            : ["-map_metadata", "0", "-map_chapters", "-1"]
        arguments += [
            "-progress", "pipe:1",
            "-stats_period", "0.5",
            "-nostats",
            outputURL.path
        ]
        return FFmpegCommand(executableURL: executableURL, arguments: arguments)
    }

    private func codecArguments(for intent: AudioIntent) -> [String] {
        switch intent.outputFormat {
        case .m4a:
            return [
                "-c:a", "aac",
                "-b:a", aacBitRate(for: intent.quality),
                "-movflags", "+faststart",
                "-f", "ipod"
            ]
        case .wav:
            return ["-c:a", "pcm_s16le", "-f", "wav"]
        case .flac:
            return [
                "-c:a", "flac",
                "-compression_level", flacCompressionLevel(for: intent.quality),
                "-f", "flac"
            ]
        case .aiff:
            return ["-c:a", "pcm_s16be", "-f", "aiff"]
        }
    }

    private func aacBitRate(for quality: AudioQuality) -> String {
        switch quality {
        case .compact: "96k"
        case .balanced: "160k"
        case .high: "256k"
        }
    }

    private func flacCompressionLevel(for quality: AudioQuality) -> String {
        switch quality {
        case .compact: "8"
        case .balanced: "5"
        case .high: "3"
        }
    }
}
