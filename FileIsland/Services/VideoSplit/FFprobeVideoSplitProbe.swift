import Foundation

struct FFprobeVideoSplitProbeConfiguration: Equatable, Sendable {
    let metadataLimits: FFmpegProcessLimits
    let keyframeLimits: FFmpegProcessLimits

    static let production = FFprobeVideoSplitProbeConfiguration(
        metadataLimits: FFmpegProcessLimits(
            timeout: .seconds(15),
            terminationGracePeriod: .seconds(2),
            maximumStandardOutputBytes: 256 * 1_024,
            maximumStandardErrorBytes: 64 * 1_024
        ),
        keyframeLimits: FFmpegProcessLimits(
            timeout: .seconds(120),
            terminationGracePeriod: .seconds(2),
            maximumStandardOutputBytes: 16 * 1_024 * 1_024,
            maximumStandardErrorBytes: 64 * 1_024
        )
    )
}

struct FFprobeVideoSplitProbe: VideoSplitProbing {
    private let executableURL: URL
    private let processRunner: any FFmpegProcessRunning
    private let fileValidator: any LocalRegularMediaFileValidating
    private let metadataParser: FFprobeMetadataParser
    private let configuration: FFprobeVideoSplitProbeConfiguration

    init(
        executableURL: URL,
        processRunner: any FFmpegProcessRunning = FoundationFFmpegProcessRunner(),
        fileValidator: any LocalRegularMediaFileValidating = POSIXLocalRegularMediaFileValidator(),
        metadataParser: FFprobeMetadataParser = FFprobeMetadataParser(),
        configuration: FFprobeVideoSplitProbeConfiguration = .production
    ) {
        self.executableURL = executableURL
        self.processRunner = processRunner
        self.fileValidator = fileValidator
        self.metadataParser = metadataParser
        self.configuration = configuration
    }

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        guard !Task.isCancelled else { throw VideoSplitProbeError.probeCancelled }
        try validateExecutable()

        let accessed = input.url.startAccessingSecurityScopedResource()
        defer { if accessed { input.url.stopAccessingSecurityScopedResource() } }

        let before = try validatedIdentity(input)
        let metadataData = try await runMetadataProbe(input: input)
        let metadata: FFprobeMetadata
        do {
            metadata = try metadataParser.parse(
                metadataData,
                inputURL: input.url,
                fileByteCount: before.byteCount
            )
        } catch {
            throw mapParsingError(error)
        }

        let keyframes = try await runKeyframeProbe(input: input, metadata: metadata)
        let after = try validatedIdentity(input)
        guard before == after else {
            throw VideoSplitProbeError.fileChangedDuringProbe
        }
        guard !Task.isCancelled else { throw VideoSplitProbeError.probeCancelled }

        let facts = VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: before.videoSplitIdentity,
            durationMilliseconds: metadata.durationMilliseconds,
            displayWidth: metadata.displayWidth,
            displayHeight: metadata.displayHeight,
            rotationDegrees: metadata.rotationDegrees,
            averageBitrateBitsPerSecond: metadata.averageBitrateBitsPerSecond,
            container: metadata.container,
            videoCodec: metadata.videoCodec,
            audioCodec: metadata.audioCodec,
            videoStartMilliseconds: metadata.videoStartMilliseconds,
            audioStartMilliseconds: metadata.audioStartMilliseconds,
            audioDurationMilliseconds: metadata.audioDurationMilliseconds,
            userMetadataKeys: metadata.userMetadataKeys,
            frameDurationMilliseconds: metadata.frameDurationMilliseconds,
            keyframeMilliseconds: keyframes
        )
        return try facts.validated(for: .fastKeyframeCopy, matching: input)
    }

    private func runMetadataProbe(input: InputFile) async throws -> Data {
        let jobID = UUID()
        let collector = FFprobeDataCollector(
            maximumBytes: configuration.metadataLimits.maximumStandardOutputBytes,
            sensitivePaths: [input.url.path]
        )
        let result: FFmpegProcessResult
        do {
            result = try await processRunner.run(
                jobID: jobID,
                command: FFmpegCommand(
                    executableURL: executableURL,
                    arguments: [
                        "-hide_banner",
                        "-v", "error",
                        "-show_format",
                        "-show_streams",
                        "-show_entries",
                        "format=format_name,duration,bit_rate,start_time:format_tags=title,artist,album,comment,description,creation_time,location,copyright,make,model,software:stream=index,codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,duration,bit_rate,start_time:stream_tags=rotate,title,artist,album,comment,description,creation_time,location,copyright,make,model,software:stream_side_data=rotation",
                        "-of", "json=c=1",
                        "--", input.url.path
                    ]
                ),
                limits: configuration.metadataLimits
            ) { event in
                if collector.consume(event) == false {
                    Task { await processRunner.cancel(jobID: jobID) }
                }
            }
        } catch {
            if collector.didOverflow {
                throw VideoSplitProbeError.probeOutputLimitExceeded
            }
            throw mapProcessError(error)
        }
        guard result.exitCode == 0 else {
            throw VideoSplitProbeError.probeProcessFailed
        }
        guard !collector.didOverflow else {
            throw VideoSplitProbeError.probeOutputLimitExceeded
        }
        return collector.data
    }

    private func runKeyframeProbe(
        input: InputFile,
        metadata: FFprobeMetadata
    ) async throws -> [Int64] {
        let jobID = UUID()
        let collector = FFprobeKeyframeCollector(
            parser: FFprobeKeyframeParser(),
            sensitivePaths: [input.url.path]
        )
        let result: FFmpegProcessResult
        do {
            result = try await processRunner.run(
                jobID: jobID,
                command: FFmpegCommand(
                    executableURL: executableURL,
                    arguments: [
                        "-hide_banner",
                        "-v", "error",
                        "-select_streams", "v:0",
                        "-show_packets",
                        "-show_entries", "packet=pts_time,flags",
                        "-of", "compact=p=0:nk=0",
                        "--", input.url.path
                    ]
                ),
                limits: configuration.keyframeLimits
            ) { event in
                if collector.consume(event) == false {
                    Task { await processRunner.cancel(jobID: jobID) }
                }
            }
        } catch {
            if let parsingError = collector.parsingError {
                throw mapParsingError(parsingError)
            }
            throw mapProcessError(error)
        }
        guard result.exitCode == 0 else {
            throw VideoSplitProbeError.probeProcessFailed
        }
        do {
            return try collector.finalize(metadata: metadata)
        } catch {
            throw mapParsingError(error)
        }
    }

    private func validateExecutable() throws {
        guard executableURL.isFileURL,
              executableURL.lastPathComponent == "ffprobe",
              FileManager.default.isExecutableFile(atPath: executableURL.path),
              let values = try? executableURL.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            throw VideoSplitProbeError.probeUnavailable
        }
    }

    private func validatedIdentity(_ input: InputFile) throws -> LocalRegularMediaFileIdentity {
        do {
            return try fileValidator.validate(
                input.url,
                expectedByteCount: input.fileSize
            )
        } catch let error as LocalRegularMediaFileValidationError {
            switch error {
            case .notLocalFile:
                throw VideoSplitProbeError.notLocalFile
            case .symbolicLink:
                throw VideoSplitProbeError.symbolicLink
            case .notRegularFile:
                throw VideoSplitProbeError.notRegularFile
            case .unreadableFile:
                throw VideoSplitProbeError.unreadableFile
            case .fileSizeMismatch, .fileChanged:
                throw VideoSplitProbeError.fileChangedDuringProbe
            }
        } catch {
            throw VideoSplitProbeError.unreadableFile
        }
    }

    private func mapProcessError(_ error: any Error) -> VideoSplitProbeError {
        if let failure = error as? FFmpegProcessFailure {
            switch failure {
            case .cancelled:
                return .probeCancelled
            case .timedOut:
                return .probeTimedOut
            case .outputLimitExceeded:
                return .probeOutputLimitExceeded
            case .duplicateJobID, .launchFailed:
                return .probeUnavailable
            }
        }
        if let conversionError = error as? ConversionError {
            switch conversionError {
            case .cancelled:
                return .probeCancelled
            case .engineUnavailable:
                return .probeUnavailable
            default:
                return .probeProcessFailed
            }
        }
        if error is CancellationError { return .probeCancelled }
        return .probeProcessFailed
    }

    private func mapParsingError(_ error: any Error) -> VideoSplitProbeError {
        guard let error = error as? FFprobeParsingError else {
            return .malformedProbeOutput
        }
        switch error {
        case .unsupportedMedia:
            return .unsupportedMedia
        case .malformedOutput, .arithmeticOverflow, .lineTooLong, .tooManyRecords:
            return .malformedProbeOutput
        }
    }
}

private final class FFprobeDataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int
    private let sensitivePaths: [String]
    private var output = Data()
    private var diagnostic = ""
    private var overflow = false

    init(maximumBytes: Int, sensitivePaths: [String]) {
        self.maximumBytes = maximumBytes
        self.sensitivePaths = sensitivePaths
    }

    func consume(_ event: FFmpegProcessEvent) -> Bool {
        lock.withLock {
            switch event {
            case let .standardOutput(data):
                let remaining = max(0, maximumBytes - output.count)
                output.append(data.prefix(remaining))
                if data.count > remaining { overflow = true }
            case let .standardError(data):
                appendDiagnostic(String(decoding: data, as: UTF8.self))
            }
            return !overflow
        }
    }

    private func appendDiagnostic(_ value: String) {
        diagnostic.append(value)
        for path in sensitivePaths where !path.isEmpty {
            diagnostic = diagnostic.replacingOccurrences(of: path, with: "<path>")
        }
        if diagnostic.count > 4_096 {
            diagnostic = String(diagnostic.suffix(4_096))
        }
    }

    var data: Data { lock.withLock { output } }
    var didOverflow: Bool { lock.withLock { overflow } }
}

private final class FFprobeKeyframeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var parser: FFprobeKeyframeParser
    private let sensitivePaths: [String]
    private var diagnostic = ""
    private var error: FFprobeParsingError?

    init(parser: FFprobeKeyframeParser, sensitivePaths: [String]) {
        self.parser = parser
        self.sensitivePaths = sensitivePaths
    }

    func consume(_ event: FFmpegProcessEvent) -> Bool {
        lock.withLock {
            guard error == nil else { return false }
            switch event {
            case let .standardOutput(data):
                do {
                    try parser.consume(data)
                } catch let parsingError as FFprobeParsingError {
                    error = parsingError
                } catch {
                    self.error = .malformedOutput
                }
            case let .standardError(data):
                appendDiagnostic(String(decoding: data, as: UTF8.self))
            }
            return error == nil
        }
    }

    func finalize(metadata: FFprobeMetadata) throws -> [Int64] {
        try lock.withLock {
            if let error { throw error }
            return try parser.finalize(metadata: metadata)
        }
    }

    private func appendDiagnostic(_ value: String) {
        diagnostic.append(value)
        for path in sensitivePaths where !path.isEmpty {
            diagnostic = diagnostic.replacingOccurrences(of: path, with: "<path>")
        }
        if diagnostic.count > 4_096 {
            diagnostic = String(diagnostic.suffix(4_096))
        }
    }

    var parsingError: FFprobeParsingError? { lock.withLock { error } }
}
