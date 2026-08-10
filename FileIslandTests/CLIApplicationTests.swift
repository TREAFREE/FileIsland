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
                presets: []
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

    private var validConvertArguments: [String] {
        [
            "convert", "input.png", "--output", "/tmp/out",
            "--image-format", "jpeg", "--json"
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

    init(
        capabilities: CoreCapabilities = CoreCapabilities(
            schemaVersion: 1,
            image: CoreMediaCapabilities(inputFormats: [], outputFormats: []),
            video: CoreVideoCapabilities(
                nativeInputFormats: [], fallbackInputFormats: [], outputContainer: "mp4",
                resolutions: [], nativeSupportsTargetBytes: true, fallbackSupportsTargetBytes: false
            ),
            presets: []
        ),
        error: Error? = nil,
        conversionResult: CoreConversionResult = CoreConversionResult(
            requestID: UUID(), outputURLs: [], skippedCount: 0, failClosedCount: 0
        ),
        progress: BatchProgress? = nil
    ) {
        capabilitiesValue = capabilities
        self.error = error
        self.conversionResult = conversionResult
        progressValue = progress
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
}
