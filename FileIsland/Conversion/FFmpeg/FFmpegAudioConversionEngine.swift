@preconcurrency import AVFoundation
import Foundation

actor FFmpegAudioConversionEngine: ConversionEngine {
    private let executableURL: URL?
    private let processRunner: any FFmpegProcessRunning
    private let commandBuilder: FFmpegAudioCommandBuilder
    private let outputURLProvider: SafeOutputURLProvider
    private var activeJobIDs: Set<UUID> = []
    private var cancelledJobIDs: Set<UUID> = []
    private var isExecutableValidated = false

    init(
        executableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
        processRunner: any FFmpegProcessRunning = FoundationFFmpegProcessRunner(),
        commandBuilder: FFmpegAudioCommandBuilder = FFmpegAudioCommandBuilder(),
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
    ) async throws -> EngineExecutionResult {
        guard let intent = Self.intent(for: plan) else {
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

        var artifacts: [StagedOutputArtifact] = []
        var reserved: Set<URL> = []
        progress(0)
        do {
            try await validateExecutableIfNeeded(
                executableURL: executableURL,
                jobID: plan.id
            )
            for (index, input) in plan.inputs.enumerated() {
                try Task.checkCancellation()
                let output = try outputURLProvider.outputURL(
                    for: input.url,
                    filenameExtension: intent.outputFormat.filenameExtension,
                    policy: plan.outputPolicy,
                    reserved: reserved
                )
                reserved.insert(output)
                try await convert(
                    plan: plan,
                    input: input,
                    outputURL: output,
                    intent: intent,
                    executableURL: executableURL,
                    index: index,
                    count: plan.inputs.count,
                    progress: progress
                )
                artifacts.append(
                    StagedOutputArtifact(
                        id: OutputArtifactID(
                            sourceInputID: input.id,
                            role: .converted
                        ),
                        fileURL: output
                    )
                )
                progress(Double(index + 1) / Double(plan.inputs.count))
            }
            return EngineExecutionResult(artifacts: artifacts)
        } catch let error as ConversionError {
            artifacts.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }
            throw error
        } catch is CancellationError {
            artifacts.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }
            throw ConversionError.cancelled
        } catch {
            artifacts.forEach { try? FileManager.default.removeItem(at: $0.fileURL) }
            throw ConversionError.conversionFailed(
                underlying: "The audio conversion failed."
            )
        }
    }

    func cancel(jobID: UUID) async {
        if activeJobIDs.contains(jobID) {
            await processRunner.cancel(jobID: jobID)
        } else {
            cancelledJobIDs.insert(jobID)
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
                command: FFmpegCommand(executableURL: executableURL, arguments: ["-version"]),
                limits: .versionValidation,
                eventHandler: collector.consume
            )
        } catch let failure as FFmpegProcessFailure where failure == .cancelled {
            throw ConversionError.cancelled
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

    private func convert(
        plan: ConversionPlan,
        input: InputFile,
        outputURL: URL,
        intent: AudioIntent,
        executableURL: URL,
        index: Int,
        count: Int,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let accessed = input.url.startAccessingSecurityScopedResource()
        defer { if accessed { input.url.stopAccessingSecurityScopedResource() } }

        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".fileisland-\(UUID().uuidString).\(intent.outputFormat.filenameExtension)"
            )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let command = try commandBuilder.makeCommand(
            plan: plan,
            input: input,
            outputURL: temporaryURL,
            executableURL: executableURL
        )
        let monitor = FFmpegExecutionMonitor(
            sensitivePaths: [input.url.path, temporaryURL.path, outputURL.path],
            batchIndex: index,
            batchCount: count,
            progress: progress
        )
        let result: FFmpegProcessResult
        do {
            result = try await processRunner.run(
                jobID: plan.id,
                command: command,
                limits: .conversion,
                eventHandler: monitor.consume
            )
        } catch let failure as FFmpegProcessFailure {
            throw Self.processError(for: failure)
        }
        try Task.checkCancellation()
        guard result.exitCode == 0 else {
            throw ConversionError.conversionFailed(
                underlying: monitor.diagnostic.isEmpty
                    ? "FFmpeg exited with code \(result.exitCode)."
                    : monitor.diagnostic
            )
        }
        try await Self.validate(outputURL: temporaryURL)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw ConversionError.permissionDenied
        } catch {
            throw ConversionError.conversionFailed(
                underlying: "The converted audio could not be saved."
            )
        }
    }

    private nonisolated static func validate(outputURL: URL) async throws {
        let fileSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let asset = AVURLAsset(url: outputURL)
        let duration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard fileSize > 0,
              duration.isFinite,
              duration > 0,
              !audioTracks.isEmpty,
              videoTracks.isEmpty else {
            throw ConversionError.conversionFailed(
                underlying: "The converted audio failed validation."
            )
        }
    }

    private nonisolated static func intent(for plan: ConversionPlan) -> AudioIntent? {
        guard !plan.inputs.isEmpty,
              plan.steps.count == 1,
              case let .audio(intent) = plan.steps[0],
              plan.inputs.allSatisfy({
                  MediaConversionMatrix.supportsAudioConversion(
                      from: $0.format,
                      to: intent.outputFormat
                  )
              }) else { return nil }
        return intent
    }

    private nonisolated static func processError(
        for failure: FFmpegProcessFailure
    ) -> ConversionError {
        switch failure {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .conversionFailed(
                underlying: "FFmpeg stopped responding during audio conversion."
            )
        case .outputLimitExceeded:
            return .conversionFailed(
                underlying: "FFmpeg produced more process output than allowed."
            )
        case .launchFailed:
            return .engineUnavailable
        case .duplicateJobID:
            return .conversionFailed(
                underlying: "A conversion process is already running for this job."
            )
        }
    }
}
