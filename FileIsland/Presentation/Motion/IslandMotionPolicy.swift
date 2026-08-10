import Foundation

enum IslandVisualPhase: Equatable, Sendable {
    case idle
    case dragTarget
    case inspection
    case summary
    case actions
    case progress
    case success
    case failure
}

enum IslandMotionPolicy {
    static let successDisplayDuration: Duration = .seconds(3)

    static func windowDuration(
        from oldMode: IslandLayoutMode,
        to newMode: IslandLayoutMode,
        reduceMotion: Bool
    ) -> TimeInterval {
        guard !reduceMotion, oldMode != newMode else { return 0 }
        return newMode == .compact ? 0.18 : 0.22
    }

    static func contentDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.10 : 0.14
    }
}

enum StatusAnimationPolicy {
    static func frameInterval(
        progress: Double,
        reduceMotion: Bool
    ) -> TimeInterval? {
        guard !reduceMotion else { return nil }
        let clamped = min(max(progress, 0), 1)
        return 0.08 + (0.20 * clamped)
    }
}
