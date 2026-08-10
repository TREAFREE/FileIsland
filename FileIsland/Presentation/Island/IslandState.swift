import Foundation

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
        case .preparing, .converting:
            .compactProgress
        case .actionSelection:
            .expandedActions
        case .dragHover, .inspecting, .droppedSummary, .success, .failure:
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
}
