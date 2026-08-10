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
    ) async throws -> [URL] {
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

        var outputs: [URL] = []
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
                outputs.append(output)
                progress(Double(index + 1) / Double(plan.inputs.count))
            }
            return outputs
        } catch let error as ConversionError {
            outputs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        } catch is CancellationError {
            outputs.forEach { try? FileManager.default.removeItem(at: $0) }
            throw ConversionError.cancelled
        } catch {
            outputs.forEach { try? FileManager.default.removeItem(at: $0) }
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
}
