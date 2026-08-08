import CoreGraphics

struct NotchWingMetrics: Equatable, Sendable {
    let leadingWidth: CGFloat
    let occludedWidth: CGFloat
    let trailingWidth: CGFloat
}

enum NotchWingLayout {
    static func metrics(
        islandWidth: CGFloat,
        notchWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> NotchWingMetrics {
        let available = max(0, islandWidth - (horizontalPadding * 2))
        let occluded = min(max(0, notchWidth), available)
        let wing = max(0, (available - occluded) / 2)
        return NotchWingMetrics(
            leadingWidth: wing,
            occludedWidth: occluded,
            trailingWidth: wing
        )
    }
}
