import Foundation

enum FileIslandCoreError: Error, Equatable, Sendable {
    case recursiveRequired
    case missingImageConfiguration
    case missingVideoConfiguration
    case missingAudioConfiguration
    case conflictingConfiguration
    case presetNotApplicable(String)
    case unsupportedInput
}

struct CoreMediaCapabilities: Equatable, Sendable {
    let inputFormats: [String]
    let outputFormats: [String]
}

struct CoreVideoCapabilities: Equatable, Sendable {
    let nativeInputFormats: [String]
    let fallbackInputFormats: [String]
    let outputContainer: String
    let resolutions: [String]
    let nativeSupportsTargetBytes: Bool
    let fallbackSupportsTargetBytes: Bool
}

struct CorePreset: Equatable, Sendable {
    let id: String
    let displayName: String
    let summary: String
    let mediaType: String
}

struct CoreCapabilities: Equatable, Sendable {
    let schemaVersion: Int
    let image: CoreMediaCapabilities
    let video: CoreVideoCapabilities
    let audio: CoreMediaCapabilities
    let presets: [CorePreset]
}

struct CoreInspectedFile: Equatable, Sendable {
    let displayName: String
    let mediaKind: String
    let format: String
    let byteCount: Int64
    let relativePath: String
}

struct CoreInspection: Equatable, Sendable {
    let schemaVersion: Int
    let files: [CoreInspectedFile]
}

struct CoreConversionRequest: Sendable {
    let id: UUID
    let paths: [URL]
    let recursive: Bool
    let outputDirectory: URL
    let imageIntent: ImageIntent?
    let videoIntent: VideoIntent?
    let audioIntent: AudioIntent?
    let imagePresetID: String?
    let videoPresetID: String?

    init(
        id: UUID = UUID(),
        paths: [URL],
        recursive: Bool,
        outputDirectory: URL,
        imageIntent: ImageIntent? = nil,
        videoIntent: VideoIntent? = nil,
        audioIntent: AudioIntent? = nil,
        imagePresetID: String? = nil,
        videoPresetID: String? = nil
    ) {
        self.id = id
        self.paths = paths
        self.recursive = recursive
        self.outputDirectory = outputDirectory
        self.imageIntent = imageIntent
        self.videoIntent = videoIntent
        self.audioIntent = audioIntent
        self.imagePresetID = imagePresetID
        self.videoPresetID = videoPresetID
    }
}

struct CoreConversionResult: Equatable, Sendable {
    let requestID: UUID
    let outputURLs: [URL]
    let skippedCount: Int
    let failClosedCount: Int
}

protocol FileIslandCoreServing: Sendable {
    func capabilities() async throws -> CoreCapabilities
    func inspect(paths: [URL], recursive: Bool) async throws -> CoreInspection
    func convert(
        _ request: CoreConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> CoreConversionResult
    func cancel(requestID: UUID) async
}
