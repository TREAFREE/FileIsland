import Foundation

enum IslandVideoOperation: String, Equatable, Sendable {
    case convert
    case splitForSharing
}

enum IslandVideoSplitIssue: Equatable, Sendable {
    case enterAtLeastOneLimit
    case invalidMaximumMegabytes
    case invalidMaximumDuration
    case runtimeUnavailable
    case unsupportedSource
    case sourceChanged
    case keyframesTooFarApart
    case planningFailed
}

enum IslandVideoSplitPlanningState: Equatable, Sendable {
    case inactive
    case planning
    case ready
    case blocked(IslandVideoSplitIssue)
}

enum IslandState: Equatable, Sendable {
    case idle
    case dragHover
    case inspecting
    case droppedSummary([InputFile])
    case actionSelection([InputFile])
    case preparing
    case converting(JobSnapshot)
    case success(ResultSummary)
    case failure(UserFacingError)
}

enum IslandPresentationMode: Equatable, Sendable {
    case physicalNotch
    case floatingPill
}

enum IslandLayoutMode: Equatable, Sendable {
    case compact
    case expanded
    case expandedActions
    case compactProgress
}

extension IslandState {
    var layoutMode: IslandLayoutMode {
        switch self {
        case .idle:
            .compact
        case .preparing, .converting, .success:
            .compactProgress
        case .actionSelection:
            .expandedActions
        case .dragHover, .inspecting, .droppedSummary, .failure:
            .expanded
        }
    }

    var visualPhase: IslandVisualPhase {
        switch self {
        case .idle:
            .idle
        case .dragHover:
            .dragTarget
        case .inspecting:
            .inspection
        case .droppedSummary:
            .summary
        case .actionSelection:
            .actions
        case .preparing, .converting:
            .progress
        case .success:
            .success
        case .failure:
            .failure
        }
    }

    var allowsKeyboardInteraction: Bool {
        switch self {
        case .idle, .dragHover, .inspecting:
            false
        case .droppedSummary, .actionSelection, .preparing, .converting, .success, .failure:
            true
        }
    }

    var allowsInputSelection: Bool {
        switch self {
        case .preparing, .converting:
            false
        default:
            true
        }
    }
}
