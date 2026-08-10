import XCTest
@testable import FileIsland

final class IslandProgressVisualTests: XCTestCase {
    func testPreparingUsesIndeterminateHighlightUnlessMotionIsReduced() {
        let animated = IslandProgressVisual(state: .preparing, reduceMotion: false)
        let reduced = IslandProgressVisual(state: .preparing, reduceMotion: true)

        XCTAssertTrue(animated.isVisible)
        XCTAssertNil(animated.fraction)
        XCTAssertTrue(animated.animatesHighlight)
        XCTAssertTrue(reduced.isVisible)
        XCTAssertNil(reduced.fraction)
        XCTAssertFalse(reduced.animatesHighlight)
    }

    func testConvertingClampsTheRealProgressFraction() {
        XCTAssertEqual(
            IslandProgressVisual(
                state: .converting(snapshot(progress: -1)),
                reduceMotion: false
            ).fraction,
            0
        )
        XCTAssertEqual(
            IslandProgressVisual(
                state: .converting(snapshot(progress: 2)),
                reduceMotion: false
            ).fraction,
            1
        )
    }

    func testNonProcessingStatesHideTheBorder() {
        XCTAssertFalse(IslandProgressVisual(state: .idle, reduceMotion: false).isVisible)
        XCTAssertFalse(IslandProgressVisual(state: .dragHover, reduceMotion: false).isVisible)
    }

    private func snapshot(progress: Double) -> JobSnapshot {
        JobSnapshot(
            actionLabel: "Converting",
            progress: progress,
            isEstimated: false,
            currentFile: 1,
            totalFiles: 1,
            inputBytes: nil,
            estimatedOutputBytes: nil
        )
    }
}
