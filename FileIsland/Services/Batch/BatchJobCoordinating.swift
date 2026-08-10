import Foundation

struct BatchProgress: Equatable, Sendable {
    let requestID: UUID
    let fraction: Double
    let currentFile: Int
    let totalFiles: Int
    let currentDisplayName: String?
}

struct BatchResult: Equatable, Sendable {
    let outputURLs: [URL]
    let skippedCount: Int
    let failClosedCount: Int
}

protocol BatchJobCoordinating: Sendable {
    func execute(
        _ request: BatchConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> BatchResult

    func cancel(requestID: UUID) async
}
