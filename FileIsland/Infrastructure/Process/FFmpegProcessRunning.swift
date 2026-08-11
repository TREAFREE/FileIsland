import Foundation

enum FFmpegProcessEvent: Sendable {
    case standardOutput(Data)
    case standardError(Data)
}

enum FFmpegProcessStream: Equatable, Sendable {
    case standardOutput
    case standardError
}

struct FFmpegProcessLimits: Equatable, Sendable {
    let timeout: Duration?
    let inactivityTimeout: Duration?
    let terminationGracePeriod: Duration
    let maximumStandardOutputBytes: Int
    let maximumStandardErrorBytes: Int

    init(
        timeout: Duration?,
        inactivityTimeout: Duration? = nil,
        terminationGracePeriod: Duration,
        maximumStandardOutputBytes: Int,
        maximumStandardErrorBytes: Int
    ) {
        precondition(timeout.map { $0 > .zero } ?? true)
        precondition(inactivityTimeout.map { $0 > .zero } ?? true)
        precondition(terminationGracePeriod >= .zero)
        precondition(maximumStandardOutputBytes >= 0)
        precondition(maximumStandardErrorBytes >= 0)
        self.timeout = timeout
        self.inactivityTimeout = inactivityTimeout
        self.terminationGracePeriod = terminationGracePeriod
        self.maximumStandardOutputBytes = maximumStandardOutputBytes
        self.maximumStandardErrorBytes = maximumStandardErrorBytes
    }

    static let versionValidation = FFmpegProcessLimits(
        timeout: .seconds(10),
        terminationGracePeriod: .seconds(2),
        maximumStandardOutputBytes: 256 * 1_024,
        maximumStandardErrorBytes: 256 * 1_024
    )

    static let conversion = FFmpegProcessLimits(
        timeout: nil,
        inactivityTimeout: .seconds(5 * 60),
        terminationGracePeriod: .seconds(2),
        maximumStandardOutputBytes: 256 * 1_024 * 1_024,
        maximumStandardErrorBytes: 8 * 1_024 * 1_024
    )

    /// Source-compatible bounded test convenience. Production code names its profile.
    static let legacy = conversion
}

enum FFmpegProcessFailure: Error, Equatable, Sendable {
    case duplicateJobID
    case launchFailed
    case cancelled
    case timedOut
    case outputLimitExceeded(FFmpegProcessStream)
}

struct FFmpegProcessResult: Equatable, Sendable {
    let exitCode: Int32
}

protocol FFmpegProcessRunning: Sendable {
    func run(
        jobID: UUID,
        command: FFmpegCommand,
        limits: FFmpegProcessLimits,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult

    func cancel(jobID: UUID) async
}

extension FFmpegProcessRunning {
    func run(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        try await run(
            jobID: jobID,
            command: command,
            limits: .conversion,
            eventHandler: eventHandler
        )
    }
}
