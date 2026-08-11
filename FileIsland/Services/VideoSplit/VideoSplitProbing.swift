import Foundation

protocol VideoSplitProbing: Sendable {
    /// Implementations are responsible for proving that the URL is a local,
    /// readable ordinary file and not a symbolic link before returning facts.
    /// The returned identity is checked again by the planner.
    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts
}

enum VideoSplitProbeError: Error, Equatable, Sendable {
    case notLocalFile
    case symbolicLink
    case notRegularFile
    case unreadableFile
    case fileChangedDuringProbe
    case probeUnavailable
    case probeCancelled
    case probeTimedOut
    case probeOutputLimitExceeded
    case probeProcessFailed
    case malformedProbeOutput
    case unsupportedMedia
    case invalidDuration
    case invalidDisplayDimensions
    case invalidDisplayRotation
    case invalidAverageBitrate
    case invalidFrameDuration
    case invalidMediaIdentity
    case invalidKeyframeTimeline
    case inputIdentityMismatch
}

struct VideoSplitSourceFacts: Codable, Equatable, Sendable {
    static let maximumDurationMilliseconds: Int64 = 24 * 60 * 60 * 1_000

    let inputID: UUID
    let sourceURL: URL
    let fileIdentity: VideoSplitFileIdentity
    let durationMilliseconds: Int64
    let displayWidth: Int
    let displayHeight: Int
    /// Display-matrix rotation normalized to one of the four right-angle
    /// quadrants. Keeping this alongside the rotation-aware display size lets
    /// validation distinguish 0° from 180° and 90° from 270°.
    let rotationDegrees: Int
    let averageBitrateBitsPerSecond: Int64
    let container: String
    let videoCodec: String
    let audioCodec: String?
    let videoStartMilliseconds: Int64
    let audioStartMilliseconds: Int64?
    let audioDurationMilliseconds: Int64?
    let userMetadataKeys: Set<String>
    let frameDurationMilliseconds: Double
    /// Only independently decodable cut points belong in this timeline.
    let keyframeMilliseconds: [Int64]

    init(
        inputID: UUID,
        sourceURL: URL,
        fileIdentity: VideoSplitFileIdentity,
        durationMilliseconds: Int64,
        displayWidth: Int,
        displayHeight: Int,
        rotationDegrees: Int = 0,
        averageBitrateBitsPerSecond: Int64,
        container: String,
        videoCodec: String,
        audioCodec: String?,
        videoStartMilliseconds: Int64,
        audioStartMilliseconds: Int64?,
        audioDurationMilliseconds: Int64?,
        userMetadataKeys: Set<String>,
        frameDurationMilliseconds: Double,
        keyframeMilliseconds: [Int64]
    ) {
        self.inputID = inputID
        self.sourceURL = sourceURL
        self.fileIdentity = fileIdentity
        self.durationMilliseconds = durationMilliseconds
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.rotationDegrees = rotationDegrees
        self.averageBitrateBitsPerSecond = averageBitrateBitsPerSecond
        self.container = container
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.videoStartMilliseconds = videoStartMilliseconds
        self.audioStartMilliseconds = audioStartMilliseconds
        self.audioDurationMilliseconds = audioDurationMilliseconds
        self.userMetadataKeys = userMetadataKeys
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.keyframeMilliseconds = keyframeMilliseconds
    }

    func validated(
        for mode: VideoSplitMode,
        matching input: InputFile
    ) throws -> Self {
        guard input.url.isFileURL,
              sourceURL.isFileURL,
              inputID == input.id,
              fileIdentity.byteCount == input.fileSize,
              sourceURL.standardizedFileURL == input.url.standardizedFileURL else {
            throw VideoSplitProbeError.inputIdentityMismatch
        }
        return try validated(for: mode)
    }

    func validated(for mode: VideoSplitMode) throws -> Self {
        guard durationMilliseconds > 0,
              durationMilliseconds <= Self.maximumDurationMilliseconds else {
            throw VideoSplitProbeError.invalidDuration
        }
        guard displayWidth > 0, displayHeight > 0 else {
            throw VideoSplitProbeError.invalidDisplayDimensions
        }
        guard [0, 90, 180, 270].contains(rotationDegrees) else {
            throw VideoSplitProbeError.invalidDisplayRotation
        }
        guard averageBitrateBitsPerSecond > 0 else {
            throw VideoSplitProbeError.invalidAverageBitrate
        }
        guard fileIdentity.byteCount > 0,
              fileIdentity.modificationNanoseconds >= 0,
              fileIdentity.modificationNanoseconds < 1_000_000_000 else {
            throw VideoSplitProbeError.invalidMediaIdentity
        }
        if let audioCodec {
            guard !audioCodec.isEmpty,
                  let audioStartMilliseconds,
                  let audioDurationMilliseconds,
                  audioDurationMilliseconds > 0,
                  Self.safeAbsoluteDifference(
                      audioStartMilliseconds,
                      videoStartMilliseconds
                  ) <= 1_000 else {
                throw VideoSplitProbeError.invalidMediaIdentity
            }
        } else if audioStartMilliseconds != nil || audioDurationMilliseconds != nil {
            throw VideoSplitProbeError.invalidMediaIdentity
        }
        guard frameDurationMilliseconds.isFinite,
              frameDurationMilliseconds > 0,
              frameDurationMilliseconds <= Double(durationMilliseconds) else {
            throw VideoSplitProbeError.invalidFrameDuration
        }
        guard Self.filenameExtension(forContainer: container) != nil,
              Self.isSafeMediaToken(videoCodec),
              audioCodec.map(Self.isSafeMediaToken) ?? true else {
            throw VideoSplitProbeError.invalidMediaIdentity
        }

        guard keyframeMilliseconds.first == 0,
              keyframeMilliseconds.allSatisfy({
                  $0 >= 0 && $0 < durationMilliseconds
              }),
              zip(keyframeMilliseconds, keyframeMilliseconds.dropFirst())
                .allSatisfy({ $0.0 < $0.1 }) else {
            throw VideoSplitProbeError.invalidKeyframeTimeline
        }
        return self
    }

    static func filenameExtension(forContainer container: String) -> String? {
        switch container {
        case "mp4": "mp4"
        case "mov", "quicktime": "mov"
        case "m4v": "m4v"
        case "matroska", "mkv": "mkv"
        case "webm": "webm"
        case "avi": "avi"
        case "mpeg", "mpegps": "mpeg"
        case "mpegts", "ts": "ts"
        case "flv": "flv"
        case "3gp": "3gp"
        case "asf", "wmv": "wmv"
        default: nil
        }
    }

    private static func isSafeMediaToken(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.lowercased()
            && value.contains(where: { $0.isLetter || $0.isNumber })
            && value.allSatisfy { character in
                character.isASCII
                    && (character.isLetter
                        || character.isNumber
                        || character == "-"
                        || character == "_")
            }
    }

    private static func safeAbsoluteDifference(_ lhs: Int64, _ rhs: Int64) -> UInt64 {
        lhs.magnitude >= rhs.magnitude && (lhs < 0) == (rhs < 0)
            ? lhs.magnitude - rhs.magnitude
            : lhs < 0 && rhs >= 0 || rhs < 0 && lhs >= 0
                ? lhs.magnitude + rhs.magnitude
                : rhs.magnitude - lhs.magnitude
    }
}
