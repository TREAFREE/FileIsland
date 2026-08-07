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
    case compactProgress
}

extension IslandState {
    var layoutMode: IslandLayoutMode {
        switch self {
        case .idle:
            .compact
        case .preparing, .converting:
            .compactProgress
        case .dragHover, .inspecting, .droppedSummary, .actionSelection, .success, .failure:
            .expanded
        }
    }
}
