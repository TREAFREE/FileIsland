import Foundation

struct PresetRecommendation: Equatable, Sendable {
    let preset: ConversionPreset
    let intent: ConversionIntent
}

struct ConversionPresetResolver: Sendable {
    func recommendations(
        for files: [InputFile],
        capability: ConversionCapability,
        presets: [ConversionPreset]
    ) -> [PresetRecommendation] {
        guard !files.isEmpty else { return [] }
        return presets.compactMap { preset in
            recommendation(for: preset, files: files, capability: capability)
        }
    }

    private func recommendation(
        for preset: ConversionPreset,
        files: [InputFile],
        capability: ConversionCapability
    ) -> PresetRecommendation? {
        switch (preset.mediaType, capability) {
        case let (.image, .image(availableFormats)):
            guard let outputFormat = preset.output.imageFormat,
                  availableFormats.contains(outputFormat),
                  files.allSatisfy({ outputFormat.canConvert($0.format) }),
                  let quality = preset.options.quality,
                  let stripMetadata = preset.options.stripMetadata else {
                return nil
            }
            return PresetRecommendation(
                preset: preset,
                intent: .convertImage(
                    ImageIntent(
                        outputFormat: outputFormat,
                        maxPixelDimension: preset.constraints.maxPixelDimension,
                        targetBytes: preset.constraints.maxBytes,
                        qualityPreference: quality,
                        stripMetadata: stripMetadata
                    )
                )
            )

        case let (.video, .video(availableResolutions, supportsTargetSize)):
            guard preset.output.container == .mp4,
                  preset.output.videoCodec == .h264,
                  preset.output.audioCodec == .aac,
                  let compatibility = preset.output.compatibility,
                  let quality = preset.options.quality,
                  let resolution = preset.constraints.maxResolution,
                  availableResolutions.contains(resolution),
                  supportsTargetSize || preset.constraints.maxBytes == nil else {
                return nil
            }
            return PresetRecommendation(
                preset: preset,
                intent: .convertVideo(
                    VideoIntent(
                        compatibility: compatibility,
                        maxResolution: resolution,
                        targetBytes: preset.constraints.maxBytes,
                        qualityPreference: quality
                    )
                )
            )

        default:
            return nil
        }
    }
}
