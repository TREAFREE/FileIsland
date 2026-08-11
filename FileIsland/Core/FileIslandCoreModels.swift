import Foundation

enum FileIslandCoreError: Error, Equatable, Sendable {
    case recursiveRequired
    case missingImageConfiguration
    case missingVideoConfiguration
    case missingAudioConfiguration
    case conflictingConfiguration
    case presetNotApplicable(String)
    case unsupportedInput
    case splitRuntimeUnavailable
    case invalidSplitConfiguration
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

struct CoreVideoSplitConstraintCapabilities: Equatable, Sendable {
    let supported: [String]
    let requiresAtLeastOne: Bool
    let decimalMegabyteBytes: Int64
    let durationUnit: String
    let durationPrecisionMilliseconds: Int64
}

struct CoreVideoSplitCapabilities: Equatable, Sendable {
    let constraintSources: [String]
    let modes: [String]
    let inputContainers: [String]
    let videoCodecs: [String]
    let audioCodecs: [String]
    let allowsNoAudio: Bool
    let customConstraints: CoreVideoSplitConstraintCapabilities
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
    let videoSplit: CoreVideoSplitCapabilities?

    init(
        schemaVersion: Int,
        image: CoreMediaCapabilities,
        video: CoreVideoCapabilities,
        audio: CoreMediaCapabilities,
        presets: [CorePreset],
        videoSplit: CoreVideoSplitCapabilities? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.image = image
        self.video = video
        self.audio = audio
        self.presets = presets
        self.videoSplit = videoSplit
    }
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

struct CoreVideoSplitRequest: Sendable {
    let id: UUID
    let paths: [URL]
    let recursive: Bool
    let outputDirectory: URL
    let maxBytes: Int64?
    let maxDurationMilliseconds: Int64?
    let mode: VideoSplitMode
    let stripMetadata: Bool

    init(
        id: UUID = UUID(),
        paths: [URL],
        recursive: Bool,
        outputDirectory: URL,
        maxBytes: Int64?,
        maxDurationMilliseconds: Int64?,
        mode: VideoSplitMode = .fastKeyframeCopy,
        stripMetadata: Bool = false
    ) {
        self.id = id
        self.paths = paths
        self.recursive = recursive
        self.outputDirectory = outputDirectory
        self.maxBytes = maxBytes
        self.maxDurationMilliseconds = maxDurationMilliseconds
        self.mode = mode
        self.stripMetadata = stripMetadata
    }
}

struct CoreVideoSplitPlanEvent: Equatable, Sendable {
    let requestID: UUID
    let inputOrdinal: Int
    let totalInputs: Int
    let displayName: String
    let segmentRelativePaths: [SafeRelativePath]
}

struct CoreVideoSplitValidationEvent: Equatable, Sendable {
    let requestID: UUID
    let segmentCount: Int
}

struct CoreVideoSplitPublicationEvent: Equatable, Sendable {
    let requestID: UUID
    let outputURLs: [URL]
}

enum CoreVideoSplitEvent: Equatable, Sendable {
    case plan(CoreVideoSplitPlanEvent)
    case segment(VideoSplitBatchProgress)
    case validation(CoreVideoSplitValidationEvent)
    case publication(CoreVideoSplitPublicationEvent)
    case rollback(requestID: UUID)
}

struct CoreVideoSplitResult: Equatable, Sendable {
    let requestID: UUID
    let outputURLs: [URL]
    let segmentCount: Int
    let totalBytes: Int64
}

protocol FileIslandCoreServing: Sendable {
    func capabilities() async throws -> CoreCapabilities
    func inspect(paths: [URL], recursive: Bool) async throws -> CoreInspection
    func convert(
        _ request: CoreConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> CoreConversionResult
    func split(
        _ request: CoreVideoSplitRequest,
        event: @Sendable @escaping (CoreVideoSplitEvent) -> Void
    ) async throws -> CoreVideoSplitResult
    func cancel(requestID: UUID) async
}

extension FileIslandCoreServing {
    func split(
        _ request: CoreVideoSplitRequest,
        event: @Sendable @escaping (CoreVideoSplitEvent) -> Void
    ) async throws -> CoreVideoSplitResult {
        throw FileIslandCoreError.splitRuntimeUnavailable
    }
}
