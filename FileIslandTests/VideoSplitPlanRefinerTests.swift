import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("Fast video split plan refinement")
struct VideoSplitPlanRefinerTests {
    @Test("An oversized segment moves the global interval to an earlier keyframe")
    func refinesToEarlierKeyframe() throws {
        let (plan, source) = try fixture(
            planBoundaries: [0, 3_000, 6_000, 10_000],
            keyframes: [0, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 9_000]
        )

        let refined = try VideoSplitPlanRefiner().refine(
            plan,
            source: source,
            failedSegmentIndex: 1
        )

        #expect(refined.id == plan.id)
        #expect(refined.segments.map(\.endMilliseconds) == [2_000, 4_000, 6_000, 8_000, 10_000])
        #expect(refined.segments.map(\.index) == [1, 2, 3, 4, 5])
        #expect(refined.segments.last?.outputRelativePath.string.hasSuffix("part-05-of-05.mp4") == true)
    }

    @Test("A failed tail can be shortened when it contains an earlier keyframe")
    func refinesTail() throws {
        let (plan, source) = try fixture(
            planBoundaries: [0, 3_000, 6_000, 10_000],
            keyframes: [0, 3_000, 6_000, 7_000, 8_000, 9_000]
        )

        let refined = try VideoSplitPlanRefiner().refine(
            plan,
            source: source,
            failedSegmentIndex: 3
        )

        #expect(refined.segments.map(\.endMilliseconds) == [3_000, 6_000, 9_000, 10_000])
    }

    @Test("Sparse keyframes and invalid indices fail closed")
    func rejectsUnreachableRefinement() throws {
        let (plan, source) = try fixture(
            planBoundaries: [0, 3_000, 6_000],
            keyframes: [0, 3_000]
        )
        #expect(throws: VideoSplitRefinementError.noEarlierKeyframe) {
            try VideoSplitPlanRefiner().refine(
                plan,
                source: source,
                failedSegmentIndex: 1
            )
        }
        #expect(throws: VideoSplitRefinementError.invalidFailedSegment) {
            try VideoSplitPlanRefiner().refine(
                plan,
                source: source,
                failedSegmentIndex: 9
            )
        }
    }

    private func fixture(
        planBoundaries: [Int64],
        keyframes: [Int64]
    ) throws -> (VideoSplitPlan, VideoSplitSourceFacts) {
        let input = InputFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000163")!,
            url: URL(fileURLWithPath: "/private/tmp/Movie.mp4"),
            type: .mpeg4Movie,
            fileSize: 10_000_000,
            displayName: "Movie.mp4"
        )
        let count = planBoundaries.count - 1
        let segments = try (0..<count).map { offset in
            VideoSegmentPlan(
                index: offset + 1,
                startMilliseconds: planBoundaries[offset],
                endMilliseconds: planBoundaries[offset + 1],
                outputRelativePath: try SafeRelativePath(
                    "Movie — Split/Movie-part-\(offset + 1)-of-\(count).mp4"
                ),
                estimatedBytes: 3_000_000,
                requiresReencoding: false
            )
        }
        let plan = VideoSplitPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000016D")!,
            input: input,
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: 4_000_000,
                    maxDurationMilliseconds: 4_000,
                    safetyRatio: 0.9,
                    requiredContainer: nil,
                    requiredVideoCodec: nil,
                    requiredAudioCodec: nil
                ),
                stripMetadata: true
            ),
            ruleSnapshot: nil,
            segments: segments
        )
        let source = VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            durationMilliseconds: planBoundaries.last!,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: 8_000_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 0,
            audioStartMilliseconds: 0,
            audioDurationMilliseconds: planBoundaries.last!,
            userMetadataKeys: [],
            frameDurationMilliseconds: 1_000 / 30,
            keyframeMilliseconds: keyframes
        )
        return (plan, source)
    }
}
