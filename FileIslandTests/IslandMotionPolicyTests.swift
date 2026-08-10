import XCTest
@testable import FileIsland

final class IslandMotionPolicyTests: XCTestCase {
    func testWindowTransitionsUseResponsiveAsymmetricDurations() {
        XCTAssertEqual(
            IslandMotionPolicy.windowDuration(
                from: .compact,
                to: .expanded,
                reduceMotion: false
            ),
            0.30,
            accuracy: 0.001
        )
        XCTAssertEqual(
            IslandMotionPolicy.windowDuration(
                from: .expanded,
                to: .compact,
                reduceMotion: false
            ),
            0.24,
            accuracy: 0.001
        )
        XCTAssertEqual(
            IslandMotionPolicy.windowDuration(
                from: .expanded,
                to: .expanded,
                reduceMotion: false
            ),
            0,
            accuracy: 0.001
        )
    }

    func testReduceMotionRemovesWindowMovementButKeepsShortContentFeedback() {
        XCTAssertEqual(
            IslandMotionPolicy.windowDuration(
                from: .compact,
                to: .expandedActions,
                reduceMotion: true
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(IslandMotionPolicy.contentDuration(reduceMotion: true), 0.10)
        XCTAssertEqual(IslandMotionPolicy.contentDuration(reduceMotion: false), 0.20)
        XCTAssertLessThan(
            IslandMotionPolicy.contentDuration(reduceMotion: false),
            0.3
        )
    }

    func testStatusFrameIntervalSlowsMonotonicallyWithRealProgress() throws {
        let start = try XCTUnwrap(
            StatusAnimationPolicy.frameInterval(progress: -1, reduceMotion: false)
        )
        let middle = try XCTUnwrap(
            StatusAnimationPolicy.frameInterval(progress: 0.5, reduceMotion: false)
        )
        let end = try XCTUnwrap(
            StatusAnimationPolicy.frameInterval(progress: 2, reduceMotion: false)
        )

        XCTAssertEqual(start, 0.08, accuracy: 0.001)
        XCTAssertEqual(middle, 0.18, accuracy: 0.001)
        XCTAssertEqual(end, 0.28, accuracy: 0.001)
        XCTAssertLessThan(start, middle)
        XCTAssertLessThan(middle, end)
        XCTAssertNil(StatusAnimationPolicy.frameInterval(progress: 0.5, reduceMotion: true))
    }

    func testStatesMapToStableVisualPhases() {
        let snapshot = JobSnapshot(
            actionLabel: "Converting",
            progress: 0.5,
            isEstimated: false,
            currentFile: 1,
            totalFiles: 1,
            inputBytes: nil,
            estimatedOutputBytes: nil
        )
        let result = ResultSummary(outputURLs: [], inputBytes: 100, outputBytes: 50)

        XCTAssertEqual(IslandState.idle.visualPhase, .idle)
        XCTAssertEqual(IslandState.dragHover.visualPhase, .dragTarget)
        XCTAssertEqual(IslandState.inspecting.visualPhase, .inspection)
        XCTAssertEqual(IslandState.droppedSummary([]).visualPhase, .summary)
        XCTAssertEqual(IslandState.actionSelection([]).visualPhase, .actions)
        XCTAssertEqual(IslandState.preparing.visualPhase, .progress)
        XCTAssertEqual(IslandState.converting(snapshot).visualPhase, .progress)
        XCTAssertEqual(IslandState.success(result).visualPhase, .success)
        XCTAssertEqual(
            IslandState.failure(UserFacingError(title: "Error", message: "Message")).visualPhase,
            .failure
        )
    }
}
