import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("Fast video split output validation")
struct VideoSplitOutputValidatorTests {
    @Test("The live decoder reads the first frame of the audited fixture")
    func liveDecoderReadsFirstFrame() async throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/task016-keyframes.mp4")
        let helperURL = try #require(
            Bundle.main.url(forAuxiliaryExecutable: "FileIslandMediaValidator")
        )

        #expect(
            try await AVFoundationVideoSplitSegmentDecodabilityChecker(
                helperExecutableURL: helperURL
            )
                .canDecodeFirstFrame(at: fixtureURL)
        )
    }

    @Test("The live decoder never accepts arbitrary bytes as a video frame")
    func liveDecoderRejectsInvalidMedia() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-Invalid-Video-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let invalidURL = root.appendingPathComponent("invalid.mp4")
        try Data([0x00, 0x01, 0x02]).write(to: invalidURL)
        let helperURL = try #require(
            Bundle.main.url(forAuxiliaryExecutable: "FileIslandMediaValidator")
        )

        do {
            let accepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
                helperExecutableURL: helperURL
            )
                .canDecodeFirstFrame(at: invalidURL)
            #expect(accepted == false)
        } catch {
            // A parser/reader error is also a fail-closed result.
        }
    }

    @Test("A complete manifest is probed and returned in plan order")
    func validatesCompleteManifestByArtifactIdentity() async throws {
        let fixture = try Fixture(fileByteCounts: [3, 4])
        defer { fixture.remove() }
        let validator = makeValidator(
            probe: StubProbe { input in fixture.outputFacts(for: input) }
        )

        let result = try await validator.validate(
            plan: fixture.plan,
            source: fixture.source,
            stagedArtifacts: Array(fixture.stagedArtifacts.reversed()),
            stagingRoot: fixture.stagingRoot
        )

        #expect(result.segments.map(\.index) == [1, 2])
        #expect(result.segments.map(\.artifact.id) == fixture.plannedArtifactIDs)
        #expect(result.segments.map(\.actualBytes) == [3, 4])
        #expect(result.totalBytes == 7)
    }

    @Test("An inexact typed manifest is rejected before any media probe")
    func rejectsManifestBeforeProbe() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let probe = CountingProbe { input in fixture.outputFacts(for: input) }
        let validator = makeValidator(probe: probe)

        await expectFailure(.invalidManifest) {
            try await validator.validate(
                plan: fixture.plan,
                source: fixture.source,
                stagedArtifacts: [fixture.stagedArtifacts[0]],
                stagingRoot: fixture.stagingRoot
            )
        }

        let callCount = await probe.callCount()
        #expect(callCount == 0)
    }

    @Test("Audited H.264 segments without an audio stream are accepted")
    func acceptsNoAudioSourceAndOutputs() async throws {
        let fixture = try Fixture(sourceAudioCodec: nil)
        defer { fixture.remove() }
        let validator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(for: input, audioCodec: nil)
            }
        )

        let result = try await fixture.validate(with: validator)

        #expect(result.segments.allSatisfy { $0.actualFacts.audioCodec == nil })
    }

    @Test("The original byte limit reports the exact oversized segment")
    func rejectsOversizedSegment() async throws {
        let fixture = try Fixture(maxBytes: 4, fileByteCounts: [4, 5])
        defer { fixture.remove() }
        let validator = fixture.validator()

        await expectFailure(
            .exceedsMaximumBytes(
                segmentIndex: 2,
                actualBytes: 5,
                maximumBytes: 4
            )
        ) {
            try await fixture.validate(with: validator)
        }
    }

    @Test("Duration uses the original limit plus one-frame-or-100ms tolerance")
    func rejectsOverDurationSegment() async throws {
        let fixture = try Fixture(maxDurationMilliseconds: 1_000)
        defer { fixture.remove() }
        let validator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    durationMilliseconds: fixture.index(for: input.url) == 2 ? 1_101 : 1_000
                )
            }
        )

        await expectFailure(
            .exceedsMaximumDuration(
                segmentIndex: 2,
                actualDurationMilliseconds: 1_101,
                maximumDurationMilliseconds: 1_000,
                toleranceMilliseconds: 100
            )
        ) {
            try await fixture.validate(with: validator)
        }
    }

    @Test("Container and video codec must match the audited source")
    func rejectsContainerAndVideoCodecChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let containerValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    container: fixture.index(for: input.url) == 2 ? "mov" : "mp4"
                )
            }
        )
        await expectFailure(.containerMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: containerValidator)
        }

        let codecValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    videoCodec: fixture.index(for: input.url) == 2 ? "vp9" : "h264"
                )
            }
        )
        await expectFailure(.videoCodecMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: codecValidator)
        }
    }

    @Test("Audio presence and codec must match the source")
    func rejectsAudioRemovalAndCodecChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let missingAudioValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    audioCodec: fixture.index(for: input.url) == 2 ? nil : "aac"
                )
            }
        )
        await expectFailure(.audioPresenceMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: missingAudioValidator)
        }

        let changedAudioValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    audioCodec: fixture.index(for: input.url) == 2 ? "mp3" : "aac"
                )
            }
        )
        await expectFailure(.audioCodecMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: changedAudioValidator)
        }
    }

    @Test("Exact display dimensions and quadrant rotation must be preserved")
    func rejectsDisplayGeometryOrRotationChange() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let dimensionsValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    displayWidth: fixture.index(for: input.url) == 2 ? 1_280 : 1_920,
                    displayHeight: fixture.index(for: input.url) == 2 ? 720 : 1_080
                )
            }
        )
        await expectFailure(.orientationMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: dimensionsValidator)
        }

        for changedRotation in [90, 180, 270] {
            let rotationValidator = makeValidator(
                probe: StubProbe { input in
                    fixture.outputFacts(
                        for: input,
                        rotationDegrees: fixture.index(for: input.url) == 2
                            ? changedRotation
                            : 0
                    )
                }
            )
            await expectFailure(.orientationMismatch(segmentIndex: 2)) {
                try await fixture.validate(with: rotationValidator)
            }
        }
    }

    @Test("Metadata removal is enforced only when the plan requests it")
    func validatesMetadataRemovalIntent() async throws {
        let strippingFixture = try Fixture(stripMetadata: true)
        defer { strippingFixture.remove() }
        let strippingValidator = makeValidator(
            probe: StubProbe { input in
                strippingFixture.outputFacts(
                    for: input,
                    userMetadataKeys: strippingFixture.index(for: input.url) == 2
                        ? ["title"]
                        : []
                )
            }
        )
        await expectFailure(.metadataNotRemoved(segmentIndex: 2)) {
            try await strippingFixture.validate(with: strippingValidator)
        }

        let preservingFixture = try Fixture(stripMetadata: false)
        defer { preservingFixture.remove() }
        let preservingValidator = makeValidator(
            probe: StubProbe { input in
                preservingFixture.outputFacts(
                    for: input,
                    userMetadataKeys: ["comment", "title"]
                )
            }
        )
        let output = try await preservingFixture.validate(with: preservingValidator)
        #expect(output.segments.allSatisfy {
            $0.actualFacts.userMetadataKeys == ["comment", "title"]
        })
    }

    @Test("Audio start and duration must remain aligned with each video segment")
    func rejectsAudioTimingDrift() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let startDriftValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    audioStartMilliseconds: fixture.index(for: input.url) == 2 ? 251 : 0
                )
            }
        )
        await expectFailure(.audioTimingMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: startDriftValidator)
        }

        let durationDriftValidator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    audioDurationMilliseconds: fixture.index(for: input.url) == 2
                        ? 749
                        : nil
                )
            }
        )
        await expectFailure(.audioTimingMismatch(segmentIndex: 2)) {
            try await fixture.validate(with: durationDriftValidator)
        }
    }

    @Test("Every segment must begin on an independently decodable frame")
    func rejectsNonKeyframeStart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let validator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(
                    for: input,
                    keyframeMilliseconds: fixture.index(for: input.url) == 2 ? [40] : [0]
                )
            }
        )

        await expectFailure(.firstFrameNotIndependentlyDecodable(segmentIndex: 2)) {
            try await fixture.validate(with: validator)
        }
    }

    @Test("A zero-time keyframe flag is insufficient when real decoding fails")
    func rejectsUndecodableKeyframeFlag() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let validator = makeValidator(
            probe: StubProbe { input in fixture.outputFacts(for: input) },
            decodability: StubDecodabilityChecker { url in
                fixture.index(for: url) != 2
            }
        )

        await expectFailure(.firstFrameNotIndependentlyDecodable(segmentIndex: 2)) {
            try await fixture.validate(with: validator)
        }
    }

    @Test("Small per-segment drift cannot accumulate into a timeline gap")
    func rejectsAccumulatedTimelineDrift() async throws {
        let fixture = try Fixture(
            segmentCount: 6,
            durationPerSegmentMilliseconds: 1_000,
            maxDurationMilliseconds: 2_000
        )
        defer { fixture.remove() }
        let validator = makeValidator(
            probe: StubProbe { input in
                fixture.outputFacts(for: input, durationMilliseconds: 900)
            }
        )

        await expectFailure(
            .timelineCoverageMismatch(
                actualDurationMilliseconds: 5_400,
                sourceDurationMilliseconds: 6_000,
                toleranceMilliseconds: 500
            )
        ) {
            try await fixture.validate(with: validator)
        }
    }

    @Test("Probe and manifest failures expose no private path")
    func redactsUnderlyingPaths() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let secret = "/Users/real-person/Private Movie.mp4"
        let validator = makeValidator(
            probe: StubProbe { _ in throw PrivateProbeError.message(secret) }
        )

        do {
            _ = try await fixture.validate(with: validator)
            Issue.record("Expected the probe to fail")
        } catch {
            #expect(error as? VideoSplitOutputValidationError == .probeFailed(segmentIndex: 1))
            #expect(String(reflecting: error).contains(secret) == false)
            #expect(String(describing: error).contains("Users") == false)
        }

        let escaped = StagedOutputArtifact(
            id: fixture.stagedArtifacts[0].id,
            fileURL: URL(fileURLWithPath: secret)
        )
        do {
            _ = try await makeValidator(
                probe: StubProbe { input in fixture.outputFacts(for: input) }
            ).validate(
                plan: fixture.plan,
                source: fixture.source,
                stagedArtifacts: [escaped, fixture.stagedArtifacts[1]],
                stagingRoot: fixture.stagingRoot
            )
            Issue.record("Expected the unsafe manifest to fail")
        } catch {
            #expect(error as? VideoSplitOutputValidationError == .invalidManifest)
            #expect(String(reflecting: error).contains(secret) == false)
        }
    }

    private func expectFailure<T>(
        _ expected: VideoSplitOutputValidationError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected \(expected)")
        } catch {
            #expect(error as? VideoSplitOutputValidationError == expected)
        }
    }
}

private func makeValidator(
    probe: any VideoSplitProbing,
    decodability: any VideoSplitSegmentDecodabilityChecking =
        StubDecodabilityChecker { _ in true }
) -> VideoSplitOutputValidator {
    VideoSplitOutputValidator(
        probe: probe,
        decodabilityChecker: decodability
    )
}

private struct StubProbe: VideoSplitProbing {
    let handler: @Sendable (InputFile) async throws -> VideoSplitSourceFacts

    init(
        handler: @Sendable @escaping (InputFile) async throws -> VideoSplitSourceFacts
    ) {
        self.handler = handler
    }

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        try await handler(input)
    }
}

private actor CountingProbe: VideoSplitProbing {
    private let handler: @Sendable (InputFile) async throws -> VideoSplitSourceFacts
    private var calls = 0

    init(
        handler: @Sendable @escaping (InputFile) async throws -> VideoSplitSourceFacts
    ) {
        self.handler = handler
    }

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        calls += 1
        return try await handler(input)
    }

    func callCount() -> Int { calls }
}

private struct StubDecodabilityChecker: VideoSplitSegmentDecodabilityChecking {
    let handler: @Sendable (URL) async throws -> Bool

    init(handler: @Sendable @escaping (URL) async throws -> Bool) {
        self.handler = handler
    }

    func canDecodeFirstFrame(at fileURL: URL) async throws -> Bool {
        try await handler(fileURL)
    }
}

private enum PrivateProbeError: Error, Sendable {
    case message(String)
}

private struct Fixture: Sendable {
    let stagingRoot: URL
    let plan: VideoSplitPlan
    let source: VideoSplitSourceFacts
    let stagedArtifacts: [StagedOutputArtifact]
    let sourceAudioCodec: String?
    let durationPerSegmentMilliseconds: Int64

    var plannedArtifactIDs: [OutputArtifactID] {
        plan.segments.map { segment in
            OutputArtifactID(
                sourceInputID: plan.input.id,
                role: .videoSegment(
                    ordinal: segment.index,
                    total: plan.segments.count
                )
            )
        }
    }

    init(
        segmentCount: Int = 2,
        durationPerSegmentMilliseconds: Int64 = 1_000,
        maxBytes: Int64? = 10,
        maxDurationMilliseconds: Int64? = 1_100,
        fileByteCounts: [Int]? = nil,
        sourceAudioCodec: String? = "aac",
        stripMetadata: Bool = true
    ) throws {
        precondition(segmentCount > 0)
        let inputID = UUID()
        let inputURL = URL(fileURLWithPath: "/private/tmp/validator-source.mp4")
        let totalDuration = Int64(segmentCount) * durationPerSegmentMilliseconds
        let input = InputFile(
            id: inputID,
            url: inputURL,
            type: .mpeg4Movie,
            fileSize: 1_000_000,
            displayName: "validator-source.mp4"
        )
        let segments = try (1...segmentCount).map { index in
            VideoSegmentPlan(
                index: index,
                startMilliseconds: Int64(index - 1) * durationPerSegmentMilliseconds,
                endMilliseconds: Int64(index) * durationPerSegmentMilliseconds,
                outputRelativePath: try SafeRelativePath(
                    "validator-source — Split/validator-source-part-\(index)-of-\(segmentCount).mp4"
                ),
                estimatedBytes: 1,
                requiresReencoding: false
            )
        }
        plan = VideoSplitPlan(
            id: UUID(),
            input: input,
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: maxBytes,
                    maxDurationMilliseconds: maxDurationMilliseconds,
                    safetyRatio: 0.9,
                    requiredContainer: "mp4",
                    requiredVideoCodec: "h264",
                    requiredAudioCodec: sourceAudioCodec
                ),
                stripMetadata: stripMetadata
            ),
            ruleSnapshot: nil,
            segments: segments
        )
        source = VideoSplitSourceFacts(
            inputID: inputID,
            sourceURL: inputURL,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            durationMilliseconds: totalDuration,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: 8_000_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: sourceAudioCodec,
            videoStartMilliseconds: 0,
            audioStartMilliseconds: sourceAudioCodec == nil ? nil : 0,
            audioDurationMilliseconds: sourceAudioCodec == nil ? nil : totalDuration,
            userMetadataKeys: [],
            frameDurationMilliseconds: 40,
            keyframeMilliseconds: (0..<segmentCount).map {
                Int64($0) * durationPerSegmentMilliseconds
            }
        )
        self.sourceAudioCodec = sourceAudioCodec
        self.durationPerSegmentMilliseconds = durationPerSegmentMilliseconds

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-VideoSplitOutputValidator-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false
        )
        let byteCounts = fileByteCounts ?? Array(repeating: 1, count: segmentCount)
        precondition(byteCounts.count == segmentCount)
        let artifacts = try (1...segmentCount).map { index in
            let fileURL = root.appendingPathComponent("staged-\(index).mp4")
            try Data(repeating: 0x01, count: byteCounts[index - 1]).write(to: fileURL)
            return StagedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: inputID,
                    role: .videoSegment(ordinal: index, total: segmentCount)
                ),
                fileURL: fileURL
            )
        }
        stagingRoot = root
        stagedArtifacts = artifacts
    }

    func validator() -> VideoSplitOutputValidator {
        makeValidator(
            probe: StubProbe { input in self.outputFacts(for: input) }
        )
    }

    func validate(
        with validator: VideoSplitOutputValidator
    ) async throws -> ValidatedVideoSplitOutput {
        try await validator.validate(
            plan: plan,
            source: source,
            stagedArtifacts: stagedArtifacts,
            stagingRoot: stagingRoot
        )
    }

    func index(for url: URL) -> Int {
        stagedArtifacts.firstIndex(where: {
            $0.fileURL.standardizedFileURL == url.standardizedFileURL
        }).map { $0 + 1 } ?? 0
    }

    func outputFacts(
        for input: InputFile,
        durationMilliseconds: Int64? = nil,
        container: String = "mp4",
        videoCodec: String = "h264",
        audioCodec: String? = "aac",
        displayWidth: Int = 1_920,
        displayHeight: Int = 1_080,
        rotationDegrees: Int = 0,
        audioStartMilliseconds: Int64 = 0,
        audioDurationMilliseconds: Int64? = nil,
        keyframeMilliseconds: [Int64] = [0],
        userMetadataKeys: Set<String> = []
    ) -> VideoSplitSourceFacts {
        VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: (try? actualVideoSplitTestIdentity(
                at: input.url,
                expectedByteCount: input.fileSize
            )) ?? makeVideoSplitTestIdentity(byteCount: input.fileSize),
            durationMilliseconds: durationMilliseconds ?? durationPerSegmentMilliseconds,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            rotationDegrees: rotationDegrees,
            averageBitrateBitsPerSecond: 8_000_000,
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            videoStartMilliseconds: 0,
            audioStartMilliseconds: audioCodec == nil ? nil : audioStartMilliseconds,
            audioDurationMilliseconds: audioCodec == nil
                ? nil
                : (audioDurationMilliseconds
                    ?? durationMilliseconds
                    ?? durationPerSegmentMilliseconds),
            userMetadataKeys: userMetadataKeys,
            frameDurationMilliseconds: 40,
            keyframeMilliseconds: keyframeMilliseconds
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: stagingRoot)
    }
}
