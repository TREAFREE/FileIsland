import CoreGraphics

enum IslandDragExitPolicy {
    static let topEdgeTolerance: CGFloat = 6

    static func shouldKeepExpanded(
        pointer: CGPoint,
        primaryButtonPressed: Bool,
        screenFrame: CGRect,
        islandFrame: CGRect
    ) -> Bool {
        guard primaryButtonPressed else { return false }

        let isHorizontallyOverIsland = pointer.x >= islandFrame.minX
            && pointer.x <= islandFrame.maxX
        let isAtPhysicalTopEdge = pointer.y >= screenFrame.maxY - topEdgeTolerance
            && pointer.y <= screenFrame.maxY

        return isHorizontallyOverIsland && isAtPhysicalTopEdge
    }
}
