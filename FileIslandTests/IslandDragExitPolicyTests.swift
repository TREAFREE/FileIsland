import CoreGraphics
import XCTest
@testable import FileIsland

final class IslandDragExitPolicyTests: XCTestCase {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 932)
    private let islandFrame = CGRect(x: 530, y: 780, width: 380, height: 152)

    func testKeepsExpandedWhileDraggingAgainstPhysicalTopEdge() {
        XCTAssertTrue(
            IslandDragExitPolicy.shouldKeepExpanded(
                pointer: CGPoint(x: 720, y: 931),
                primaryButtonPressed: true,
                screenFrame: screenFrame,
                islandFrame: islandFrame
            )
        )
    }

    func testAllowsCollapseAfterButtonRelease() {
        XCTAssertFalse(
            IslandDragExitPolicy.shouldKeepExpanded(
                pointer: CGPoint(x: 720, y: 931),
                primaryButtonPressed: false,
                screenFrame: screenFrame,
                islandFrame: islandFrame
            )
        )
    }

    func testAllowsCollapseAfterLeavingIslandWidthOrTopEdge() {
        XCTAssertFalse(
            IslandDragExitPolicy.shouldKeepExpanded(
                pointer: CGPoint(x: 400, y: 931),
                primaryButtonPressed: true,
                screenFrame: screenFrame,
                islandFrame: islandFrame
            )
        )
        XCTAssertFalse(
            IslandDragExitPolicy.shouldKeepExpanded(
                pointer: CGPoint(x: 720, y: 900),
                primaryButtonPressed: true,
                screenFrame: screenFrame,
                islandFrame: islandFrame
            )
        )
    }
}
