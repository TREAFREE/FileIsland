import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class VideoConversionPlanBuilderTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/File Island Output", isDirectory: true)

    func testBuildsHighCompatibilityPlanForMOVAndMP4Batch() throws {
        let inputs = [
            makeInput(name: "one.mov", type: .quickTimeMovie),
            makeInput(name: "two.mp4", type: .mpeg4Movie)
        ]
        let intent = VideoIntent(
            compatibility: .highCompatibility,
            maxResolution: .p1080,
            targetBytes: nil,
            qualityPreference: .balanced
        )

        let plan = try VideoConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.inputs, inputs)
        XCTAssertEqual(plan.steps, [.video(intent)])
        XCTAssertEqual(plan.outputPolicy, .chosenDirectory(outputDirectory, suffix: ""))
        XCTAssertNil(plan.estimatedOutput)
    }

    func testBuildsPerFileTargetPlanWithBatchEstimate() throws {
        let inputs = [
            makeInput(name: "one.mov", type: .quickTimeMovie),
            makeInput(name: "two.mp4", type: .mpeg4Movie)
        ]
        let intent = makeIntent(targetBytes: 50_000_000)

        let plan = try VideoConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.steps, [.video(intent)])
        XCTAssertEqual(plan.estimatedOutput?.totalBytes, 100_000_000)
        XCTAssertEqual(plan.estimatedOutput?.summary, "Up to 50 MB per file")
    }

    func testBuildsNativeM4VPlanWithTargetSize() throws {
        let input = makeInput(name: "clip.m4v", type: nil)
        let intent = makeIntent(targetBytes: 50_000_000)

        let plan = try VideoConversionPlanBuilder().makePlan(
            inputs: [input],
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.inputs, [input])
        XCTAssertEqual(plan.steps, [.video(intent)])
        XCTAssertEqual(plan.estimatedOutput?.totalBytes, 50_000_000)
    }

    func testBuildsUntargetedMKVAndWebMFallbackPlan() throws {
        let inputs = [
            makeInput(name: "one.mkv", type: UTType(filenameExtension: "mkv")),
            makeInput(name: "two.webm", type: UTType(filenameExtension: "webm"))
        ]
        let intent = makeIntent()

        let plan = try VideoConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.inputs, inputs)
        XCTAssertEqual(plan.steps, [.video(intent)])
        XCTAssertNil(plan.estimatedOutput)
    }

    func testRejectsEmptyUnsupportedAndInvalidTargetPlans() {
        assertBuildFails(inputs: [], intent: makeIntent(), error: .unsupportedInput)
        assertBuildFails(
            inputs: [makeInput(name: "photo.png", type: .png)],
            intent: makeIntent(),
            error: .unsupportedInput
        )
        assertBuildFails(inputs: [makeInput(name: "clip.mov", type: .quickTimeMovie)], intent: makeIntent(targetBytes: 0), error: .targetSizeUnreachable)
        assertBuildFails(inputs: [makeInput(name: "clip.mov", type: .quickTimeMovie)], intent: makeIntent(targetBytes: -1), error: .targetSizeUnreachable)
        assertBuildFails(
            inputs: [makeInput(name: "clip.mkv", type: UTType(filenameExtension: "mkv"))],
            intent: makeIntent(targetBytes: 50_000_000),
            error: .unsupportedOutput
        )
        assertBuildFails(
            inputs: [
                makeInput(name: "native.mov", type: .quickTimeMovie),
                makeInput(name: "fallback.mkv", type: UTType(filenameExtension: "mkv"))
            ],
            intent: makeIntent(),
            error: .unsupportedInput
        )
        assertBuildFails(
            inputs: [makeInput(name: "clip.mov", type: .quickTimeMovie)],
            intent: VideoIntent(
                compatibility: .web,
                maxResolution: .source,
                targetBytes: nil,
                qualityPreference: .balanced
            ),
            error: .unsupportedOutput
        )
    }

    private func assertBuildFails(
        inputs: [InputFile],
        intent: VideoIntent,
        error expectedError: ConversionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try VideoConversionPlanBuilder().makePlan(
                inputs: inputs,
                intent: intent,
                outputDirectory: outputDirectory
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? ConversionError, expectedError, file: file, line: line)
        }
    }

    private func makeIntent(targetBytes: Int64? = nil) -> VideoIntent {
        VideoIntent(
            compatibility: .highCompatibility,
            maxResolution: .source,
            targetBytes: targetBytes,
            qualityPreference: .balanced
        )
    }

    private func makeInput(name: String, type: UTType?) -> InputFile {
        InputFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            type: type,
            fileSize: 1,
            displayName: name
        )
    }
}
