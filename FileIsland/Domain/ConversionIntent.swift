import Foundation

enum ConversionIntent: Equatable, Sendable {
    case convertImage(ImageIntent)
    case convertVideo(VideoIntent)
    case convertAudio(AudioIntent)
}

struct ImageIntent: Equatable, Sendable {
    var outputFormat: ImageOutputFormat?
    var maxPixelDimension: Int?
    var targetBytes: Int64?
    var qualityPreference: QualityPreference
    var stripMetadata: Bool
}

struct VideoIntent: Equatable, Sendable {
    var compatibility: CompatibilityTarget?
    var maxResolution: VideoResolution?
    var targetBytes: Int64?
    var qualityPreference: QualityPreference
}

struct AudioIntent: Equatable, Sendable {
    var outputFormat: AudioOutputFormat
    var quality: AudioQuality
    var stripMetadata: Bool
}

enum AudioOutputFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case m4a
    case wav
    case flac
    case aiff

    var filenameExtension: String { rawValue }
}

enum AudioQuality: String, Codable, CaseIterable, Equatable, Sendable {
    case compact
    case balanced
    case high
}

enum ImageOutputFormat: String, Codable, Equatable, Sendable {
    case jpeg
    case png
    case webP

    var filenameExtension: String {
        switch self {
        case .jpeg:
            "jpg"
        case .png:
            "png"
        case .webP:
            "webp"
        }
    }

    func canConvert(_ inputFormat: InputFileFormat) -> Bool {
        MediaConversionMatrix.supportsImageConversion(
            from: inputFormat,
            to: self
        )
    }
}

enum QualityPreference: String, Codable, Equatable, Sendable {
    case smallestFile
    case balanced
    case highestQuality
}

enum CompatibilityTarget: String, Codable, Equatable, Sendable {
    case highCompatibility
    case web
}

enum VideoResolution: String, Codable, Equatable, Sendable {
    case source
    case p1080
    case p720
}
