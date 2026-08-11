@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import VideoToolbox

actor NativeVideoConversionEngine: ConversionEngine {
    private let outputURLProvider: SafeOutputURLProvider
    private var activeJobs: [UUID: Task<EngineExecutionResult, Error>] = [:]
    private var cancelledJobIDs: Set<UUID> = []

    init(outputURLProvider: SafeOutputURLProvider = SafeOutputURLProvider()) {
        self.outputURLProvider = outputURLProvider
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool {
        Self.intent(for: plan) != nil
    }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult {
        guard Self.intent(for: plan) != nil else {
            throw ConversionError.unsupportedInput
        }
        guard cancelledJobIDs.remove(plan.id) == nil else {
            throw ConversionError.cancelled
        }

        let task = Task.detached(priority: .userInitiated) { [outputURLProvider] in
            try await Self.perform(
                plan,
                outputURLProvider: outputURLProvider,
                progress: progress
            )
        }
        activeJobs[plan.id] = task
        defer { activeJobs[plan.id] = nil }

        do {
            return try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch {
            throw Self.map(error)
        }
    }

    func cancel(jobID: UUID) async {
        if let task = activeJobs[jobID] {
            task.cancel()
        } else {
            cancelledJobIDs.insert(jobID)
        }
    }

    private nonisolated static func perform(
        _ plan: ConversionPlan,
        outputURLProvider: SafeOutputURLProvider,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult {
        guard let intent = intent(for: plan) else {
            throw ConversionError.unsupportedInput
        }

        var completedArtifacts: [StagedOutputArtifact] = []
        var reservedOutputs: Set<URL> = []
        progress(0)

        do {
            for (index, input) in plan.inputs.enumerated() {
                try Task.checkCancellation()
                let outputURL = try outputURLProvider.outputURL(
                    for: input.url,
                    filenameExtension: "mp4",
                    policy: plan.outputPolicy,
                    reserved: reservedOutputs
                )
                reservedOutputs.insert(outputURL)

                try await export(
                    inputURL: input.url,
                    outputURL: outputURL,
                    resolution: intent.maxResolution ?? .source,
                    targetBytes: intent.targetBytes,
                    batchIndex: index,
                    batchCount: plan.inputs.count,
                    progress: progress
                )
                completedArtifacts.append(
                    StagedOutputArtifact(
                        id: OutputArtifactID(
                            sourceInputID: input.id,
                            role: .converted
                        ),
                        fileURL: outputURL
                    )
                )
                progress(Double(index + 1) / Double(plan.inputs.count))
            }
            return EngineExecutionResult(artifacts: completedArtifacts)
        } catch {
            for artifact in completedArtifacts {
                try? FileManager.default.removeItem(at: artifact.fileURL)
            }
            throw error
        }
    }

    private nonisolated static func export(
        inputURL: URL,
        outputURL: URL,
        resolution: VideoResolution,
        targetBytes: Int64?,
        batchIndex: Int,
        batchCount: Int,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let accessed = inputURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { inputURL.stopAccessingSecurityScopedResource() }
        }

        let sourceAsset = AVURLAsset(url: inputURL)
        let sourceInfo = try await mediaInfo(for: sourceAsset)
        guard sourceInfo.isPlayable, sourceInfo.videoCodec != nil else {
            throw ConversionError.invalidMedia
        }
        let attempts = try exportAttempts(
            resolution: resolution,
            targetBytes: targetBytes,
            sourceInfo: sourceInfo
        )

        for (attemptIndex, attempt) in attempts.enumerated() {
            try Task.checkCancellation()
            let temporaryURL = outputURL.deletingLastPathComponent()
                .appendingPathComponent(".fileisland-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            do {
                let exporter = try VideoExportSessionController(
                    inputURL: inputURL,
                    presetName: attempt.presetName,
                    fileLengthLimit: attempt.fileLengthLimit
                )
                try await exporter.export(to: temporaryURL) { itemProgress in
                    let attemptProgress = (
                        Double(attemptIndex) + itemProgress.clamped(to: 0...1)
                    ) / Double(attempts.count)
                    progress((Double(batchIndex) + attemptProgress) / Double(batchCount))
                }
                try Task.checkCancellation()

                let outputAsset = AVURLAsset(url: temporaryURL)
                let outputInfo = try await mediaInfo(for: outputAsset)
                try validate(
                    source: sourceInfo,
                    output: outputInfo,
                    url: temporaryURL,
                    targetBytes: targetBytes
                )

                do {
                    try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
                    return
                } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                    throw ConversionError.permissionDenied
                } catch {
                    throw ConversionError.conversionFailed(
                        underlying: "The video output could not be saved."
                    )
                }
            } catch is CancellationError {
                throw ConversionError.cancelled
            } catch let error as ConversionError where error == .permissionDenied {
                throw error
            } catch {
                guard targetBytes != nil else {
                    if let conversionError = error as? ConversionError {
                        throw conversionError
                    }
                    throw ConversionError.conversionFailed(
                        underlying: "The native video export failed."
                    )
                }
                let attemptBoundary = Double(attemptIndex + 1) / Double(attempts.count)
                progress((Double(batchIndex) + attemptBoundary) / Double(batchCount))
            }
        }

        throw ConversionError.targetSizeUnreachable
    }

    private nonisolated static func mediaInfo(for asset: AVAsset) async throws -> VideoMediaInfo {
        do {
            let duration = try await asset.load(.duration)
            let playable = try await asset.load(.isPlayable)
            guard duration.isNumeric,
                  duration.seconds.isFinite,
                  duration.seconds > 0,
                  let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw ConversionError.invalidMedia
            }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let transform = try await videoTrack.load(.preferredTransform)
            let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
            let displaySize = CGRect(origin: .zero, size: naturalSize)
                .applying(transform)
                .standardized
                .size
            let videoCodec = try await codec(of: videoTrack)
            let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
            let audioCodec: FourCharCode?
            if let audioTrack {
                audioCodec = try await codec(of: audioTrack)
            } else {
                audioCodec = nil
            }
            return VideoMediaInfo(
                duration: duration.seconds,
                nominalFrameRate: nominalFrameRate,
                displaySize: displaySize,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                hasAudio: audioTrack != nil,
                isPlayable: playable
            )
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.invalidMedia
        }
    }

    private nonisolated static func codec(of track: AVAssetTrack) async throws -> FourCharCode? {
        let descriptions = try await track.load(.formatDescriptions)
        return descriptions.first.map(CMFormatDescriptionGetMediaSubType)
    }

    private nonisolated static func validate(
        source: VideoMediaInfo,
        output: VideoMediaInfo,
        url: URL,
        targetBytes: Int64? = nil
    ) throws {
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let singleFrameTolerance = source.nominalFrameRate > 0
            ? 1 / Double(source.nominalFrameRate)
            : 0
        let durationTolerance = max(0.1, singleFrameTolerance)

        guard fileSize > 0,
              output.isPlayable,
              output.videoCodec == kCMVideoCodecType_H264,
              !source.hasAudio || output.audioCodec == kAudioFormatMPEG4AAC,
              abs(output.duration - source.duration) <= durationTolerance,
              output.displaySize.width > 0,
              output.displaySize.height > 0,
              targetBytes.map({ Int64(fileSize) <= $0 }) ?? true,
              orientation(of: output.displaySize) == orientation(of: source.displaySize) else {
            throw ConversionError.conversionFailed(underlying: "The exported video failed validation.")
        }
    }

    private nonisolated static func exportAttempts(
        resolution: VideoResolution,
        targetBytes: Int64?,
        sourceInfo: VideoMediaInfo
    ) throws -> [VideoExportAttempt] {
        guard let targetBytes else {
            return [
                VideoExportAttempt(
                    presetName: try presetName(
                        for: resolution,
                        displaySize: sourceInfo.displaySize
                    ),
                    fileLengthLimit: nil
                )
            ]
        }

        let targetPlan = try VideoTargetSizePlanner().makePlan(
            targetBytes: targetBytes,
            duration: sourceInfo.duration,
            hasAudio: sourceInfo.hasAudio,
            sourceDisplaySize: sourceInfo.displaySize,
            requestedResolution: resolution
        )
        return targetPlan.exportTiers.map {
            VideoExportAttempt(
                presetName: presetName(for: $0),
                fileLengthLimit: targetPlan.fileLengthLimit
            )
        }
    }

    private nonisolated static func presetName(for tier: VideoExportTier) -> String {
        switch tier {
        case .p2160: AVAssetExportPreset3840x2160
        case .p1080: AVAssetExportPreset1920x1080
        case .p720: AVAssetExportPreset1280x720
        case .p540: AVAssetExportPreset960x540
        case .p480: AVAssetExportPreset640x480
        }
    }

    private nonisolated static func presetName(
        for resolution: VideoResolution,
        displaySize: CGSize
    ) throws -> String {
        switch resolution {
        case .p720:
            AVAssetExportPreset1280x720
        case .p1080:
            AVAssetExportPreset1920x1080
        case .source:
            switch max(displaySize.width, displaySize.height) {
            case ...1280:
                AVAssetExportPreset1280x720
            case ...1920:
                AVAssetExportPreset1920x1080
            case ...3840:
                AVAssetExportPreset3840x2160
            default:
                throw ConversionError.unsupportedInput
            }
        }
    }

    private nonisolated static func orientation(of size: CGSize) -> VideoOrientation {
        if abs(size.width - size.height) < 1 { return .square }
        return size.width > size.height ? .landscape : .portrait
    }

    private nonisolated static func intent(for plan: ConversionPlan) -> VideoIntent? {
        guard !plan.inputs.isEmpty,
              plan.steps.count == 1,
              case let .video(intent) = plan.steps[0],
              intent.compatibility == .highCompatibility,
              intent.maxResolution != nil,
              intent.targetBytes.map({ $0 > 0 }) ?? true,
              MediaConversionMatrix.videoBackend(for: plan.inputs.map(\.format)) == .native else {
            return nil
        }
        return intent
    }

    private nonisolated static func map(_ error: Error) -> ConversionError {
        if let conversionError = error as? ConversionError { return conversionError }
        if error is CancellationError { return .cancelled }
        return .conversionFailed(underlying: "The native video conversion failed.")
    }
}

private struct VideoExportAttempt: Sendable {
    let presetName: String
    let fileLengthLimit: Int64?
}

private struct VideoMediaInfo: Sendable {
    let duration: Double
    let nominalFrameRate: Float
    let displaySize: CGSize
    let videoCodec: FourCharCode?
    let audioCodec: FourCharCode?
    let hasAudio: Bool
    let isPlayable: Bool
}

private enum VideoOrientation: Sendable {
    case landscape
    case portrait
    case square
}

private actor VideoExportSessionController {
    private let exporter: AVAssetExportSession

    init(inputURL: URL, presetName: String, fileLengthLimit: Int64?) throws {
        let asset = AVURLAsset(url: inputURL)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw ConversionError.engineUnavailable
        }
        exporter.shouldOptimizeForNetworkUse = true
        if let fileLengthLimit {
            exporter.fileLengthLimit = fileLengthLimit
        }
        self.exporter = exporter
    }

    func export(
        to outputURL: URL,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let monitor = Task { [weak self] in
            await self?.monitorProgress(progress: progress)
        }
        defer { monitor.cancel() }
        try await exporter.export(to: outputURL, as: .mp4)
    }

    private func monitorProgress(
        progress: @Sendable (Double) -> Void
    ) async {
        for await state in exporter.states(updateInterval: 0.05) {
            guard !Task.isCancelled else { return }
            if case let .exporting(exportProgress) = state {
                let itemProgress = min(max(exportProgress.fractionCompleted, 0), 1)
                progress(itemProgress)
            }
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
