import Foundation

enum ConversionIntent: Equatable, Sendable {
    case convertImage(ImageIntent)
    case convertVideo(VideoIntent)
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

enum ImageOutputFormat: String, Equatable, Sendable {
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
        switch (inputFormat, self) {
        case (.heic, .jpeg), (.png, .jpeg), (.jpeg, .png):
            true
        default:
            false
        }
    }
}

enum QualityPreference: String, Equatable, Sendable {
    case smallestFile
    case balanced
    case highestQuality
}

enum CompatibilityTarget: String, Equatable, Sendable {
    case highCompatibility
    case web
}

enum VideoResolution: String, Equatable, Sendable {
    case source
    case p1080
    case p720
}
