import Foundation

enum VideoSplitJobEvent: Equatable, Sendable {
    case progress(VideoSplitBatchProgress)
    case validationCompleted(requestID: UUID, segmentCount: Int)
    case publicationCompleted(requestID: UUID, outputURLs: [URL])
}

protocol VideoSplitJobCoordinating: Sendable {
    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult

    func cancel(requestID: UUID) async
}

extension VideoSplitJobCoordinating {
    func execute(
        _ request: VideoSplitBatchRequest,
        progress: @Sendable @escaping (VideoSplitBatchProgress) -> Void
    ) async throws -> VideoSplitBatchResult {
        try await execute(request) { event in
            guard case let .progress(value) = event else { return }
            progress(value)
        }
    }
}
