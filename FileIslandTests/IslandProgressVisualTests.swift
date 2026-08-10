import XCTest
@testable import FileIsland

final class IslandProgressVisualTests: XCTestCase {
    func testPreparingUsesIndeterminateHighlightUnlessMotionIsReduced() {
        let animated = IslandProgressVisual(state: .preparing, reduceMotion: false)
        let reduced = IslandProgressVisual(state: .preparing, reduceMotion: true)

        XCTAssertEqual(animated.style, .indeterminate)
        XCTAssertTrue(animated.animatesComet)
        XCTAssertEqual(reduced.style, .indeterminate)
        XCTAssertFalse(reduced.animatesComet)
    }

    func testConvertingClampsTheRealProgressFraction() {
        XCTAssertEqual(
            IslandProgressVisual(
                state: .converting(snapshot(progress: -1)),
                reduceMotion: false
            ).style,
            .determinate(0)
        )
        XCTAssertEqual(
            IslandProgressVisual(
                state: .converting(snapshot(progress: 2)),
                reduceMotion: false
            ).style,
            .determinate(1)
        )
    }

    func testDeterminateProgressDoesNotRunAnIndependentChaseAnimation() {
        let visual = IslandProgressVisual(
            state: .converting(snapshot(progress: 0.42)),
            reduceMotion: false
        )

        XCTAssertEqual(visual.style, .determinate(0.42))
        XCTAssertFalse(visual.animatesComet)
    }

    func testNonProcessingStatesHideTheBorder() {
        XCTAssertEqual(IslandProgressVisual(state: .idle, reduceMotion: false).style, .hidden)
        XCTAssertEqual(IslandProgressVisual(state: .dragHover, reduceMotion: false).style, .hidden)
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
