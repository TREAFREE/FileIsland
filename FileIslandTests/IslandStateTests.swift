import XCTest
@testable import FileIsland

final class IslandStateTests: XCTestCase {
    func testStateMapsToExpectedLayoutModes() {
        let snapshot = JobSnapshot(
            actionLabel: "Converting…",
            progress: 0.5,
            isEstimated: false,
            currentFile: 1,
            totalFiles: 1,
            inputBytes: 100,
            estimatedOutputBytes: 50
        )

        XCTAssertEqual(IslandState.idle.layoutMode, .compact)
        XCTAssertEqual(IslandState.dragHover.layoutMode, .expanded)
        XCTAssertEqual(IslandState.inspecting.layoutMode, .expanded)
        XCTAssertEqual(IslandState.droppedSummary([]).layoutMode, .expanded)
        XCTAssertEqual(IslandState.preparing.layoutMode, .compactProgress)
        XCTAssertEqual(IslandState.converting(snapshot).layoutMode, .compactProgress)
    }
}
