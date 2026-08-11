import Darwin
import Foundation
import UniformTypeIdentifiers

protocol VideoSplitSegmentDecodabilityChecking: Sendable {
    func canDecodeFirstFrame(at fileURL: URL) async throws -> Bool
}

/// Runs the AVFoundation decoder in a bounded child process. The potentially
/// blocking `copyNextSampleBuffer()` call never executes in the App or CLI
/// process, so timeout and cancellation can always terminate the helper.
struct AVFoundationVideoSplitSegmentDecodabilityChecker:
    VideoSplitSegmentDecodabilityChecking,
    Sendable
{
    private struct Response: Decodable {
        let decodable: Bool
        let schemaVersion: Int
    }

    private let helperExecutableURL: URL
    private let processRunner: any FFmpegProcessRunning
    private let fileValidator: any LocalRegularMediaFileValidating

    init(
        helperExecutableURL: URL,
        processRunner: any FFmpegProcessRunning = FoundationFFmpegProcessRunner(),
        fileValidator: any LocalRegularMediaFileValidating =
            POSIXLocalRegularMediaFileValidator()
    ) {
        self.helperExecutableURL = helperExecutableURL.standardizedFileURL
        self.processRunner = processRunner
        self.fileValidator = fileValidator
    }

    func canDecodeFirstFrame(at fileURL: URL) async throws -> Bool {
        try Task.checkCancellation()
        guard isTrustedHelperExecutable,
              (try? fileValidator.validate(fileURL, expectedByteCount: nil)) != nil else {
            return false
        }

        let output = MediaValidatorProcessOutput()
        let result: FFmpegProcessResult
        do {
            result = try await processRunner.run(
                jobID: UUID(),
                command: FFmpegCommand(
                    executableURL: helperExecutableURL,
                    arguments: ["--first-frame", fileURL.path]
                ),
                limits: .avFoundationMediaValidation
            ) { event in
                output.append(event)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as FFmpegProcessFailure {
            if failure == .cancelled {
                throw CancellationError()
            }
            return false
        } catch {
            return false
        }

        try Task.checkCancellation()
        guard result.exitCode == 0 else { return false }
        let response = try? JSONDecoder().decode(Response.self, from: output.standardOutput)
        return response?.schemaVersion == 1 && response?.decodable == true
    }

    private var isTrustedHelperExecutable: Bool {
        guard helperExecutableURL.isFileURL,
              helperExecutableURL.lastPathComponent == "FileIslandMediaValidator",
              (try? fileValidator.validate(
                  helperExecutableURL,
                  expectedByteCount: nil
              )) != nil else {
            return false
        }
        return access(helperExecutableURL.path, X_OK) == 0
    }
}

extension FFmpegProcessLimits {
    static let avFoundationMediaValidation = FFmpegProcessLimits(
        timeout: .seconds(15),
        inactivityTimeout: nil,
        terminationGracePeriod: .seconds(1),
        maximumStandardOutputBytes: 64 * 1_024,
        maximumStandardErrorBytes: 64 * 1_024
    )
}

private final class MediaValidatorProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()

    func append(_ event: FFmpegProcessEvent) {
        guard case let .standardOutput(data) = event else { return }
        lock.withLock { output.append(data) }
    }

    var standardOutput: Data {
        lock.withLock { output }
    }
}

/// Safe default for tests/custom coordinators that do not inject the packaged
/// helper. Production construction always provides the isolated checker.
private struct UnavailableVideoSplitSegmentDecodabilityChecker:
    VideoSplitSegmentDecodabilityChecking,
    Sendable
{
    func canDecodeFirstFrame(at _: URL) async throws -> Bool { false }
}

enum VideoSplitOutputValidationError: Error, Equatable, Sendable {
    case unsupportedPlan
    case invalidSource
    case invalidManifest
    case probeFailed(segmentIndex: Int)
    case stagedFileChanged(segmentIndex: Int)
    case containerMismatch(segmentIndex: Int)
    case videoCodecMismatch(segmentIndex: Int)
    case audioPresenceMismatch(segmentIndex: Int)
    case audioCodecMismatch(segmentIndex: Int)
    case audioTimingMismatch(segmentIndex: Int)
    case metadataNotRemoved(segmentIndex: Int)
    case orientationMismatch(segmentIndex: Int)
    case firstFrameNotIndependentlyDecodable(segmentIndex: Int)
    case exceedsMaximumBytes(
        segmentIndex: Int,
        actualBytes: Int64,
        maximumBytes: Int64
    )
    case exceedsMaximumDuration(
        segmentIndex: Int,
        actualDurationMilliseconds: Int64,
        maximumDurationMilliseconds: Int64,
        toleranceMilliseconds: Int64
    )
    case plannedDurationMismatch(
        segmentIndex: Int,
        actualDurationMilliseconds: Int64,
        plannedDurationMilliseconds: Int64,
        toleranceMilliseconds: Int64
    )
    case timelineCoverageMismatch(
        actualDurationMilliseconds: Int64,
        sourceDurationMilliseconds: Int64,
        toleranceMilliseconds: Int64
    )
}

struct ValidatedVideoSplitSegment: Equatable, Sendable {
    let index: Int
    let artifact: ValidatedOutputArtifact
    let actualFacts: VideoSplitSourceFacts
    let actualBytes: Int64
}

struct ValidatedVideoSplitOutput: Equatable, Sendable {
    let manifest: ValidatedOutputArtifactManifest
    let segments: [ValidatedVideoSplitSegment]

    var totalBytes: Int64 {
        segments.reduce(into: 0) { total, segment in
            let (sum, overflow) = total.addingReportingOverflow(segment.actualBytes)
            total = overflow ? Int64.max : sum
        }
    }
}

/// Validates the complete staged artifact set before any segment is published.
///
/// The manifest validator is deliberately run first so probing can never turn
/// an unplanned, duplicated, reordered-by-position, or unsafe staging path into
/// a publishable artifact. Probe failures are collapsed into path-free errors.
struct VideoSplitOutputValidator: Sendable {
    private let probe: any VideoSplitProbing
    private let decodabilityChecker: any VideoSplitSegmentDecodabilityChecking
    private let manifestValidator: OutputArtifactManifestValidator

    init(
        probe: any VideoSplitProbing,
        decodabilityChecker: any VideoSplitSegmentDecodabilityChecking =
            UnavailableVideoSplitSegmentDecodabilityChecker(),
        manifestValidator: OutputArtifactManifestValidator = OutputArtifactManifestValidator()
    ) {
        self.probe = probe
        self.decodabilityChecker = decodabilityChecker
        self.manifestValidator = manifestValidator
    }

    func validate(
        plan: VideoSplitPlan,
        source: VideoSplitSourceFacts,
        stagedArtifacts: [StagedOutputArtifact],
        stagingRoot: URL
    ) async throws -> ValidatedVideoSplitOutput {
        try Task.checkCancellation()
        let validatedSource = try validateAuditedPlan(plan, source: source)
        let plannedArtifacts = plan.segments.map { segment in
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: plan.input.id,
                    role: .videoSegment(
                        ordinal: segment.index,
                        total: plan.segments.count
                    )
                ),
                preferredRelativePath: segment.outputRelativePath
            )
        }

        let manifest: ValidatedOutputArtifactManifest
        do {
            manifest = try manifestValidator.validate(
                plannedArtifacts: plannedArtifacts,
                stagedArtifacts: stagedArtifacts,
                allowedSourceInputIDs: [plan.input.id],
                stagingRoot: stagingRoot
            )
        } catch {
            throw VideoSplitOutputValidationError.invalidManifest
        }

        let perSegmentTolerance = Self.perSegmentTolerance(
            frameDurationMilliseconds: validatedSource.frameDurationMilliseconds
        )
        var validatedSegments: [ValidatedVideoSplitSegment] = []
        validatedSegments.reserveCapacity(plan.segments.count)
        var totalActualDuration: Int64 = 0

        for (segment, artifact) in zip(plan.segments, manifest.entries) {
            try Task.checkCancellation()
            let actualBytes = try fileSize(
                at: artifact.stagedFileURL,
                segmentIndex: segment.index
            )
            if let maximumBytes = plan.intent.constraints.maxBytes,
               actualBytes > maximumBytes {
                throw VideoSplitOutputValidationError.exceedsMaximumBytes(
                    segmentIndex: segment.index,
                    actualBytes: actualBytes,
                    maximumBytes: maximumBytes
                )
            }

            let outputInput = InputFile(
                id: artifact.id.sourceInputID,
                url: artifact.stagedFileURL,
                type: Self.contentType(for: artifact.stagedFileURL),
                fileSize: actualBytes,
                displayName: artifact.preferredRelativePath.components.last ?? "segment"
            )
            let outputFacts: VideoSplitSourceFacts
            do {
                outputFacts = try await probe.probe(outputInput)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as VideoSplitProbeError where error == .probeCancelled {
                throw CancellationError()
            } catch {
                throw VideoSplitOutputValidationError.probeFailed(
                    segmentIndex: segment.index
                )
            }

            guard outputFacts.keyframeMilliseconds.first == 0 else {
                throw VideoSplitOutputValidationError.firstFrameNotIndependentlyDecodable(
                    segmentIndex: segment.index
                )
            }
            let validatedOutput: VideoSplitSourceFacts
            do {
                validatedOutput = try outputFacts.validated(
                    for: .fastKeyframeCopy,
                    matching: outputInput
                )
            } catch {
                throw VideoSplitOutputValidationError.probeFailed(
                    segmentIndex: segment.index
                )
            }
            guard Self.outputIdentity(validatedOutput.fileIdentity)
                    == artifact.fileIdentity else {
                throw VideoSplitOutputValidationError.stagedFileChanged(
                    segmentIndex: segment.index
                )
            }

            try validateMediaIdentity(
                validatedOutput,
                source: validatedSource,
                segmentIndex: segment.index
            )
            try validateAudioTiming(
                validatedOutput,
                segmentIndex: segment.index,
                toleranceMilliseconds: perSegmentTolerance
            )
            if plan.intent.stripMetadata,
               !validatedOutput.userMetadataKeys.isEmpty {
                throw VideoSplitOutputValidationError.metadataNotRemoved(
                    segmentIndex: segment.index
                )
            }
            do {
                guard try await decodabilityChecker.canDecodeFirstFrame(
                    at: artifact.stagedFileURL
                ) else {
                    throw VideoSplitOutputValidationError
                        .firstFrameNotIndependentlyDecodable(segmentIndex: segment.index)
                }
            } catch let error as VideoSplitOutputValidationError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw VideoSplitOutputValidationError.firstFrameNotIndependentlyDecodable(
                    segmentIndex: segment.index
                )
            }

            if let maximumDuration = plan.intent.constraints.maxDurationMilliseconds,
               Self.exceeds(
                   validatedOutput.durationMilliseconds,
                   maximum: maximumDuration,
                   tolerance: perSegmentTolerance
               ) {
                throw VideoSplitOutputValidationError.exceedsMaximumDuration(
                    segmentIndex: segment.index,
                    actualDurationMilliseconds: validatedOutput.durationMilliseconds,
                    maximumDurationMilliseconds: maximumDuration,
                    toleranceMilliseconds: perSegmentTolerance
                )
            }

            let plannedDuration = segment.endMilliseconds - segment.startMilliseconds
            guard Self.absoluteDifference(
                validatedOutput.durationMilliseconds,
                plannedDuration
            ) <= UInt64(perSegmentTolerance) else {
                throw VideoSplitOutputValidationError.plannedDurationMismatch(
                    segmentIndex: segment.index,
                    actualDurationMilliseconds: validatedOutput.durationMilliseconds,
                    plannedDurationMilliseconds: plannedDuration,
                    toleranceMilliseconds: perSegmentTolerance
                )
            }

            let (newTotal, overflow) = totalActualDuration.addingReportingOverflow(
                validatedOutput.durationMilliseconds
            )
            guard !overflow else {
                throw VideoSplitOutputValidationError.timelineCoverageMismatch(
                    actualDurationMilliseconds: totalActualDuration,
                    sourceDurationMilliseconds: validatedSource.durationMilliseconds,
                    toleranceMilliseconds: Self.totalCoverageTolerance(
                        segmentCount: plan.segments.count,
                        frameDurationMilliseconds: validatedSource.frameDurationMilliseconds
                    )
                )
            }
            totalActualDuration = newTotal
            validatedSegments.append(
                ValidatedVideoSplitSegment(
                    index: segment.index,
                    artifact: artifact,
                    actualFacts: validatedOutput,
                    actualBytes: actualBytes
                )
            )
        }

        let totalTolerance = Self.totalCoverageTolerance(
            segmentCount: plan.segments.count,
            frameDurationMilliseconds: validatedSource.frameDurationMilliseconds
        )
        guard Self.absoluteDifference(
            totalActualDuration,
            validatedSource.durationMilliseconds
        ) <= UInt64(totalTolerance) else {
            throw VideoSplitOutputValidationError.timelineCoverageMismatch(
                actualDurationMilliseconds: totalActualDuration,
                sourceDurationMilliseconds: validatedSource.durationMilliseconds,
                toleranceMilliseconds: totalTolerance
            )
        }

        return ValidatedVideoSplitOutput(
            manifest: manifest,
            segments: validatedSegments
        )
    }

    private func validateAuditedPlan(
        _ plan: VideoSplitPlan,
        source: VideoSplitSourceFacts
    ) throws -> VideoSplitSourceFacts {
        guard plan.input.kind == .video,
              plan.intent.mode == .fastKeyframeCopy,
              plan.intent.source == .custom,
              plan.ruleSnapshot == nil,
              !plan.segments.isEmpty,
              plan.segments.count <= 999,
              plan.segments.allSatisfy({ !$0.requiresReencoding }) else {
            throw VideoSplitOutputValidationError.unsupportedPlan
        }
        do {
            try VideoSplitDomainValidator.validate(plan: plan)
        } catch {
            throw VideoSplitOutputValidationError.unsupportedPlan
        }

        let validatedSource: VideoSplitSourceFacts
        do {
            validatedSource = try source.validated(
                for: .fastKeyframeCopy,
                matching: plan.input
            )
        } catch {
            throw VideoSplitOutputValidationError.invalidSource
        }

        guard Self.isAuditedContainer(validatedSource.container),
              validatedSource.videoCodec == "h264",
              validatedSource.audioCodec == nil || validatedSource.audioCodec == "aac",
              plan.segments.last?.endMilliseconds == validatedSource.durationMilliseconds,
              plan.segments.allSatisfy({ segment in
                  let pathExtension = URL(
                      fileURLWithPath: segment.outputRelativePath.string
                  ).pathExtension.lowercased()
                  return ["mp4", "mov"].contains(pathExtension)
                    && Self.canonicalContainer(pathExtension)
                        == Self.canonicalContainer(validatedSource.container)
              }),
              plan.intent.constraints.requiredContainer.map({
                  Self.canonicalContainer($0)
                    == Self.canonicalContainer(validatedSource.container)
              }) ?? true,
              plan.intent.constraints.requiredVideoCodec.map({ $0 == "h264" }) ?? true,
              plan.intent.constraints.requiredAudioCodec.map({ required in
                  validatedSource.audioCodec == required
              }) ?? true else {
            throw VideoSplitOutputValidationError.unsupportedPlan
        }
        return validatedSource
    }

    private func validateMediaIdentity(
        _ output: VideoSplitSourceFacts,
        source: VideoSplitSourceFacts,
        segmentIndex: Int
    ) throws {
        guard Self.canonicalContainer(output.container)
                == Self.canonicalContainer(source.container) else {
            throw VideoSplitOutputValidationError.containerMismatch(
                segmentIndex: segmentIndex
            )
        }
        guard output.videoCodec == source.videoCodec else {
            throw VideoSplitOutputValidationError.videoCodecMismatch(
                segmentIndex: segmentIndex
            )
        }
        guard (output.audioCodec == nil) == (source.audioCodec == nil) else {
            throw VideoSplitOutputValidationError.audioPresenceMismatch(
                segmentIndex: segmentIndex
            )
        }
        guard output.audioCodec == source.audioCodec else {
            throw VideoSplitOutputValidationError.audioCodecMismatch(
                segmentIndex: segmentIndex
            )
        }
        guard output.displayWidth == source.displayWidth,
              output.displayHeight == source.displayHeight,
              output.rotationDegrees == source.rotationDegrees else {
            throw VideoSplitOutputValidationError.orientationMismatch(
                segmentIndex: segmentIndex
            )
        }
    }

    private func fileSize(at url: URL, segmentIndex: Int) throws -> Int64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values.fileSize, fileSize > 0 else {
                throw VideoSplitOutputValidationError.invalidManifest
            }
            return Int64(fileSize)
        } catch let error as VideoSplitOutputValidationError {
            throw error
        } catch {
            throw VideoSplitOutputValidationError.probeFailed(segmentIndex: segmentIndex)
        }
    }

    private func validateAudioTiming(
        _ output: VideoSplitSourceFacts,
        segmentIndex: Int,
        toleranceMilliseconds: Int64
    ) throws {
        guard output.audioCodec != nil else { return }
        guard let audioStart = output.audioStartMilliseconds,
              let audioDuration = output.audioDurationMilliseconds else {
            throw VideoSplitOutputValidationError.audioTimingMismatch(
                segmentIndex: segmentIndex
            )
        }
        let timingTolerance = max(250, toleranceMilliseconds * 2)
        guard Self.absoluteDifference(
            audioStart,
            output.videoStartMilliseconds
        ) <= UInt64(timingTolerance),
        Self.absoluteDifference(
            audioDuration,
            output.durationMilliseconds
        ) <= UInt64(timingTolerance) else {
            throw VideoSplitOutputValidationError.audioTimingMismatch(
                segmentIndex: segmentIndex
            )
        }
    }

    private static func contentType(for url: URL) -> UTType? {
        switch canonicalContainer(url.pathExtension.lowercased()) {
        case "mp4": .mpeg4Movie
        case "mov": .quickTimeMovie
        default: nil
        }
    }

    private static func outputIdentity(
        _ identity: VideoSplitFileIdentity
    ) -> OutputArtifactFileIdentity {
        OutputArtifactFileIdentity(
            device: identity.device,
            inode: identity.inode,
            byteCount: identity.byteCount,
            modificationSeconds: identity.modificationSeconds,
            modificationNanoseconds: identity.modificationNanoseconds
        )
    }

    private static func canonicalContainer(_ value: String) -> String? {
        switch value.lowercased() {
        case "mp4", "m4v": "mp4"
        case "mov", "quicktime": "mov"
        default: nil
        }
    }

    private static func isAuditedContainer(_ value: String) -> Bool {
        switch value.lowercased() {
        case "mp4", "mov", "quicktime": true
        default: false
        }
    }

    private static func perSegmentTolerance(
        frameDurationMilliseconds: Double
    ) -> Int64 {
        max(100, Int64(ceil(frameDurationMilliseconds)))
    }

    private static func totalCoverageTolerance(
        segmentCount: Int,
        frameDurationMilliseconds: Double
    ) -> Int64 {
        let frameBudget = ceil(Double(segmentCount) * frameDurationMilliseconds)
        return max(500, Int64(frameBudget))
    }

    private static func exceeds(
        _ actual: Int64,
        maximum: Int64,
        tolerance: Int64
    ) -> Bool {
        let (ceiling, overflow) = maximum.addingReportingOverflow(tolerance)
        return !overflow && actual > ceiling
    }

    private static func absoluteDifference(_ lhs: Int64, _ rhs: Int64) -> UInt64 {
        if (lhs < 0) == (rhs < 0) {
            return lhs.magnitude >= rhs.magnitude
                ? lhs.magnitude - rhs.magnitude
                : rhs.magnitude - lhs.magnitude
        }
        return lhs.magnitude + rhs.magnitude
    }
}
