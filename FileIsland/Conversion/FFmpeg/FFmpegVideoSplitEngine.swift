import Foundation

actor FFmpegVideoSplitEngine: VideoSplitEngine {
    private let executableURL: URL?
    private let processRunner: any FFmpegProcessRunning
    private let commandBuilder: FFmpegVideoSplitCommandBuilder
    private let fileValidator: any LocalRegularMediaFileValidating
    private var activeJobIDs: Set<UUID> = []
    private var cancelledJobIDs: Set<UUID> = []

    init(
        executableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
        processRunner: any FFmpegProcessRunning = FoundationFFmpegProcessRunner(),
        commandBuilder: FFmpegVideoSplitCommandBuilder = FFmpegVideoSplitCommandBuilder(),
        fileValidator: any LocalRegularMediaFileValidating =
            POSIXLocalRegularMediaFileValidator()
    ) {
        self.executableURL = executableURL
        self.processRunner = processRunner
        self.commandBuilder = commandBuilder
        self.fileValidator = fileValidator
    }

    nonisolated func canHandle(_ plan: VideoSplitPlan) -> Bool {
        guard plan.input.kind == .video,
              plan.intent.mode == .fastKeyframeCopy,
              plan.intent.source == .custom,
              plan.ruleSnapshot == nil,
              !plan.segments.isEmpty,
              plan.segments.allSatisfy({ !$0.requiresReencoding }) else {
            return false
        }
        let extensions = Set(
            plan.segments.map {
                URL(fileURLWithPath: $0.outputRelativePath.string)
                    .pathExtension.lowercased()
            }
        )
        return extensions.count == 1
            && extensions.isSubset(of: ["mp4", "mov"])
    }

    func execute(
        _ plan: VideoSplitPlan,
        stagingDirectory: URL,
        progress: @Sendable @escaping (VideoSplitExecutionProgress) -> Void
    ) async throws -> EngineExecutionResult {
        guard canHandle(plan) else {
            throw VideoSplitEngineError.unsupportedPlan
        }
        guard let executableURL,
              Self.isTrustedExecutable(executableURL) else {
            throw VideoSplitEngineError.engineUnavailable
        }
        guard Self.isSafeStagingDirectory(stagingDirectory) else {
            throw VideoSplitEngineError.invalidStagingDirectory
        }
        guard cancelledJobIDs.remove(plan.id) == nil else {
            throw VideoSplitEngineError.cancelled
        }
        guard activeJobIDs.insert(plan.id).inserted else {
            throw VideoSplitEngineError.processFailed
        }
        defer { activeJobIDs.remove(plan.id) }

        let invocation: FFmpegVideoSplitCommand
        do {
            invocation = try commandBuilder.makeCommand(
                plan: plan,
                stagingDirectory: stagingDirectory,
                executableURL: executableURL
            )
        } catch {
            throw VideoSplitEngineError.unsupportedPlan
        }
        let monitor = VideoSplitProgressMonitor(
            jobID: plan.id,
            totalMilliseconds: plan.segments.last?.endMilliseconds ?? 1,
            sensitivePaths: [plan.input.url.path, stagingDirectory.path],
            progress: progress
        )
        progress(
            VideoSplitExecutionProgress(
                jobID: plan.id,
                fraction: 0,
                processedMilliseconds: 0
            )
        )

        let accessed = plan.input.url.startAccessingSecurityScopedResource()
        defer {
            if accessed { plan.input.url.stopAccessingSecurityScopedResource() }
        }

        do {
            let identity = try fileValidator.validate(
                plan.input.url,
                expectedByteCount: plan.input.fileSize
            )
            guard identity.videoSplitIdentity == plan.sourceFileIdentity else {
                throw VideoSplitEngineError.sourceChanged
            }
        } catch let error as VideoSplitEngineError {
            throw error
        } catch {
            throw VideoSplitEngineError.sourceChanged
        }

        do {
            let result = try await processRunner.run(
                jobID: plan.id,
                command: invocation.command,
                limits: FFmpegProcessLimits(
                    timeout: .seconds(30 * 60),
                    terminationGracePeriod: .seconds(2),
                    maximumStandardOutputBytes: 1_024 * 1_024,
                    maximumStandardErrorBytes: 64 * 1_024
                ),
                eventHandler: monitor.consume
            )
            try Task.checkCancellation()
            guard result.exitCode == 0 else {
                Self.removeExpectedArtifacts(invocation.stagedArtifacts)
                throw VideoSplitEngineError.processFailed
            }
            let finalIdentity = try fileValidator.validate(
                plan.input.url,
                expectedByteCount: plan.input.fileSize
            )
            guard finalIdentity.videoSplitIdentity == plan.sourceFileIdentity else {
                Self.removeExpectedArtifacts(invocation.stagedArtifacts)
                throw VideoSplitEngineError.sourceChanged
            }
            monitor.finish()
            return EngineExecutionResult(artifacts: invocation.stagedArtifacts)
        } catch let error as VideoSplitEngineError {
            Self.removeExpectedArtifacts(invocation.stagedArtifacts)
            throw error
        } catch let failure as FFmpegProcessFailure {
            Self.removeExpectedArtifacts(invocation.stagedArtifacts)
            switch failure {
            case .cancelled:
                throw VideoSplitEngineError.cancelled
            case .timedOut:
                throw VideoSplitEngineError.processTimedOut
            case .outputLimitExceeded:
                throw VideoSplitEngineError.excessiveProcessOutput
            case .duplicateJobID, .launchFailed:
                throw VideoSplitEngineError.engineUnavailable
            }
        } catch let error as LocalRegularMediaFileValidationError {
            Self.removeExpectedArtifacts(invocation.stagedArtifacts)
            _ = error
            throw VideoSplitEngineError.sourceChanged
        } catch is CancellationError {
            Self.removeExpectedArtifacts(invocation.stagedArtifacts)
            throw VideoSplitEngineError.cancelled
        } catch {
            Self.removeExpectedArtifacts(invocation.stagedArtifacts)
            throw VideoSplitEngineError.processFailed
        }
    }

    func cancel(jobID: UUID) async {
        if activeJobIDs.contains(jobID) {
            await processRunner.cancel(jobID: jobID)
        } else {
            cancelledJobIDs.insert(jobID)
        }
    }

    private nonisolated static func isTrustedExecutable(_ url: URL) -> Bool {
        guard url.isFileURL,
              FileManager.default.isExecutableFile(atPath: url.path),
              let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    private nonisolated static func isSafeStagingDirectory(_ url: URL) -> Bool {
        guard url.isFileURL,
              url.standardizedFileURL.path != "/",
              let values = try? url.resourceValues(
                  forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private nonisolated static func removeExpectedArtifacts(
        _ artifacts: [StagedOutputArtifact]
    ) {
        for artifact in artifacts {
            try? FileManager.default.removeItem(at: artifact.fileURL)
        }
    }
}

private final class VideoSplitProgressMonitor: @unchecked Sendable {
    private let jobID: UUID
    private let totalMilliseconds: Int64
    private let sensitivePaths: [String]
    private let progress: @Sendable (VideoSplitExecutionProgress) -> Void
    private let lock = NSLock()
    private var standardOutputBuffer = Data()
    private var diagnosticBuffer = Data()
    private var lastMilliseconds: Int64 = 0
    private var lastFraction = 0.0

    init(
        jobID: UUID,
        totalMilliseconds: Int64,
        sensitivePaths: [String],
        progress: @Sendable @escaping (VideoSplitExecutionProgress) -> Void
    ) {
        self.jobID = jobID
        self.totalMilliseconds = max(totalMilliseconds, 1)
        self.sensitivePaths = sensitivePaths
        self.progress = progress
    }

    func consume(_ event: FFmpegProcessEvent) {
        switch event {
        case let .standardOutput(data):
            consumeStandardOutput(data)
        case let .standardError(data):
            lock.withLock {
                let remaining = max(0, 64 * 1_024 - diagnosticBuffer.count)
                diagnosticBuffer.append(data.prefix(remaining))
            }
        }
    }

    func finish() {
        emit(milliseconds: totalMilliseconds, fraction: 1)
    }

    private func consumeStandardOutput(_ data: Data) {
        let lines: [String] = lock.withLock {
            standardOutputBuffer.append(data)
            var parsed: [String] = []
            while let newline = standardOutputBuffer.firstIndex(of: 0x0A) {
                let lineData = standardOutputBuffer[..<newline]
                standardOutputBuffer.removeSubrange(...newline)
                if let line = String(data: lineData, encoding: .utf8) {
                    parsed.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            return parsed
        }
        for line in lines {
            if line == "progress=end" {
                finish()
            } else if line.hasPrefix("out_time_us="),
                      let microseconds = Int64(line.dropFirst("out_time_us=".count)) {
                let milliseconds = max(0, microseconds / 1_000)
                emit(
                    milliseconds: milliseconds,
                    fraction: min(Double(milliseconds) / Double(totalMilliseconds), 0.999)
                )
            }
        }
    }

    private func emit(milliseconds: Int64, fraction: Double) {
        let update: VideoSplitExecutionProgress? = lock.withLock {
            let clampedMilliseconds = max(lastMilliseconds, min(milliseconds, totalMilliseconds))
            let clampedFraction = max(lastFraction, min(max(fraction, 0), 1))
            guard clampedMilliseconds > lastMilliseconds || clampedFraction > lastFraction else {
                return nil
            }
            lastMilliseconds = clampedMilliseconds
            lastFraction = clampedFraction
            return VideoSplitExecutionProgress(
                jobID: jobID,
                fraction: clampedFraction,
                processedMilliseconds: clampedMilliseconds
            )
        }
        if let update { progress(update) }
    }

    var sanitizedDiagnostic: String {
        let raw = lock.withLock {
            String(decoding: diagnosticBuffer, as: UTF8.self)
        }
        return sensitivePaths.reduce(raw) { value, path in
            value.replacingOccurrences(of: path, with: "<redacted>")
        }
    }
}
