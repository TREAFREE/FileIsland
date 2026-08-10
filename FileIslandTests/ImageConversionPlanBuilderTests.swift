import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class ImageConversionPlanBuilderTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/File Island Output", isDirectory: true)

    func testBuildsJPEGPlanForHEICAndPNGBatch() throws {
        let inputs = [
            makeInput(name: "one.heic", type: .heic),
            makeInput(name: "two.png", type: .png)
        ]
        let intent = makeIntent(output: .jpeg, maxPixelDimension: 2048)

        let plan = try ImageConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.inputs, inputs)
        XCTAssertEqual(plan.steps, [.image(intent)])
        XCTAssertEqual(plan.outputPolicy, .chosenDirectory(outputDirectory, suffix: ""))
    }

    func testBuildsPNGPlanForJPEGBatch() throws {
        let inputs = [makeInput(name: "photo.jpg", type: .jpeg)]
        let intent = makeIntent(output: .png)

        let plan = try ImageConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.steps, [.image(intent)])
    }

    func testBuildsJPEGPlanForMixedCommonImageBatch() throws {
        let inputs = [
            makeInput(name: "one.heif", type: .heif),
            makeInput(name: "two.jpg", type: .jpeg),
            makeInput(name: "three.png", type: .png),
            makeInput(name: "four.webp", type: .webP),
            makeInput(name: "five.tiff", type: .tiff)
        ]
        let intent = makeIntent(output: .jpeg)

        let plan = try ImageConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.inputs, inputs)
        XCTAssertEqual(plan.steps, [.image(intent)])
    }

    func testAllowsSameFormatPlansForImageProcessing() throws {
        let jpegIntent = makeIntent(output: .jpeg, maxPixelDimension: 2048)
        let pngIntent = makeIntent(output: .png, targetBytes: 500_000)

        XCTAssertNoThrow(try ImageConversionPlanBuilder().makePlan(
            inputs: [makeInput(name: "photo.jpg", type: .jpeg)],
            intent: jpegIntent,
            outputDirectory: outputDirectory
        ))
        XCTAssertNoThrow(try ImageConversionPlanBuilder().makePlan(
            inputs: [makeInput(name: "graphic.png", type: .png)],
            intent: pngIntent,
            outputDirectory: outputDirectory
        ))
    }

    func testBuildsPerFileTargetPlanWithBatchEstimate() throws {
        let inputs = [
            makeInput(name: "one.png", type: .png),
            makeInput(name: "two.png", type: .png)
        ]
        let intent = makeIntent(output: .jpeg, targetBytes: 500_000)

        let plan = try ImageConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: intent,
            outputDirectory: outputDirectory
        )

        XCTAssertEqual(plan.steps, [.image(intent)])
        XCTAssertEqual(
            plan.estimatedOutput,
            EstimatedOutput(totalBytes: 1_000_000, summary: "Up to 500 KB per file")
        )
    }

    func testRejectsNonPositiveTargetSizes() {
        for targetBytes in [Int64.zero, -1] {
            assertBuildFails(
                inputs: [makeInput(name: "photo.png", type: .png)],
                intent: makeIntent(output: .jpeg, targetBytes: targetBytes),
                error: .targetSizeUnreachable
            )
        }
    }

    func testRejectsEmptyUnsupportedAndFutureScopePlans() {
        assertBuildFails(inputs: [], intent: makeIntent(output: .jpeg), error: .unsupportedInput)
        assertBuildFails(
            inputs: [makeInput(name: "photo.png", type: .png)],
            intent: makeIntent(output: .webP),
            error: .unsupportedOutput
        )
        assertBuildFails(
            inputs: [makeInput(name: "photo.gif", type: .gif)],
            intent: makeIntent(output: .jpeg),
            error: .unsupportedInput
        )
        assertBuildFails(
            inputs: [makeInput(name: "photo.png", type: .png)],
            intent: makeIntent(output: .jpeg, maxPixelDimension: 0),
            error: .unsupportedOutput
        )
    }

    private func assertBuildFails(
        inputs: [InputFile],
        intent: ImageIntent,
        error expectedError: ConversionError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ImageConversionPlanBuilder().makePlan(
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

    private func makeIntent(
        output: ImageOutputFormat,
        maxPixelDimension: Int? = nil,
        targetBytes: Int64? = nil
    ) -> ImageIntent {
        ImageIntent(
            outputFormat: output,
            maxPixelDimension: maxPixelDimension,
            targetBytes: targetBytes,
            qualityPreference: .balanced,
            stripMetadata: true
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
