import Foundation

enum FFmpegProcessEvent: Sendable {
    case standardOutput(Data)
    case standardError(Data)
}

struct FFmpegProcessResult: Equatable, Sendable {
    let exitCode: Int32
}

protocol FFmpegProcessRunning: Sendable {
    func run(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult

    func cancel(jobID: UUID) async
}
