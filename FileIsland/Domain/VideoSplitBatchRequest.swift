import Foundation

struct VideoSplitBatchItem: Equatable, Sendable {
    let input: BatchInput
    let plan: VideoSplitPlan
}

struct VideoSplitBatchRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let selections: [InputSelection]
    let outputDirectory: URL
    let items: [VideoSplitBatchItem]

    init(
        id: UUID = UUID(),
        selections: [InputSelection],
        outputDirectory: URL,
        items: [VideoSplitBatchItem]
    ) {
        self.id = id
        self.selections = selections
        self.outputDirectory = outputDirectory
        self.items = items
    }
}

struct VideoSplitBatchProgress: Equatable, Sendable {
    let requestID: UUID
    let fraction: Double
    let currentFile: Int
    let totalFiles: Int
    let currentDisplayName: String?
    let currentSegment: Int?
    let totalSegments: Int?
}

struct VideoSplitBatchResult: Equatable, Sendable {
    let requestID: UUID
    let outputURLs: [URL]
    let segmentCount: Int
    let totalBytes: Int64
}

enum VideoSplitJobError: Error, Equatable, Sendable {
    case anotherRequestIsRunning
    case emptyRequest
    case invalidOutputDirectory
    case duplicateInputIdentity
    case stalePlan
    case engineUnavailable
    case validationFailed
    case keyframeSpacingUnreachable
    case retryLimitReached
    case publicationFailed
    case cancelled
}
