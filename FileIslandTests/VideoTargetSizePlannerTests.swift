import CoreGraphics
import XCTest
@testable import FileIsland

final class VideoTargetSizePlannerTests: XCTestCase {
    func testUsesSafetyBudgetAndReservesAACBitRate() throws {
        let plan = try VideoTargetSizePlanner().makePlan(
            targetBytes: 50_000_000,
            duration: 120,
            hasAudio: true,
            sourceDisplaySize: CGSize(width: 3840, height: 2160),
            requestedResolution: .p1080
        )

        XCTAssertEqual(plan.fileLengthLimit, 47_500_000)
        XCTAssertEqual(plan.totalBitRate, 3_166_666)
        XCTAssertEqual(plan.audioBitRate, 128_000)
        XCTAssertEqual(plan.videoBitRate, 3_038_666)
        XCTAssertEqual(plan.exportTiers, [.p1080, .p720, .p540, .p480])
    }

    func testSourceCeilingUsesSourceGeometryAndAvailableBitRate() throws {
        let fourK = try VideoTargetSizePlanner().makePlan(
            targetBytes: 100_000_000,
            duration: 60,
            hasAudio: false,
            sourceDisplaySize: CGSize(width: 3840, height: 2160),
            requestedResolution: .source
        )
        let fullHD = try VideoTargetSizePlanner().makePlan(
            targetBytes: 100_000_000,
            duration: 60,
            hasAudio: false,
            sourceDisplaySize: CGSize(width: 1920, height: 1080),
            requestedResolution: .source
        )

        XCTAssertEqual(fourK.exportTiers.first, .p2160)
        XCTAssertEqual(fullHD.exportTiers, [.p1080, .p720, .p540, .p480])
    }

    func testLowBudgetStartsAt480pWhenStillReachable() throws {
        let plan = try VideoTargetSizePlanner().makePlan(
            targetBytes: 5_000_000,
            duration: 120,
            hasAudio: false,
            sourceDisplaySize: CGSize(width: 1920, height: 1080),
            requestedResolution: .source
        )

        XCTAssertEqual(plan.exportTiers, [.p480])
        XCTAssertEqual(plan.videoBitRate, plan.totalBitRate)
    }

    func testRejectsInvalidAndUnreachableBudgets() {
        assertThrows(.targetSizeUnreachable) {
            _ = try VideoTargetSizePlanner().makePlan(
                targetBytes: 0,
                duration: 60,
                hasAudio: false,
                sourceDisplaySize: CGSize(width: 1920, height: 1080),
                requestedResolution: .source
            )
        }
        assertThrows(.targetSizeUnreachable) {
            _ = try VideoTargetSizePlanner().makePlan(
                targetBytes: 5_000_000,
                duration: 120,
                hasAudio: true,
                sourceDisplaySize: CGSize(width: 1920, height: 1080),
                requestedResolution: .source
            )
        }
    }

    private func assertThrows(
        _ expected: ConversionError,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation()) { error in
            XCTAssertEqual(error as? ConversionError, expected)
        }
    }
}
