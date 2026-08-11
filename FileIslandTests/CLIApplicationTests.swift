import Foundation
import XCTest
@testable import FileIsland

final class CLIApplicationTests: XCTestCase {
    func testCapabilitiesWritesOnlyVersionedJSONToStandardOutput() async throws {
        let output = MemoryCLIOutput()
        let core = StubCLICore(
            capabilities: CoreCapabilities(
                schemaVersion: 1,
                image: CoreMediaCapabilities(inputFormats: ["png"], outputFormats: ["jpeg"]),
                video: CoreVideoCapabilities(
                    nativeInputFormats: ["mp4"], fallbackInputFormats: ["webm"],
                    outputContainer: "mp4", resolutions: ["source"],
                    nativeSupportsTargetBytes: true, fallbackSupportsTargetBytes: false
                ),
                audio: CoreMediaCapabilities(
                    inputFormats: ["mp3"], outputFormats: ["m4a"]
                ),
                presets: [],
                videoSplit: CoreVideoSplitCapabilities(
                    constraintSources: ["custom"],
                    modes: ["fast-keyframe-copy"],
                    inputContainers: ["mp4", "mov"],
                    videoCodecs: ["h264"],
                    audioCodecs: ["aac"],
                    allowsNoAudio: true,
                    customConstraints: CoreVideoSplitConstraintCapabilities(
                        supported: ["maxBytes", "maxDurationSeconds"],
                        requiresAtLeastOne: true,
                        decimalMegabyteBytes: 1_000_000,
                        durationUnit: "seconds",
                        durationPrecisionMilliseconds: 1
                    )
                )
            )
        )
        let app = FileIslandCLIApplication(core: core, output: output)

        let exit = await app.run(arguments: ["capabilities", "--json"])

        XCTAssertEqual(exit, .success)
        XCTAssertTrue(output.standardError.isEmpty)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: output.standardOutput) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["kind"] as? String, "capabilities")
        let split = try XCTUnwrap(object["videoSplit"] as? [String: Any])
        XCTAssertEqual(split["constraintSources"] as? [String], ["custom"])
        XCTAssertEqual(split["modes"] as? [String], ["fast-keyframe-copy"])
        XCTAssertEqual(split["inputContainers"] as? [String], ["mp4", "mov"])
        XCTAssertEqual(split["videoCodecs"] as? [String], ["h264"])
        XCTAssertEqual(split["audioCodecs"] as? [String], ["aac"])
        XCTAssertEqual(split["allowsNoAudio"] as? Bool, true)
        let constraints = try XCTUnwrap(split["customConstraints"] as? [String: Any])
        XCTAssertEqual(
            constraints["supported"] as? [String],
            ["maxBytes", "maxDurationSeconds"]
        )
        XCTAssertEqual(constraints["requiresAtLeastOne"] as? Bool, true)
        XCTAssertEqual(constraints["decimalMegabyteBytes"] as? Int, 1_000_000)
        XCTAssertEqual(constraints["durationUnit"] as? String, "seconds")
        XCTAssertEqual(constraints["durationPrecisionMilliseconds"] as? Int, 1)
        XCTAssertNil(split["platformRules"])
        XCTAssertFalse((split["modes"] as? [String] ?? []).contains("preciseCompatible"))
    }

    func testArgumentAndDomainErrorsUseStableExitCodesWithoutPrivatePaths() async {
        let output = MemoryCLIOutput()
        let core = StubCLICore(error: FileIslandCoreError.unsupportedInput)
        let app = FileIslandCLIApplication(core: core, output: output)

        let argumentExit = await app.run(arguments: ["inspect", "/Users/private/secret.png"])
        XCTAssertEqual(argumentExit, .argumentError)
        XCTAssertFalse(output.standardErrorString.contains("/Users/private"))

        output.reset()
        let unsupportedExit = await app.run(arguments: [
            "convert", "/Users/private/secret.bin", "--output", "/tmp/out",
            "--image-format", "jpeg", "--json"
        ])
        XCTAssertEqual(unsupportedExit, .unsupported)
        XCTAssertFalse(output.standardErrorString.contains("/Users/private"))
    }

    func testConvertEmitsJSONLinesAndPartialSkipExit() async throws {
        let output = MemoryCLIOutput()
        let requestID = UUID()
        let core = StubCLICore(
            conversionResult: CoreConversionResult(
                requestID: requestID,
                outputURLs: [URL(fileURLWithPath: "/tmp/out/nested/result.jpg")],
                skippedCount: 0,
                failClosedCount: 1
            ),
            progress: BatchProgress(
                requestID: requestID,
                fraction: 0.5,
                currentFile: 1,
                totalFiles: 2,
                currentDisplayName: "私密 photo.png"
            )
        )
        let app = FileIslandCLIApplication(core: core, output: output)

        let exit = await app.run(arguments: [
            "convert", "input.png", "--output", "/tmp/out",
            "--image-format", "jpeg", "--json"
        ])

        XCTAssertEqual(exit, .partialSkip)
        let lines = output.standardOutputString.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        let states = try lines.map { line -> String? in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            XCTAssertEqual(object?["schemaVersion"] as? Int, 1)
            return object?["state"] as? String
        }
        XCTAssertEqual(states, ["preparing", "running", "completed"])
        XCTAssertFalse(output.standardOutputString.contains("/tmp/out"))
        XCTAssertTrue(output.standardOutputString.contains("nested/result.jpg"))
    }

    func testCancellationAndUnreachableTargetUseDistinctExitCodes() async {
        let cancelledOutput = MemoryCLIOutput()
        let cancelledApp = FileIslandCLIApplication(
            core: StubCLICore(error: ConversionError.cancelled),
            output: cancelledOutput
        )
        let cancelledExit = await cancelledApp.run(arguments: validConvertArguments)

        XCTAssertEqual(cancelledExit, .cancelled)
        XCTAssertTrue(cancelledOutput.standardOutputString.contains("\"state\":\"cancelled\""))

        let unreachableOutput = MemoryCLIOutput()
        let unreachableApp = FileIslandCLIApplication(
            core: StubCLICore(error: ConversionError.targetSizeUnreachable),
            output: unreachableOutput
        )
        let unreachableExit = await unreachableApp.run(arguments: validConvertArguments)

        XCTAssertEqual(unreachableExit, .unsupported)
        XCTAssertTrue(unreachableOutput.standardOutputString.contains("\"state\":\"failed\""))
    }

    func testSplitEmitsStablePathSafeJSONLines() async throws {
        let output = MemoryCLIOutput()
        let requestID = UUID()
        let published = URL(fileURLWithPath: "/tmp/out/Movie — Split/Movie-part-01-of-01.mp4")
        let planPath = try SafeRelativePath("Movie — Split/Movie-part-01-of-01.mp4")
        let core = StubCLICore(
            splitResult: CoreVideoSplitResult(
                requestID: requestID,
                outputURLs: [published],
                segmentCount: 1,
                totalBytes: 42
            ),
            splitEvents: [
                .plan(
                    CoreVideoSplitPlanEvent(
                        requestID: requestID,
                        inputOrdinal: 1,
                        totalInputs: 1,
                        displayName: "Movie.mp4",
                        segmentRelativePaths: [planPath]
                    )
                ),
                .segment(
                    VideoSplitBatchProgress(
                        requestID: requestID,
                        fraction: 0.5,
                        currentFile: 1,
                        totalFiles: 1,
                        currentDisplayName: "Movie.mp4",
                        currentSegment: 1,
                        totalSegments: 1
                    )
                ),
                .validation(
                    CoreVideoSplitValidationEvent(requestID: requestID, segmentCount: 1)
                ),
                .publication(
                    CoreVideoSplitPublicationEvent(
                        requestID: requestID,
                        outputURLs: [published]
                    )
                )
            ]
        )
        let app = FileIslandCLIApplication(core: core, output: output)

        let exit = await app.run(arguments: [
            "split", "/Users/private/Movie.mp4", "--output", "/tmp/out",
            "--max-duration-seconds", "60", "--mode", "fast-keyframe-copy", "--json"
        ])

        XCTAssertEqual(exit, .success)
        let objects = try output.standardOutputString.split(separator: "\n").map { line in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
        }
        XCTAssertEqual(objects.compactMap { $0["state"] as? String }, [
            "plan", "segment", "validation", "publication", "completed"
        ])
        XCTAssertTrue(objects.allSatisfy { $0["schemaVersion"] as? Int == 1 })
        XCTAssertFalse(output.standardOutputString.contains("/Users/private"))
        XCTAssertFalse(output.standardOutputString.contains("/tmp/out"))
        XCTAssertTrue(output.standardOutputString.contains("Movie — Split/Movie-part-01-of-01.mp4"))
    }

    func testSplitFailureEmitsRollbackAndFailedWithoutPrivatePath() async {
        let output = MemoryCLIOutput()
        let requestID = UUID()
        let core = StubCLICore(
            error: VideoSplitJobError.keyframeSpacingUnreachable,
            splitEvents: [.rollback(requestID: requestID)]
        )
        let app = FileIslandCLIApplication(core: core, output: output)

        let exit = await app.run(arguments: [
            "split", "/Users/private/Movie.mp4", "--output", "/tmp/out",
            "--max-bytes", "1000000", "--mode", "fast-keyframe-copy", "--json"
        ])

        XCTAssertEqual(exit, .unsupported)
        XCTAssertTrue(output.standardOutputString.contains("\"state\":\"rollback\""))
        XCTAssertTrue(output.standardOutputString.contains("\"state\":\"failed\""))
        XCTAssertFalse(output.standardOutputString.contains("/Users/private"))
        XCTAssertFalse(output.standardOutputString.contains("/tmp/out"))
    }

    func testSplitPlanningProbeCancellationUsesCancelledExitOnly() async {
        let cancelledOutput = MemoryCLIOutput()
        let cancelledApp = FileIslandCLIApplication(
            core: StubCLICore(error: VideoSplitProbeError.probeCancelled),
            output: cancelledOutput
        )
        let cancelledExit = await cancelledApp.run(arguments: validSplitArguments)
        XCTAssertEqual(cancelledExit, .cancelled)
        XCTAssertTrue(cancelledOutput.standardOutputString.contains("\"state\":\"cancelled\""))

        let timedOutOutput = MemoryCLIOutput()
        let timedOutApp = FileIslandCLIApplication(
            core: StubCLICore(error: VideoSplitProbeError.probeTimedOut),
            output: timedOutOutput
        )
        let timedOutExit = await timedOutApp.run(arguments: validSplitArguments)
        XCTAssertEqual(timedOutExit, .unsupported)
        XCTAssertTrue(timedOutOutput.standardOutputString.contains("\"state\":\"failed\""))
    }

    private var validConvertArguments: [String] {
        [
            "convert", "input.png", "--output", "/tmp/out",
            "--image-format", "jpeg", "--json"
        ]
    }

    private var validSplitArguments: [String] {
        [
            "split", "input.mp4", "--output", "/tmp/out",
            "--max-duration-seconds", "60", "--mode", "fast-keyframe-copy", "--json"
        ]
    }
}

private final class MemoryCLIOutput: CLIOutputWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()

    var standardOutput: Data { lock.withLock { stdout } }
    var standardError: Data { lock.withLock { stderr } }
    var standardOutputString: String { String(decoding: standardOutput, as: UTF8.self) }
    var standardErrorString: String { String(decoding: standardError, as: UTF8.self) }

    func writeStandardOutput(_ data: Data) { lock.withLock { stdout.append(data) } }
    func writeStandardError(_ data: Data) { lock.withLock { stderr.append(data) } }
    func reset() { lock.withLock { stdout = Data(); stderr = Data() } }
}

private actor StubCLICore: FileIslandCoreServing {
    let capabilitiesValue: CoreCapabilities
    let error: Error?
    let conversionResult: CoreConversionResult
    let progressValue: BatchProgress?
    let splitResult: CoreVideoSplitResult
    let splitEvents: [CoreVideoSplitEvent]

    init(
        capabilities: CoreCapabilities = CoreCapabilities(
            schemaVersion: 1,
            image: CoreMediaCapabilities(inputFormats: [], outputFormats: []),
            video: CoreVideoCapabilities(
                nativeInputFormats: [], fallbackInputFormats: [], outputContainer: "mp4",
                resolutions: [], nativeSupportsTargetBytes: true, fallbackSupportsTargetBytes: false
            ),
            audio: CoreMediaCapabilities(inputFormats: [], outputFormats: []),
            presets: []
        ),
        error: Error? = nil,
        conversionResult: CoreConversionResult = CoreConversionResult(
            requestID: UUID(), outputURLs: [], skippedCount: 0, failClosedCount: 0
        ),
        progress: BatchProgress? = nil,
        splitResult: CoreVideoSplitResult = CoreVideoSplitResult(
            requestID: UUID(), outputURLs: [], segmentCount: 0, totalBytes: 0
        ),
        splitEvents: [CoreVideoSplitEvent] = []
    ) {
        capabilitiesValue = capabilities
        self.error = error
        self.conversionResult = conversionResult
        progressValue = progress
        self.splitResult = splitResult
        self.splitEvents = splitEvents
    }

    func capabilities() async throws -> CoreCapabilities {
        if let error { throw error }
        return capabilitiesValue
    }

    func inspect(paths: [URL], recursive: Bool) async throws -> CoreInspection {
        if let error { throw error }
        return CoreInspection(schemaVersion: 1, files: [])
    }

    func convert(
        _ request: CoreConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> CoreConversionResult {
        if let error { throw error }
        if let progressValue { progress(progressValue) }
        return conversionResult
    }

    func cancel(requestID: UUID) async {}

    func split(
        _ request: CoreVideoSplitRequest,
        event: @Sendable @escaping (CoreVideoSplitEvent) -> Void
    ) async throws -> CoreVideoSplitResult {
        for value in splitEvents { event(value) }
        if let error { throw error }
        return splitResult
    }
}
