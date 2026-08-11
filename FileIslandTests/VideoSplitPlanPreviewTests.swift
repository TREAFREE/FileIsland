import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import FileIsland

@MainActor
final class VideoSplitPlanPreviewTests: XCTestCase {
    func testPrecisePreviewCarriesPlanFactsButDoesNotExposeExecution() throws {
        let preview = VideoSplitPlanPreview(plan: try makePlan(mode: .preciseCompatible))

        XCTAssertEqual(preview.segmentCount, 3)
        XCTAssertEqual(preview.maxBytes, 100_000_000)
        XCTAssertEqual(preview.maxDurationMilliseconds, 300_000)
        XCTAssertEqual(preview.mode, .preciseCompatible)
        XCTAssertTrue(preview.requiresReencoding)
        XCTAssertFalse(preview.noSplitNeeded)
        XCTAssertFalse(preview.isExecutionAvailable)
    }

    func testAuditedFastCustomPreviewExposesExecutionOnlyWhenRuntimeIsAvailable() throws {
        let plan = try makePlan(mode: .fastKeyframeCopy)

        XCTAssertTrue(
            VideoSplitPlanPreview(
                plan: plan,
                runtimeAvailable: true
            ).isExecutionAvailable
        )
        XCTAssertFalse(VideoSplitPlanPreview(plan: plan).isExecutionAvailable)
        XCTAssertFalse(
            VideoSplitPlanPreview(
                plan: plan,
                runtimeAvailable: false
            ).isExecutionAvailable
        )
    }

    func testPreviewUsesEnglishAndSimplifiedChineseCatalogStrings() throws {
        let preview = VideoSplitPlanPreview(
            plan: try makePlan(mode: .fastKeyframeCopy),
            runtimeAvailable: true
        )
        let english = localization(language: .english)
        let chinese = localization(language: .simplifiedChinese)

        XCTAssertEqual(preview.localizedModeTitle(using: english), "Fast · keep original quality")
        XCTAssertEqual(preview.localizedModeTitle(using: chinese), "快速 · 保留原画质")
        XCTAssertEqual(preview.localizedSegmentSummary(using: english), "Estimated 3 segments")
        XCTAssertEqual(preview.localizedSegmentSummary(using: chinese), "预计 3 段")
        XCTAssertEqual(
            preview.localizedDecimalMegabyteDisclosure(using: chinese),
            "1 MB 等于 1,000,000 字节。"
        )
        XCTAssertEqual(
            preview.localizedExecutionStatus(using: chinese),
            "可以开始切分"
        )
    }

    func testSingleSegmentPreviewExplainsThatNoSplitIsNeeded() throws {
        let preview = VideoSplitPlanPreview(plan: try makePlan(mode: .fastKeyframeCopy, count: 1))
        let chinese = localization(language: .simplifiedChinese)

        XCTAssertTrue(preview.noSplitNeeded)
        XCTAssertEqual(preview.localizedSegmentSummary(using: chinese), "无需切分")
        XCTAssertNil(preview.localizedQualityNotice(using: chinese))
    }

    func testCustomLimitsUseDecimalMegabytesAndDecimalSeconds() throws {
        let limits = try VideoSplitCustomLimits.parse(
            maximumMegabytes: "12.345678",
            maximumDurationSeconds: "90.25"
        )

        XCTAssertEqual(limits.maxBytes, 12_345_678)
        XCTAssertEqual(limits.maxDurationMilliseconds, 90_250)
        XCTAssertEqual(limits.constraints.safetyRatio, 0.95)
    }

    func testCustomLimitsAcceptEitherLimitAndRejectMissingOrInvalidValues() throws {
        XCTAssertEqual(
            try VideoSplitCustomLimits.parse(
                maximumMegabytes: "",
                maximumDurationSeconds: "60"
            ).maxDurationMilliseconds,
            60_000
        )
        XCTAssertThrowsError(
            try VideoSplitCustomLimits.parse(
                maximumMegabytes: "",
                maximumDurationSeconds: ""
            )
        ) { error in
            XCTAssertEqual(error as? VideoSplitCustomLimitError, .missingLimits)
        }
        XCTAssertThrowsError(
            try VideoSplitCustomLimits.parse(
                maximumMegabytes: "1e3",
                maximumDurationSeconds: ""
            )
        ) { error in
            XCTAssertEqual(
                error as? VideoSplitCustomLimitError,
                .invalidMaximumMegabytes
            )
        }
        XCTAssertThrowsError(
            try VideoSplitCustomLimits.parse(
                maximumMegabytes: "10",
                maximumDurationSeconds: "0"
            )
        ) { error in
            XCTAssertEqual(
                error as? VideoSplitCustomLimitError,
                .invalidMaximumDuration
            )
        }
    }

    func testIncreaseContrastStrengthensCustomLimitFieldBoundary() {
        let standard = VideoSplitLimitFieldAppearance.resolve(increaseContrast: false)
        let increased = VideoSplitLimitFieldAppearance.resolve(increaseContrast: true)

        XCTAssertGreaterThan(increased.borderOpacity, standard.borderOpacity)
        XCTAssertGreaterThan(increased.borderWidth, standard.borderWidth)
    }

    func testSplitLimitUnitsPreserveCanonicalValuesWhenChanged() {
        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.convertedText(
                "500",
                from: VideoSplitSizeUnit.megabytes,
                to: .gigabytes
            ),
            "0.5"
        )
        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.canonicalText(
                "0.5",
                unit: VideoSplitSizeUnit.gigabytes
            ),
            "500"
        )
        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.convertedText(
                "120",
                from: VideoSplitDurationUnit.seconds,
                to: .minutes
            ),
            "2"
        )
        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.convertedText(
                "1.5",
                from: VideoSplitDurationUnit.hours,
                to: .minutes
            ),
            "90"
        )
    }

    func testSplitLimitUnitConversionLeavesEmptyAndInvalidInputUntouched() {
        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.convertedText(
                "",
                from: VideoSplitSizeUnit.megabytes,
                to: .gigabytes
            ),
            ""
        )
        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.convertedText(
                "not-a-number",
                from: VideoSplitDurationUnit.seconds,
                to: .minutes
            ),
            "not-a-number"
        )
    }

    func testSplitLimitSliderScalesCoverCommonRangesAndRemainMonotonic() {
        XCTAssertEqual(
            VideoSplitLimitSliderScale.canonicalMegabytes(at: 0),
            10
        )
        XCTAssertEqual(
            VideoSplitLimitSliderScale.canonicalMegabytes(at: 1),
            10_000
        )
        XCTAssertEqual(
            VideoSplitLimitSliderScale.canonicalSeconds(at: 0),
            10
        )
        XCTAssertEqual(
            VideoSplitLimitSliderScale.canonicalSeconds(at: 1),
            10_800
        )

        let sizeSamples = stride(from: 0.0, through: 1.0, by: 0.1)
            .map { VideoSplitLimitSliderScale.canonicalMegabytes(at: $0) }
        let durationSamples = stride(from: 0.0, through: 1.0, by: 0.1)
            .map { VideoSplitLimitSliderScale.canonicalSeconds(at: $0) }
        XCTAssertEqual(sizeSamples, sizeSamples.sorted())
        XCTAssertEqual(durationSamples, durationSamples.sorted())
        XCTAssertEqual(
            VideoSplitLimitSliderScale.canonicalMegabytes(
                at: VideoSplitLimitSliderScale.sizePosition(forCanonicalMegabytes: 1_000)
            ),
            1_000
        )
        XCTAssertEqual(
            VideoSplitLimitSliderScale.canonicalSeconds(
                at: VideoSplitLimitSliderScale.durationPosition(forCanonicalSeconds: 300)
            ),
            300
        )
    }

    private func makePlan(
        mode: VideoSplitMode,
        count: Int = 3
    ) throws -> VideoSplitPlan {
        let input = InputFile(
            url: URL(fileURLWithPath: "/tmp/Movie.mp4"),
            type: .mpeg4Movie,
            fileSize: 300_000_000,
            displayName: "Movie.mp4"
        )
        let constraints = VideoSegmentConstraints(
            maxBytes: 100_000_000,
            maxDurationMilliseconds: 300_000,
            safetyRatio: 0.92,
            requiredContainer: nil,
            requiredVideoCodec: nil,
            requiredAudioCodec: nil
        )
        let durationPerSegment: Int64 = 100_000
        let segments = try (0..<count).map { offset in
            VideoSegmentPlan(
                index: offset + 1,
                startMilliseconds: Int64(offset) * durationPerSegment,
                endMilliseconds: Int64(offset + 1) * durationPerSegment,
                outputRelativePath: try SafeRelativePath(
                    "Movie — Split/Movie-part-\(String(format: "%02d", offset + 1))-of-\(String(format: "%02d", count)).mp4"
                ),
                estimatedBytes: 90_000_000,
                requiresReencoding: mode == .preciseCompatible
            )
        }
        return VideoSplitPlan(
            id: UUID(),
            input: input,
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            intent: VideoSplitIntent(
                source: .custom,
                mode: mode,
                constraints: constraints,
                stripMetadata: true
            ),
            ruleSnapshot: nil,
            segments: segments
        )
    }

    private func localization(language: AppLanguage) -> LocalizationController {
        let suite = "VideoSplitPlanPreviewTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPreferences(defaults: defaults)
        let controller = LocalizationController(preferences: preferences)
        controller.language = language
        return controller
    }
}
