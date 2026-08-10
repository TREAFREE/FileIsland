import Foundation

enum VideoConversionBackend: Equatable, Sendable {
    case native
    case ffmpegFallback
}

enum MediaConversionMatrix {
    static let imageInputFormats: Set<InputFileFormat> = [
        .heic,
        .heif,
        .jpeg,
        .png,
        .webP,
        .tiff,
        .gif,
        .bmp,
        .avif
    ]

    static let nativeVideoInputFormats: Set<InputFileFormat> = [
        .mov,
        .mp4,
        .m4v
    ]

    static let fallbackVideoInputFormats: Set<InputFileFormat> = [
        .mkv,
        .webM,
        .avi,
        .mpeg,
        .ts,
        .flv,
        .threeGP,
        .wmv
    ]

    static let audioInputFormats: Set<InputFileFormat> = [
        .mp3, .wav, .aiff, .m4a, .aac, .flac, .ogg, .opus, .ac3
    ]

    static let audioOutputFormats: [AudioOutputFormat] = [
        .m4a, .wav, .flac, .aiff
    ]

    static func imageOutputFormats(
        for inputs: [InputFileFormat]
    ) -> [ImageOutputFormat] {
        guard !inputs.isEmpty,
              inputs.allSatisfy(imageInputFormats.contains) else {
            return []
        }
        return [.jpeg, .png]
    }

    static func supportsImageConversion(
        from input: InputFileFormat,
        to output: ImageOutputFormat
    ) -> Bool {
        imageInputFormats.contains(input) && imageOutputFormats(for: [input]).contains(output)
    }

    static func videoBackend(
        for inputs: [InputFileFormat]
    ) -> VideoConversionBackend? {
        guard !inputs.isEmpty else { return nil }
        if inputs.allSatisfy(nativeVideoInputFormats.contains) {
            return .native
        }
        if inputs.allSatisfy(fallbackVideoInputFormats.contains) {
            return .ffmpegFallback
        }
        return nil
    }

    static func supportsAudioConversion(
        from input: InputFileFormat,
        to output: AudioOutputFormat
    ) -> Bool {
        audioInputFormats.contains(input) && audioOutputFormats.contains(output)
    }
}
