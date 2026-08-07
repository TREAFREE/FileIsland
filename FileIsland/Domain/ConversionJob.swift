import Foundation

struct ConversionJob: Identifiable, Equatable, Sendable {
    let id: UUID
    let plan: ConversionPlan
    var state: JobState

    init(id: UUID = UUID(), plan: ConversionPlan, state: JobState = .queued) {
        self.id = id
        self.plan = plan
        self.state = state
    }
}

enum JobState: Equatable, Sendable {
    case queued
    case preparing
    case running(progress: Double)
    case cancelling
    case completed([URL])
    case failed(ConversionError)
    case cancelled
}

enum ConversionError: Error, Equatable, Sendable {
    case unsupportedInput
    case unsupportedOutput
    case insufficientDiskSpace
    case permissionDenied
    case engineUnavailable
    case invalidMedia
    case cancelled
    case targetSizeUnreachable
    case conversionFailed(underlying: String?)
}

struct JobSnapshot: Equatable, Sendable {
    let actionLabel: String
    let progress: Double
    let isEstimated: Bool
    let currentFile: Int
    let totalFiles: Int
    let inputBytes: Int64?
    let estimatedOutputBytes: Int64?
}

struct ResultSummary: Equatable, Sendable {
    let outputURLs: [URL]
    let inputBytes: Int64
    let outputBytes: Int64
}

struct UserFacingError: Error, Equatable, Sendable {
    let title: String
    let message: String
}
