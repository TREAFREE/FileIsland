import Foundation

struct VideoSplitExecutionProgress: Equatable, Sendable {
    let jobID: UUID
    let fraction: Double
    let processedMilliseconds: Int64
}

enum VideoSplitEngineError: Error, Equatable, Sendable {
    case unsupportedPlan
    case engineUnavailable
    case invalidStagingDirectory
    case processFailed
    case processTimedOut
    case excessiveProcessOutput
    case sourceChanged
    case cancelled
}

protocol VideoSplitEngine: Sendable {
    func canHandle(_ plan: VideoSplitPlan) -> Bool

    func execute(
        _ plan: VideoSplitPlan,
        stagingDirectory: URL,
        progress: @Sendable @escaping (VideoSplitExecutionProgress) -> Void
    ) async throws -> EngineExecutionResult

    func cancel(jobID: UUID) async
}
