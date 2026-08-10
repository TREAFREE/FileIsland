import Foundation

struct ConversionPresetCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let presets: [ConversionPreset]
}

struct ConversionPreset: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let version: Int
    let displayName: String
    let summary: String
    let mediaType: PresetMediaType
    let output: PresetOutput
    let constraints: PresetConstraints
    let options: PresetOptions
}

enum PresetMediaType: String, Codable, Equatable, Sendable {
    case image
    case video
}

struct PresetOutput: Codable, Equatable, Sendable {
    let imageFormat: ImageOutputFormat?
    let container: PresetVideoContainer?
    let videoCodec: PresetVideoCodec?
    let audioCodec: PresetAudioCodec?
    let compatibility: CompatibilityTarget?
}

enum PresetVideoContainer: String, Codable, Equatable, Sendable {
    case mp4
}

enum PresetVideoCodec: String, Codable, Equatable, Sendable {
    case h264
}

enum PresetAudioCodec: String, Codable, Equatable, Sendable {
    case aac
}

struct PresetConstraints: Codable, Equatable, Sendable {
    let maxPixelDimension: Int?
    let maxResolution: VideoResolution?
    let maxBytes: Int64?
}

struct PresetOptions: Codable, Equatable, Sendable {
    let quality: QualityPreference?
    let stripMetadata: Bool?
}
