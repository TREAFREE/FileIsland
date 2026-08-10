import AppKit
import XCTest
@testable import FileIsland

@MainActor
final class StatusItemAnimatorTests: XCTestCase {
    func testStartAdvancesFramesAndStopInvalidatesTimer() throws {
        let scheduler = RecordingStatusTimerFactory()
        var emitted: [NSImage] = []
        let frames = [NSImage(size: NSSize(width: 1, height: 1)), NSImage(size: NSSize(width: 2, height: 2))]
        let animator = StatusItemAnimator(
            frames: frames,
            reduceMotion: { false },
            timerFactory: scheduler.makeTimer,
            setImage: { emitted.append($0) }
        )

        animator.start(progress: 0)
        XCTAssertTrue(animator.isAnimating)
        XCTAssertEqual(scheduler.intervals, [0.08])
        scheduler.fire()
        scheduler.fire()
        XCTAssertEqual(emitted.map(\.size.width), [1, 2, 1])

        animator.stop()
        XCTAssertFalse(animator.isAnimating)
        XCTAssertTrue(try XCTUnwrap(scheduler.latestTimer).isInvalidated)
    }

    func testProgressUpdateRebuildsOnlyWhenSpeedBucketChanges() {
        let scheduler = RecordingStatusTimerFactory()
        let animator = StatusItemAnimator(
            frames: [NSImage(size: NSSize(width: 1, height: 1))],
            reduceMotion: { false },
            timerFactory: scheduler.makeTimer,
            setImage: { _ in }
        )

        animator.start(progress: 0.50)
        animator.start(progress: 0.51)
        animator.start(progress: 1.0)

        XCTAssertEqual(scheduler.intervals.count, 2)
        XCTAssertEqual(scheduler.intervals[0], 0.18, accuracy: 0.001)
        XCTAssertEqual(scheduler.intervals[1], 0.28, accuracy: 0.001)
    }

    func testReduceMotionShowsOneStaticFrameWithoutTimer() {
        let scheduler = RecordingStatusTimerFactory()
        var imageCount = 0
        let animator = StatusItemAnimator(
            frames: [NSImage(size: NSSize(width: 1, height: 1))],
            reduceMotion: { true },
            timerFactory: scheduler.makeTimer,
            setImage: { _ in imageCount += 1 }
        )

        animator.start(progress: 0.4)

        XCTAssertFalse(animator.isAnimating)
        XCTAssertTrue(scheduler.intervals.isEmpty)
        XCTAssertEqual(imageCount, 1)
    }

    func testGeneratedFramesAreTemplateImages() {
        let frames = StatusIconFrameRenderer.makeFrames(count: 8)

        XCTAssertEqual(frames.count, 8)
        XCTAssertTrue(frames.allSatisfy(\.isTemplate))
    }
}

@MainActor
private final class RecordingStatusTimerFactory {
    private(set) var intervals: [TimeInterval] = []
    private(set) var latestTimer: RecordingStatusTimer?

    func makeTimer(
        interval: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any StatusAnimationTimer {
        intervals.append(interval)
        let timer = RecordingStatusTimer(action: action)
        latestTimer = timer
        return timer
    }

    func fire() { latestTimer?.fire() }
}

@MainActor
private final class RecordingStatusTimer: StatusAnimationTimer {
    private let action: @MainActor () -> Void
    private(set) var isInvalidated = false

    init(action: @escaping @MainActor () -> Void) { self.action = action }
    func fire() { guard !isInvalidated else { return }; action() }
    func invalidate() { isInvalidated = true }
}
