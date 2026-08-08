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

    func testRejectsEmptyUnsupportedAndFutureTargetPlans() {
        assertBuildFails(inputs: [], intent: makeIntent(), error: .unsupportedInput)
        assertBuildFails(
            inputs: [makeInput(name: "clip.mkv", type: UTType(filenameExtension: "mkv"))],
            intent: makeIntent(),
            error: .unsupportedInput
        )
        assertBuildFails(
            inputs: [makeInput(name: "photo.png", type: .png)],
            intent: makeIntent(),
            error: .unsupportedInput
        )
        assertBuildFails(
            inputs: [makeInput(name: "clip.mov", type: .quickTimeMovie)],
            intent: makeIntent(targetBytes: 50_000_000),
            error: .targetSizeUnreachable
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
