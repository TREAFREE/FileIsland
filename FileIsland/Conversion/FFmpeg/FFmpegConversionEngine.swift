import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import VideoToolbox

actor FFmpegConversionEngine: ConversionEngine {
    private let executableURL: URL?
    private let processRunner: any FFmpegProcessRunning
    private let commandBuilder: FFmpegCommandBuilder
    private let outputURLProvider: SafeOutputURLProvider
    private var activeJobIDs: Set<UUID> = []
    private var cancelledJobIDs: Set<UUID> = []
    private var isExecutableValidated = false

    init(
        executableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
        processRunner: any FFmpegProcessRunning = FoundationFFmpegProcessRunner(),
        commandBuilder: FFmpegCommandBuilder = FFmpegCommandBuilder(),
        outputURLProvider: SafeOutputURLProvider = SafeOutputURLProvider()
    ) {
        self.executableURL = executableURL
        self.processRunner = processRunner
        self.commandBuilder = commandBuilder
        self.outputURLProvider = outputURLProvider
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool {
        Self.intent(for: plan) != nil
    }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        guard Self.intent(for: plan) != nil else {
            throw ConversionError.unsupportedInput
        }
        guard let executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ConversionError.engineUnavailable
        }
        guard cancelledJobIDs.remove(plan.id) == nil else {
            throw ConversionError.cancelled
        }

        activeJobIDs.insert(plan.id)
        defer { activeJobIDs.remove(plan.id) }
        do {
            try await validateExecutableIfNeeded(
                executableURL: executableURL,
                jobID: plan.id
            )
            return try await Self.perform(
                plan,
                executableURL: executableURL,
                processRunner: processRunner,
                commandBuilder: commandBuilder,
                outputURLProvider: outputURLProvider,
                progress: progress
            )
        } catch let error as ConversionError {
            throw error
        } catch is CancellationError {
            throw ConversionError.cancelled
        } catch {
            throw ConversionError.conversionFailed(
                underlying: "The fallback video conversion failed."
            )
        }
    }

    private func validateExecutableIfNeeded(
        executableURL: URL,
        jobID: UUID
    ) async throws {
        guard !isExecutableValidated else { return }

        let collector = FFmpegVersionOutputCollector()
        let result: FFmpegProcessResult
        do {
            result = try await processRunner.run(
                jobID: jobID,
                command: FFmpegCommand(
                    executableURL: executableURL,
                    arguments: ["-version"]
                ),
                eventHandler: collector.consume
            )
        } catch let error as ConversionError where error == .cancelled {
            throw error
        } catch is CancellationError {
            throw ConversionError.cancelled
        } catch {
            throw ConversionError.engineUnavailable
        }

        let output = collector.text
        guard result.exitCode == 0,
              output.contains("ffmpeg version 8.1.2"),
              output.contains("--disable-network"),
              !output.contains("--enable-gpl"),
              !output.contains("--enable-nonfree") else {
            throw ConversionError.engineUnavailable
        }
        isExecutableValidated = true
    }

    func cancel(jobID: UUID) async {
        if activeJobIDs.contains(jobID) {
            await processRunner.cancel(jobID: jobID)
        } else {
            cancelledJobIDs.insert(jobID)
        }
    }

    private nonisolated static func perform(
        _ plan: ConversionPlan,
        executableURL: URL,
        processRunner: any FFmpegProcessRunning,
        commandBuilder: FFmpegCommandBuilder,
        outputURLProvider: SafeOutputURLProvider,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        guard let intent = intent(for: plan) else {
            throw ConversionError.unsupportedInput
        }
        var completedOutputs: [URL] = []
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
                try await convert(
                    plan: plan,
                    input: input,
                    outputURL: outputURL,
                    intent: intent,
                    executableURL: executableURL,
                    processRunner: processRunner,
                    commandBuilder: commandBuilder,
                    batchIndex: index,
                    batchCount: plan.inputs.count,
                    progress: progress
                )
                completedOutputs.append(outputURL)
                progress(Double(index + 1) / Double(plan.inputs.count))
            }
            return completedOutputs
        } catch {
            for output in completedOutputs {
                try? FileManager.default.removeItem(at: output)
            }
            throw error
        }
    }

    private nonisolated static func convert(
        plan: ConversionPlan,
        input: InputFile,
        outputURL: URL,
        intent: VideoIntent,
        executableURL: URL,
        processRunner: any FFmpegProcessRunning,
        commandBuilder: FFmpegCommandBuilder,
        batchIndex: Int,
        batchCount: Int,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let accessed = input.url.startAccessingSecurityScopedResource()
        defer {
            if accessed { input.url.stopAccessingSecurityScopedResource() }
        }

        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".fileisland-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let command = try commandBuilder.makeCommand(
            plan: plan,
            input: input,
            outputURL: temporaryURL,
            executableURL: executableURL
        )
        let monitor = FFmpegExecutionMonitor(
            sensitivePaths: [input.url.path, temporaryURL.path, outputURL.path],
            batchIndex: batchIndex,
            batchCount: batchCount,
            progress: progress
        )

        let result = try await processRunner.run(
            jobID: plan.id,
            command: command,
            eventHandler: monitor.consume
        )
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw ConversionError.conversionFailed(
                underlying: monitor.diagnostic.isEmpty
                    ? "FFmpeg exited with code \(result.exitCode)."
                    : monitor.diagnostic
            )
        }

        try await validate(
            outputURL: temporaryURL,
            source: monitor.metadata,
            resolution: intent.maxResolution ?? .source
        )
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw ConversionError.permissionDenied
        } catch {
            throw ConversionError.conversionFailed(
                underlying: "The converted video could not be saved."
            )
        }
    }

    private nonisolated static func validate(
        outputURL: URL,
        source: FFmpegSourceMetadata,
        resolution: VideoResolution
    ) async throws {
        guard let sourceDuration = source.duration,
              let sourceSize = source.orientedDisplaySize else {
            throw ConversionError.invalidMedia
        }
        let fileSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let asset = AVURLAsset(url: outputURL)
        let isPlayable = try await asset.load(.isPlayable)
        let outputDuration = try await asset.load(.duration).seconds
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ConversionError.conversionFailed(underlying: "The output has no video track.")
        }
        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        let videoCodec = videoDescriptions.first.map(CMFormatDescriptionGetMediaSubType)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let outputSize = CGRect(origin: .zero, size: naturalSize)
            .applying(transform)
            .standardized
            .size
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let audioDescriptions = try await audioTrack?.load(.formatDescriptions) ?? []
        let audioCodec = audioDescriptions.first.map(CMFormatDescriptionGetMediaSubType)
        let ceiling: CGFloat = switch resolution {
        case .source: 3_840
        case .p1080: 1_920
        case .p720: 1_280
        }

        guard fileSize > 0,
              isPlayable,
              videoCodec == kCMVideoCodecType_H264,
              !source.hasAudio || audioCodec == kAudioFormatMPEG4AAC,
              abs(outputDuration - sourceDuration) <= 0.12,
              outputSize.width > 0,
              outputSize.height > 0,
              max(outputSize.width, outputSize.height) <= ceiling + 1,
              max(outputSize.width, outputSize.height) <= max(sourceSize.width, sourceSize.height) + 1,
              orientation(of: outputSize) == orientation(of: sourceSize) else {
            throw ConversionError.conversionFailed(
                underlying: "The converted video failed validation."
            )
        }
    }

    private nonisolated static func intent(for plan: ConversionPlan) -> VideoIntent? {
        guard !plan.inputs.isEmpty,
              plan.steps.count == 1,
              case let .video(intent) = plan.steps[0],
              intent.compatibility == .highCompatibility,
              intent.maxResolution != nil,
              intent.targetBytes == nil,
              MediaConversionMatrix.videoBackend(for: plan.inputs.map(\.format)) == .ffmpegFallback else {
            return nil
        }
        return intent
    }

    private nonisolated static func orientation(of size: CGSize) -> VideoOrientation {
        if abs(size.width - size.height) < 1 { return .square }
        return size.width > size.height ? .landscape : .portrait
    }
}

private enum VideoOrientation: Sendable {
    case landscape
    case portrait
    case square
}

private final class FFmpegVersionOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maximumBytes = 64 * 1_024

    func consume(_ event: FFmpegProcessEvent) {
        let chunk: Data = switch event {
        case let .standardOutput(data), let .standardError(data): data
        }
        lock.withLock {
            let remaining = max(0, maximumBytes - data.count)
            data.append(chunk.prefix(remaining))
        }
    }

    var text: String {
        lock.withLock { String(decoding: data, as: UTF8.self) }
    }
}
