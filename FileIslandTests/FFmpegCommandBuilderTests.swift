import Foundation
import XCTest
@testable import FileIsland

final class FFmpegCommandBuilderTests: XCTestCase {
    func testBuildsStructuredHighCompatibilityCommandWithoutShell() throws {
        let executableURL = URL(fileURLWithPath: "/Applications/File Island.app/Contents/MacOS/ffmpeg")
        let inputURL = URL(fileURLWithPath: "/tmp/a clip; untouched.mkv")
        let outputURL = URL(fileURLWithPath: "/tmp/result.mp4")
        let plan = makePlan(inputURL: inputURL, format: .mkv, resolution: .p1080)

        let command = try FFmpegCommandBuilder().makeCommand(
            plan: plan,
            input: plan.inputs[0],
            outputURL: outputURL,
            executableURL: executableURL
        )

        XCTAssertEqual(command.executableURL, executableURL)
        XCTAssertEqual(value(after: "-i", in: command.arguments), inputURL.path)
        XCTAssertEqual(command.arguments.last, outputURL.path)
        XCTAssertTrue(command.arguments.contains("h264_videotoolbox"))
        XCTAssertTrue(command.arguments.contains("aac"))
        XCTAssertTrue(command.arguments.contains("0:a:0?"))
        XCTAssertTrue(command.arguments.contains("pipe:1"))
        XCTAssertEqual(value(after: "-stats_period", in: command.arguments), "0.5")
        XCTAssertTrue(command.arguments.contains(where: {
            $0.contains("min(iw\\,1920)") && $0.contains("force_divisible_by=2")
        }))
        XCTAssertFalse(command.arguments.contains("/bin/zsh"))
        XCTAssertFalse(command.arguments.contains("-c"))
        XCTAssertEqual(command.arguments.filter { $0 == inputURL.path }.count, 1)
    }

    func testResolutionFiltersDoNotUpscaleAndUseExpectedLongEdgeCeiling() throws {
        let expectations: [(VideoResolution, String)] = [
            (.source, "3840"),
            (.p1080, "1920"),
            (.p720, "1280")
        ]

        for (resolution, ceiling) in expectations {
            let plan = makePlan(
                inputURL: URL(fileURLWithPath: "/tmp/input.webm"),
                format: .webM,
                resolution: resolution
            )
            let command = try FFmpegCommandBuilder().makeCommand(
                plan: plan,
                input: plan.inputs[0],
                outputURL: URL(fileURLWithPath: "/tmp/output.mp4"),
                executableURL: URL(fileURLWithPath: "/bundle/ffmpeg")
            )

            XCTAssertTrue(command.arguments.contains(where: {
                $0.contains("min(iw\\,\(ceiling))")
                    && $0.contains("min(ih\\,\(ceiling))")
            }))
        }
    }

    func testRejectsNativeInputsAndFallbackTargetSize() {
        let executableURL = URL(fileURLWithPath: "/bundle/ffmpeg")
        let outputURL = URL(fileURLWithPath: "/tmp/output.mp4")
        let nativePlan = makePlan(
            inputURL: URL(fileURLWithPath: "/tmp/input.mov"),
            format: .mov,
            resolution: .source
        )
        let targetedPlan = makePlan(
            inputURL: URL(fileURLWithPath: "/tmp/input.mkv"),
            format: .mkv,
            resolution: .source,
            targetBytes: 50_000_000
        )

        XCTAssertThrowsError(try FFmpegCommandBuilder().makeCommand(
            plan: nativePlan,
            input: nativePlan.inputs[0],
            outputURL: outputURL,
            executableURL: executableURL
        )) { XCTAssertEqual($0 as? ConversionError, .unsupportedInput) }
        XCTAssertThrowsError(try FFmpegCommandBuilder().makeCommand(
            plan: targetedPlan,
            input: targetedPlan.inputs[0],
            outputURL: outputURL,
            executableURL: executableURL
        )) { XCTAssertEqual($0 as? ConversionError, .unsupportedOutput) }
    }

    private func makePlan(
        inputURL: URL,
        format: InputFileFormat,
        resolution: VideoResolution,
        targetBytes: Int64? = nil
    ) -> ConversionPlan {
        let input = InputFile(
            url: inputURL,
            type: nil,
            fileSize: 100,
            displayName: inputURL.lastPathComponent
        )
        precondition(input.format == format)
        return ConversionPlan(
            inputs: [input],
            steps: [.video(VideoIntent(
                compatibility: .highCompatibility,
                maxResolution: resolution,
                targetBytes: targetBytes,
                qualityPreference: .balanced
            ))],
            outputPolicy: .chosenDirectory(outputURLDirectory, suffix: "")
        )
    }

    private var outputURLDirectory: URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
