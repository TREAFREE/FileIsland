import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class VideoSplitDomainTests: XCTestCase {
    func testConstraintSourceUsesStableKeyedCodableRepresentation() throws {
        let customData = try JSONEncoder().encode(VideoSplitConstraintSource.custom)
        let verified = VideoSplitConstraintSource.verifiedRule(
            id: "platform-channel",
            revision: 4
        )
        let verifiedData = try JSONEncoder().encode(verified)

        let customObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: customData) as? [String: Any]
        )
        let verifiedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: verifiedData) as? [String: Any]
        )

        XCTAssertEqual(customObject["kind"] as? String, "custom")
        XCTAssertNil(customObject["id"])
        XCTAssertNil(customObject["revision"])
        XCTAssertEqual(verifiedObject["kind"] as? String, "verifiedRule")
        XCTAssertEqual(verifiedObject["id"] as? String, "platform-channel")
        XCTAssertEqual(verifiedObject["revision"] as? Int, 4)
        XCTAssertEqual(
            try JSONDecoder().decode(VideoSplitConstraintSource.self, from: customData),
            .custom
        )
        XCTAssertEqual(
            try JSONDecoder().decode(VideoSplitConstraintSource.self, from: verifiedData),
            verified
        )
    }

    func testConstraintSourceRejectsUnknownOrIncompleteRepresentations() throws {
        let unknown = Data(#"{"kind":"remoteSuggestion"}"#.utf8)
        let missingID = Data(#"{"kind":"verifiedRule","revision":2}"#.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode(VideoSplitConstraintSource.self, from: unknown)
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(VideoSplitConstraintSource.self, from: missingID)
        )
    }

    func testFrozenSplitValuesRoundTripThroughCodable() throws {
        let inputID = try XCTUnwrap(
            UUID(uuidString: "AEF2BF46-91A3-4018-8362-AB0A35C4A2D7")
        )
        let planID = try XCTUnwrap(
            UUID(uuidString: "4C2631D5-B5AE-40EB-A0E6-C451B8EC48BD")
        )
        let input = InputFile(
            id: inputID,
            url: URL(fileURLWithPath: "/tmp/电影 素材/海岛.mov"),
            type: .quickTimeMovie,
            fileSize: 123_456_789,
            displayName: "海岛 🏝️.mov"
        )
        let intent = VideoSplitIntent(
            source: .verifiedRule(id: "platform-channel", revision: 4),
            mode: .fastKeyframeCopy,
            constraints: VideoSegmentConstraints(
                maxBytes: 100_000_000,
                maxDurationMilliseconds: 300_000,
                safetyRatio: 0.92,
                requiredContainer: "mp4",
                requiredVideoCodec: "h264",
                requiredAudioCodec: "aac"
            ),
            stripMetadata: true
        )
        let segment = VideoSegmentPlan(
            index: 1,
            startMilliseconds: 0,
            endMilliseconds: 180_000,
            outputRelativePath: try SafeRelativePath("海岛 — Split/海岛-part-01-of-02.mp4"),
            estimatedBytes: 80_000_000,
            requiresReencoding: false
        )
        let plan = VideoSplitPlan(
            id: planID,
            input: input,
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            intent: intent,
            ruleSnapshot: nil,
            segments: [segment]
        )

        XCTAssertEqual(try roundTrip(VideoSplitMode.preciseCompatible), .preciseCompatible)
        XCTAssertEqual(try roundTrip(intent.constraints), intent.constraints)
        XCTAssertEqual(try roundTrip(intent), intent)
        XCTAssertEqual(try roundTrip(segment), segment)
        XCTAssertEqual(try roundTrip(plan), plan)
    }

    func testConstraintValidatorAcceptsSizeDurationOrBothAtInclusiveSafetyBounds() throws {
        let values = [
            VideoSegmentConstraints(
                maxBytes: 1,
                maxDurationMilliseconds: nil,
                safetyRatio: 0.80,
                requiredContainer: nil,
                requiredVideoCodec: nil,
                requiredAudioCodec: nil
            ),
            VideoSegmentConstraints(
                maxBytes: nil,
                maxDurationMilliseconds: 1,
                safetyRatio: 0.98,
                requiredContainer: nil,
                requiredVideoCodec: nil,
                requiredAudioCodec: nil
            ),
            VideoSegmentConstraints(
                maxBytes: 10_000_000,
                maxDurationMilliseconds: 60_000,
                safetyRatio: 0.92,
                requiredContainer: "mp4",
                requiredVideoCodec: "h264",
                requiredAudioCodec: "aac"
            )
        ]

        for constraints in values {
            XCTAssertNoThrow(try VideoSplitDomainValidator.validate(constraints: constraints))
        }
    }

    func testConstraintValidatorRejectsMissingAndNonPositiveLimits() {
        assertConstraintError(
            maxBytes: nil,
            maxDurationMilliseconds: nil,
            safetyRatio: 0.92,
            expected: .missingLimits
        )
        assertConstraintError(
            maxBytes: 0,
            maxDurationMilliseconds: nil,
            safetyRatio: 0.92,
            expected: .nonPositiveMaxBytes
        )
        assertConstraintError(
            maxBytes: -1,
            maxDurationMilliseconds: nil,
            safetyRatio: 0.92,
            expected: .nonPositiveMaxBytes
        )
        assertConstraintError(
            maxBytes: nil,
            maxDurationMilliseconds: 0,
            safetyRatio: 0.92,
            expected: .nonPositiveMaxDurationMilliseconds
        )
        assertConstraintError(
            maxBytes: nil,
            maxDurationMilliseconds: -1,
            safetyRatio: 0.92,
            expected: .nonPositiveMaxDurationMilliseconds
        )
    }

    func testConstraintValidatorRejectsNonFiniteAndOutOfRangeSafetyRatios() {
        for ratio in [Double.nan, .infinity, -.infinity, 0.79, 0.99] {
            assertConstraintError(
                maxBytes: 1_000_000,
                maxDurationMilliseconds: nil,
                safetyRatio: ratio,
                expected: .invalidSafetyRatio
            )
        }
    }

    func testSegmentValidatorRejectsInvalidIndexBoundsAndEstimate() throws {
        let path = try SafeRelativePath("Movie — Split/Movie-part-01-of-02.mp4")

        XCTAssertThrowsError(
            try VideoSplitDomainValidator.validate(
                segment: VideoSegmentPlan(
                    index: 0,
                    startMilliseconds: 0,
                    endMilliseconds: 1_000,
                    outputRelativePath: path,
                    estimatedBytes: 1,
                    requiresReencoding: false
                )
            )
        ) { XCTAssertEqual($0 as? VideoSplitValidationError, .invalidSegmentIndex) }

        for bounds in [(-1, 1_000), (1_000, 1_000), (1_001, 1_000)] {
            XCTAssertThrowsError(
                try VideoSplitDomainValidator.validate(
                    segment: VideoSegmentPlan(
                        index: 1,
                        startMilliseconds: Int64(bounds.0),
                        endMilliseconds: Int64(bounds.1),
                        outputRelativePath: path,
                        estimatedBytes: 1,
                        requiresReencoding: false
                    )
                )
            ) { XCTAssertEqual($0 as? VideoSplitValidationError, .invalidSegmentBounds) }
        }

        XCTAssertThrowsError(
            try VideoSplitDomainValidator.validate(
                segment: VideoSegmentPlan(
                    index: 1,
                    startMilliseconds: 0,
                    endMilliseconds: 1_000,
                    outputRelativePath: path,
                    estimatedBytes: -1,
                    requiresReencoding: false
                )
            )
        ) { XCTAssertEqual($0 as? VideoSplitValidationError, .negativeEstimatedBytes) }
    }

    func testPlanValidatorRequiresNonEmptyContinuousOrderedSegmentsFromZero() throws {
        let empty = makePlan(segments: [])
        XCTAssertThrowsError(try VideoSplitDomainValidator.validate(plan: empty)) {
            XCTAssertEqual($0 as? VideoSplitValidationError, .emptySegments)
        }

        let validSegments = try [
            makeSegment(index: 1, start: 0, end: 1_000),
            makeSegment(index: 2, start: 1_000, end: 2_000)
        ]
        XCTAssertNoThrow(
            try VideoSplitDomainValidator.validate(plan: makePlan(segments: validSegments))
        )

        let invalidSequences = try [
            [makeSegment(index: 2, start: 0, end: 1_000)],
            [makeSegment(index: 1, start: 1, end: 1_000)],
            [
                makeSegment(index: 1, start: 0, end: 1_000),
                makeSegment(index: 3, start: 1_000, end: 2_000)
            ],
            [
                makeSegment(index: 1, start: 0, end: 1_000),
                makeSegment(index: 2, start: 1_001, end: 2_000)
            ],
            [
                makeSegment(index: 1, start: 0, end: 1_000),
                makeSegment(index: 2, start: 999, end: 2_000)
            ]
        ]

        for segments in invalidSequences {
            XCTAssertThrowsError(
                try VideoSplitDomainValidator.validate(plan: makePlan(segments: segments))
            ) { XCTAssertEqual($0 as? VideoSplitValidationError, .invalidPlanOrdering) }
        }
    }

    func testDecimalMegabytesConversionIsExactCheckedAndRoundsDownToWholeBytes() throws {
        XCTAssertEqual(
            try VideoSplitDomainValidator.bytes(forDecimalMegabytes: Decimal(1)),
            1_000_000
        )
        XCTAssertEqual(
            try VideoSplitDomainValidator.bytes(forDecimalMegabytes: Decimal(string: "1.5")!),
            1_500_000
        )
        XCTAssertEqual(
            try VideoSplitDomainValidator.bytes(forDecimalMegabytes: Decimal(string: "1.0000009")!),
            1_000_000
        )
    }

    func testDecimalMegabytesConversionRejectsInvalidNonPositiveAndOverflowValues() {
        for value in [Decimal.nan, Decimal.zero, Decimal(-1), Decimal(string: "0.0000001")!] {
            XCTAssertThrowsError(
                try VideoSplitDomainValidator.bytes(forDecimalMegabytes: value)
            ) { XCTAssertEqual($0 as? VideoSplitValidationError, .invalidDecimalMegabytes) }
        }

        XCTAssertThrowsError(
            try VideoSplitDomainValidator.bytes(
                forDecimalMegabytes: Decimal(Int64.max)
            )
        ) { XCTAssertEqual($0 as? VideoSplitValidationError, .decimalMegabytesOverflow) }
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(value))
    }

    private func assertConstraintError(
        maxBytes: Int64?,
        maxDurationMilliseconds: Int64?,
        safetyRatio: Double,
        expected: VideoSplitValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let constraints = VideoSegmentConstraints(
            maxBytes: maxBytes,
            maxDurationMilliseconds: maxDurationMilliseconds,
            safetyRatio: safetyRatio,
            requiredContainer: nil,
            requiredVideoCodec: nil,
            requiredAudioCodec: nil
        )

        XCTAssertThrowsError(
            try VideoSplitDomainValidator.validate(constraints: constraints),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? VideoSplitValidationError,
                expected,
                file: file,
                line: line
            )
        }
    }

    private func makeSegment(
        index: Int,
        start: Int64,
        end: Int64
    ) throws -> VideoSegmentPlan {
        VideoSegmentPlan(
            index: index,
            startMilliseconds: start,
            endMilliseconds: end,
            outputRelativePath: try SafeRelativePath(
                "Movie — Split/Movie-part-\(index)-of-02.mp4"
            ),
            estimatedBytes: 1,
            requiresReencoding: false
        )
    }

    private func makePlan(segments: [VideoSegmentPlan]) -> VideoSplitPlan {
        VideoSplitPlan(
            id: UUID(uuidString: "4C2631D5-B5AE-40EB-A0E6-C451B8EC48BD")!,
            input: InputFile(
                id: UUID(uuidString: "AEF2BF46-91A3-4018-8362-AB0A35C4A2D7")!,
                url: URL(fileURLWithPath: "/tmp/Movie.mov"),
                type: .quickTimeMovie,
                fileSize: 2,
                displayName: "Movie.mov"
            ),
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: 2),
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: nil,
                    maxDurationMilliseconds: 1_000,
                    safetyRatio: 0.92,
                    requiredContainer: nil,
                    requiredVideoCodec: nil,
                    requiredAudioCodec: nil
                ),
                stripMetadata: true
            ),
            ruleSnapshot: nil,
            segments: segments
        )
    }
}
