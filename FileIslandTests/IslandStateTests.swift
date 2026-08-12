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
        XCTAssertEqual(IslandState.firstRun.layoutMode, .expanded)
        XCTAssertEqual(IslandState.dragHover.layoutMode, .expanded)
        XCTAssertEqual(IslandState.inspecting.layoutMode, .expanded)
        XCTAssertEqual(IslandState.droppedSummary([]).layoutMode, .expanded)
        XCTAssertEqual(IslandState.actionSelection([]).layoutMode, .expandedActions)
        XCTAssertEqual(IslandState.preparing.layoutMode, .compactProgress)
        XCTAssertEqual(IslandState.converting(snapshot).layoutMode, .compactProgress)
        XCTAssertEqual(
            IslandState.success(
                ResultSummary(outputURLs: [], inputBytes: 100, outputBytes: 50)
            ).layoutMode,
            .resultShelf
        )
        XCTAssertEqual(
            IslandState.failure(UserFacingError(title: "Error", message: "Message")).layoutMode,
            .expanded
        )
    }

    func testStateMapsToStableVisualPhases() {
        let snapshot = JobSnapshot(
            actionLabel: "Converting…",
            progress: 0.5,
            isEstimated: false,
            currentFile: 1,
            totalFiles: 1,
            inputBytes: 100,
            estimatedOutputBytes: 50
        )
        let summary = ResultSummary(
            outputURLs: [],
            inputBytes: 100,
            outputBytes: 50
        )
        let error = UserFacingError(
            title: "Conversion failed",
            message: "Try again."
        )

        XCTAssertEqual(IslandState.idle.visualPhase, .idle)
        XCTAssertEqual(IslandState.firstRun.visualPhase, .summary)
        XCTAssertEqual(IslandState.dragHover.visualPhase, .dragTarget)
        XCTAssertEqual(IslandState.inspecting.visualPhase, .inspection)
        XCTAssertEqual(IslandState.droppedSummary([]).visualPhase, .summary)
        XCTAssertEqual(IslandState.actionSelection([]).visualPhase, .actions)
        XCTAssertEqual(IslandState.preparing.visualPhase, .progress)
        XCTAssertEqual(IslandState.converting(snapshot).visualPhase, .progress)
        XCTAssertEqual(IslandState.success(summary).visualPhase, .success)
        XCTAssertEqual(IslandState.failure(error).visualPhase, .failure)
    }

    func testOnlyStatesWithActionableContentAllowKeyboardInteraction() {
        let snapshot = JobSnapshot(
            actionLabel: "Converting…",
            progress: 0.5,
            isEstimated: false,
            currentFile: 1,
            totalFiles: 1,
            inputBytes: 100,
            estimatedOutputBytes: 50
        )
        let summary = ResultSummary(outputURLs: [], inputBytes: 100, outputBytes: 50)
        let error = UserFacingError(title: "Conversion failed", message: "Try again.")

        XCTAssertFalse(IslandState.idle.allowsKeyboardInteraction)
        XCTAssertFalse(IslandState.firstRun.allowsKeyboardInteraction)
        XCTAssertFalse(IslandState.dragHover.allowsKeyboardInteraction)
        XCTAssertFalse(IslandState.inspecting.allowsKeyboardInteraction)
        XCTAssertTrue(IslandState.droppedSummary([]).allowsKeyboardInteraction)
        XCTAssertTrue(IslandState.actionSelection([]).allowsKeyboardInteraction)
        XCTAssertTrue(IslandState.preparing.allowsKeyboardInteraction)
        XCTAssertTrue(IslandState.converting(snapshot).allowsKeyboardInteraction)
        XCTAssertTrue(IslandState.success(summary).allowsKeyboardInteraction)
        XCTAssertTrue(IslandState.failure(error).allowsKeyboardInteraction)
    }

    func testInputSelectionIsDisabledOnlyWhileConversionOwnsTheWorkflow() {
        let snapshot = JobSnapshot(
            actionLabel: "Converting…",
            progress: 0.5,
            isEstimated: false,
            currentFile: 1,
            totalFiles: 1,
            inputBytes: 100,
            estimatedOutputBytes: 50
        )

        XCTAssertTrue(IslandState.idle.allowsInputSelection)
        XCTAssertTrue(IslandState.firstRun.allowsInputSelection)
        XCTAssertTrue(IslandState.dragHover.allowsInputSelection)
        XCTAssertTrue(IslandState.inspecting.allowsInputSelection)
        XCTAssertTrue(IslandState.droppedSummary([]).allowsInputSelection)
        XCTAssertTrue(IslandState.actionSelection([]).allowsInputSelection)
        XCTAssertFalse(IslandState.preparing.allowsInputSelection)
        XCTAssertFalse(IslandState.converting(snapshot).allowsInputSelection)
        XCTAssertTrue(
            IslandState.success(
                ResultSummary(outputURLs: [], inputBytes: 100, outputBytes: 50)
            ).allowsInputSelection
        )
    }
}
