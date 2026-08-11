import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class VideoSplitPlanBuilderTests: XCTestCase {
    private let builder = VideoSplitPlanBuilder()

    func testPrecisePlanUsesSizeOnlyEffectiveBudgetAndCoversTimeline() throws {
        let plan = try makePlan(
            durationMilliseconds: 10_000,
            fileSize: 10_000_000,
            intent: makeIntent(
                mode: .preciseCompatible,
                maxBytes: 5_000_000,
                safetyRatio: 0.8
            )
        )

        XCTAssertEqual(plan.segments.map(\.startMilliseconds), [0, 4_000, 8_000])
        XCTAssertEqual(plan.segments.map(\.endMilliseconds), [4_000, 8_000, 10_000])
        XCTAssertTrue(plan.segments.allSatisfy(\.requiresReencoding))
        XCTAssertEqual(plan.segments.map(\.estimatedBytes), [4_000_000, 4_000_000, 2_000_000])
    }

    func testPrecisePlanUsesDurationOnlyAndCombinedConstraintChoosesStricterLimit() throws {
        let durationOnly = try makePlan(
            durationMilliseconds: 11_000,
            intent: makeIntent(
                mode: .preciseCompatible,
                maxDurationMilliseconds: 5_000,
                safetyRatio: 0.9
            )
        )
        XCTAssertEqual(durationOnly.segments.map(\.endMilliseconds), [4_500, 9_000, 11_000])

        let combined = try makePlan(
            durationMilliseconds: 10_000,
            fileSize: 10_000_000,
            intent: makeIntent(
                mode: .preciseCompatible,
                maxBytes: 8_000_000,
                maxDurationMilliseconds: 4_000,
                safetyRatio: 0.9
            )
        )
        XCTAssertEqual(combined.segments.map(\.endMilliseconds), [3_600, 7_200, 10_000])
    }

    func testFastPlanMovesBoundariesBackwardToSafeKeyframes() throws {
        let plan = try makePlan(
            durationMilliseconds: 10_000,
            intent: makeIntent(
                mode: .fastKeyframeCopy,
                maxDurationMilliseconds: 5_000,
                safetyRatio: 0.98
            ),
            keyframes: [0, 3_000, 6_000, 9_000]
        )

        XCTAssertEqual(plan.segments.map(\.startMilliseconds), [0, 3_000, 6_000])
        XCTAssertEqual(plan.segments.map(\.endMilliseconds), [3_000, 6_000, 10_000])
        XCTAssertTrue(plan.segments.allSatisfy { !$0.requiresReencoding })
    }

    func testFastSizeOnlyAndCombinedBudgetsUseTheStricterCutTimeline() throws {
        let sizeOnly = try makePlan(
            durationMilliseconds: 10_000,
            fileSize: 10_000_000,
            intent: makeIntent(
                mode: .fastKeyframeCopy,
                maxBytes: 5_000_000,
                safetyRatio: 0.8
            ),
            keyframes: [0, 2_000, 4_000, 6_000, 8_000]
        )
        XCTAssertEqual(sizeOnly.segments.map(\.endMilliseconds), [4_000, 8_000, 10_000])

        let combined = try makePlan(
            durationMilliseconds: 10_000,
            fileSize: 10_000_000,
            intent: makeIntent(
                mode: .fastKeyframeCopy,
                maxBytes: 8_000_000,
                maxDurationMilliseconds: 4_000,
                safetyRatio: 0.8
            ),
            keyframes: [0, 2_000, 4_000, 6_000, 8_000]
        )
        XCTAssertEqual(
            combined.segments.map(\.endMilliseconds),
            [2_000, 4_000, 6_000, 8_000, 10_000]
        )
    }

    func testFastPlanFailsClosedWhenKeyframeSpacingCannotMeetLimit() {
        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 10_000,
                intent: makeIntent(
                    mode: .fastKeyframeCopy,
                    maxDurationMilliseconds: 5_000,
                    safetyRatio: 0.98
                ),
                keyframes: [0, 6_000]
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .keyframeSpacingUnreachable)
        }
    }

    func testAlreadyCompliantSourceProducesOneSegmentDespiteSafetyBudget() throws {
        let plan = try makePlan(
            durationMilliseconds: 4_900,
            fileSize: 4_900_000,
            intent: makeIntent(
                mode: .fastKeyframeCopy,
                maxBytes: 5_000_000,
                maxDurationMilliseconds: 5_000,
                safetyRatio: 0.8
            ),
            keyframes: [0]
        )

        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].startMilliseconds, 0)
        XCTAssertEqual(plan.segments[0].endMilliseconds, 4_900)
        XCTAssertEqual(plan.segments[0].estimatedBytes, 4_900_000)
    }

    func testOutputPathsAreSafeUnicodeAndLexicallyOrderedAcrossDigitBoundary() throws {
        let plan = try makePlan(
            durationMilliseconds: 100_000,
            displayName: "旅行 2026.mp4",
            intent: makeIntent(
                mode: .preciseCompatible,
                maxDurationMilliseconds: 10_205,
                safetyRatio: 0.98
            )
        )

        XCTAssertEqual(plan.segments.count, 10)
        XCTAssertEqual(
            plan.segments.first?.outputRelativePath.string,
            "旅行 2026 — Split/旅行 2026-part-01-of-10.mp4"
        )
        XCTAssertEqual(
            plan.segments.last?.outputRelativePath.string,
            "旅行 2026 — Split/旅行 2026-part-10-of-10.mp4"
        )
        XCTAssertEqual(
            plan.segments.map(\.outputRelativePath.string),
            plan.segments.map(\.outputRelativePath.string).sorted()
        )
    }

    func testRejectsSubsecondNonTailSegmentsAndMoreThan999Segments() {
        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 3_000,
                intent: makeIntent(
                    mode: .preciseCompatible,
                    maxDurationMilliseconds: 900,
                    safetyRatio: 0.9
                )
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .splitTargetUnreachable)
        }

        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 1_000_000,
                intent: makeIntent(
                    mode: .preciseCompatible,
                    maxDurationMilliseconds: 1_021,
                    safetyRatio: 0.98
                )
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .tooManySegments)
        }
    }

    func testAcceptsExactly999SegmentsAndUsesThreeDigitOrderingAt100() throws {
        let constraints = makeIntent(
            mode: .preciseCompatible,
            maxDurationMilliseconds: 1_021,
            safetyRatio: 0.98
        )
        let maximum = try makePlan(
            durationMilliseconds: 999_000,
            intent: constraints,
            keyframes: [0]
        )
        XCTAssertEqual(maximum.segments.count, 999)
        XCTAssertEqual(
            maximum.segments.last?.outputRelativePath.string,
            "Movie — Split/Movie-part-999-of-999.mp4"
        )

        let hundred = try makePlan(
            durationMilliseconds: 100_000,
            intent: constraints,
            keyframes: [0]
        )
        XCTAssertEqual(hundred.segments.count, 100)
        XCTAssertEqual(
            hundred.segments.first?.outputRelativePath.string,
            "Movie — Split/Movie-part-001-of-100.mp4"
        )
    }

    func testFastModeRejectsRequiredCodecThatWouldNeedReencoding() {
        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 10_000,
                intent: makeIntent(
                    mode: .fastKeyframeCopy,
                    maxDurationMilliseconds: 5_000,
                    safetyRatio: 0.98,
                    requiredVideoCodec: "hevc"
                ),
                keyframes: [0, 4_000, 8_000]
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .requiredMediaIncompatible)
        }
    }

    func testArithmeticAtRoundedInt64BoundaryFailsInsteadOfTrapping() {
        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 20_000,
                fileSize: 1,
                intent: makeIntent(
                    mode: .preciseCompatible,
                    maxBytes: Int64.max,
                    maxDurationMilliseconds: 10_204,
                    safetyRatio: 0.98
                ),
                averageBitrateBitsPerSecond: 7_840
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .splitTargetUnreachable)
        }
    }

    func testObservedFileSizePreventsAFalseNoSplitSizeEstimate() throws {
        let plan = try makePlan(
            durationMilliseconds: 10_000,
            fileSize: 10_000_000,
            intent: makeIntent(
                mode: .fastKeyframeCopy,
                maxBytes: 5_000_000,
                safetyRatio: 0.8
            ),
            keyframes: [0, 2_000, 4_000, 6_000, 8_000],
            averageBitrateBitsPerSecond: 1_000_000
        )

        XCTAssertEqual(plan.segments.map(\.endMilliseconds), [4_000, 8_000, 10_000])
    }

    func testSourceFactsCannotBeReusedForAnotherInput() {
        let intent = makeIntent(
            mode: .preciseCompatible,
            maxDurationMilliseconds: 5_000,
            safetyRatio: 0.92
        )
        let otherID = UUID()
        let otherURL = URL(fileURLWithPath: "/tmp/Other.mp4")
        let facts = VideoSplitSourceFacts(
            inputID: otherID,
            sourceURL: otherURL,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: 10_000_000),
            durationMilliseconds: 10_000,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: 8_000_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 0,
            audioStartMilliseconds: 0,
            audioDurationMilliseconds: 10_000,
            userMetadataKeys: [],
            frameDurationMilliseconds: 1_000 / 30,
            keyframeMilliseconds: [0]
        )
        let input = InputFile(
            url: URL(fileURLWithPath: "/tmp/Movie.mp4"),
            type: .mpeg4Movie,
            fileSize: 10_000_000,
            displayName: "Movie.mp4"
        )

        XCTAssertThrowsError(
            try builder.makePlan(
                input: input,
                intent: intent,
                source: facts,
                sharingRuleCatalog: nil
            )
        ) {
            XCTAssertEqual(
                $0 as? VideoSplitPlanningError,
                .invalidProbe(.inputIdentityMismatch)
            )
        }
    }

    func testFolderRelativeParentsKeepSameNamedVideosDistinct() throws {
        let intent = makeIntent(
            mode: .preciseCompatible,
            maxDurationMilliseconds: 5_000,
            safetyRatio: 0.8
        )
        let first = try makePlan(
            durationMilliseconds: 10_000,
            intent: intent,
            inputRelativePath: SafeRelativePath("旅行/第一天/Movie.mp4")
        )
        let second = try makePlan(
            durationMilliseconds: 10_000,
            intent: intent,
            inputRelativePath: SafeRelativePath("旅行/第二天/Movie.mp4")
        )

        XCTAssertEqual(
            first.segments.first?.outputRelativePath.string,
            "旅行/第一天/Movie — Split/Movie-part-01-of-03.mp4"
        )
        XCTAssertEqual(
            second.segments.first?.outputRelativePath.string,
            "旅行/第二天/Movie — Split/Movie-part-01-of-03.mp4"
        )
        XCTAssertNotEqual(
            first.segments.first?.outputRelativePath,
            second.segments.first?.outputRelativePath
        )
    }

    func testVerifiedRuleRequiresMatchingUnexpiredImmutableSnapshot() throws {
        let planningDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-11T00:00:00Z")
        )
        let rule = SharingRule(
            id: "platform-channel",
            revision: 3,
            platform: "Platform",
            channel: "Upload",
            displayName: "Platform · Upload",
            maxBytes: 100_000_000,
            maxDurationMilliseconds: 300_000,
            safetyRatio: 0.92,
            acceptedContainers: [.mp4],
            acceptedVideoCodecs: [.h264],
            acceptedAudioCodecs: [.aac],
            sourceURLs: [URL(string: "https://example.com/official")!],
            lastVerifiedAt: planningDate.addingTimeInterval(-86_400),
            expiresAt: planningDate.addingTimeInterval(86_400)
        )
        let intent = VideoSplitIntent(
            source: .verifiedRule(id: rule.id, revision: rule.revision),
            mode: .fastKeyframeCopy,
            constraints: VideoSegmentConstraints(
                maxBytes: rule.maxBytes,
                maxDurationMilliseconds: rule.maxDurationMilliseconds,
                safetyRatio: rule.safetyRatio,
                requiredContainer: "mp4",
                requiredVideoCodec: "h264",
                requiredAudioCodec: "aac"
            ),
            stripMetadata: true
        )

        let plan = try makePlan(
            durationMilliseconds: 600_000,
            intent: intent,
            keyframes: stride(from: Int64(0), to: 600_000, by: 60_000).map { $0 },
            sharingRuleCatalog: SharingRuleCatalog(
                schemaVersion: 1,
                catalogVersion: "2026.08",
                rules: [rule]
            ),
            planningDate: planningDate
        )

        XCTAssertEqual(plan.ruleSnapshot, rule.snapshot)
        XCTAssertEqual(plan.ruleSnapshot?.revision, 3)

        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 600_000,
                intent: intent,
                keyframes: [0, 60_000, 120_000, 180_000, 240_000, 300_000],
                sharingRuleCatalog: nil,
                planningDate: planningDate
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .invalidRuleSnapshot)
        }
        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 600_000,
                intent: intent,
                keyframes: [0, 60_000, 120_000, 180_000, 240_000, 300_000],
                sharingRuleCatalog: SharingRuleCatalog(
                    schemaVersion: 1,
                    catalogVersion: "2026.08",
                    rules: [rule]
                ),
                planningDate: rule.expiresAt
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .sharingRuleExpired)
        }

        let newerRule = SharingRule(
            id: rule.id,
            revision: 4,
            platform: rule.platform,
            channel: rule.channel,
            displayName: rule.displayName,
            maxBytes: rule.maxBytes,
            maxDurationMilliseconds: rule.maxDurationMilliseconds,
            safetyRatio: rule.safetyRatio,
            acceptedContainers: rule.acceptedContainers,
            acceptedVideoCodecs: rule.acceptedVideoCodecs,
            acceptedAudioCodecs: rule.acceptedAudioCodecs,
            sourceURLs: rule.sourceURLs,
            lastVerifiedAt: rule.lastVerifiedAt,
            expiresAt: rule.expiresAt
        )
        XCTAssertThrowsError(
            try makePlan(
                durationMilliseconds: 600_000,
                intent: intent,
                keyframes: [0, 60_000, 120_000, 180_000, 240_000, 300_000],
                sharingRuleCatalog: SharingRuleCatalog(
                    schemaVersion: 1,
                    catalogVersion: "2026.08",
                    rules: [newerRule]
                ),
                planningDate: planningDate
            )
        ) {
            XCTAssertEqual($0 as? VideoSplitPlanningError, .invalidRuleSnapshot)
        }
    }

    private func makePlan(
        durationMilliseconds: Int64,
        fileSize: Int64 = 100_000_000,
        displayName: String = "Movie.mp4",
        intent: VideoSplitIntent,
        keyframes: [Int64] = [0, 2_000, 4_000, 6_000, 8_000],
        averageBitrateBitsPerSecond: Int64 = 8_000_000,
        sharingRuleCatalog: SharingRuleCatalog? = nil,
        inputRelativePath: SafeRelativePath? = nil,
        planningDate: Date = Date(timeIntervalSince1970: 0)
    ) throws -> VideoSplitPlan {
        let input = InputFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            url: URL(fileURLWithPath: "/tmp/\(displayName)"),
            type: .mpeg4Movie,
            fileSize: fileSize,
            displayName: displayName
        )
        let facts = VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: fileSize),
            durationMilliseconds: durationMilliseconds,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: averageBitrateBitsPerSecond,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 0,
            audioStartMilliseconds: 0,
            audioDurationMilliseconds: durationMilliseconds,
            userMetadataKeys: [],
            frameDurationMilliseconds: 1_000 / 30,
            keyframeMilliseconds: keyframes.filter { $0 < durationMilliseconds }
        )
        return try builder.makePlan(
            input: input,
            intent: intent,
            source: facts,
            sharingRuleCatalog: sharingRuleCatalog,
            inputRelativePath: inputRelativePath,
            planningDate: planningDate
        )
    }

    private func makeIntent(
        mode: VideoSplitMode,
        maxBytes: Int64? = nil,
        maxDurationMilliseconds: Int64? = nil,
        safetyRatio: Double,
        requiredVideoCodec: String? = nil
    ) -> VideoSplitIntent {
        VideoSplitIntent(
            source: .custom,
            mode: mode,
            constraints: VideoSegmentConstraints(
                maxBytes: maxBytes,
                maxDurationMilliseconds: maxDurationMilliseconds,
                safetyRatio: safetyRatio,
                requiredContainer: nil,
                requiredVideoCodec: requiredVideoCodec,
                requiredAudioCodec: nil
            ),
            stripMetadata: true
        )
    }
}
