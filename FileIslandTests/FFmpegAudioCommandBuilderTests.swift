import Foundation
import XCTest
@testable import FileIsland

final class FFmpegAudioCommandBuilderTests: XCTestCase {
    func testBuildsStructuredCommandsForEverySupportedOutput() throws {
        let expectations: [(AudioOutputFormat, String, String)] = [
            (.m4a, "aac", "ipod"),
            (.wav, "pcm_s16le", "wav"),
            (.flac, "flac", "flac"),
            (.aiff, "pcm_s16be", "aiff")
        ]
        for (format, codec, muxer) in expectations {
            let plan = makePlan(outputFormat: format)
            let output = URL(fileURLWithPath: "/tmp/result.\(format.filenameExtension)")
            let command = try FFmpegAudioCommandBuilder().makeCommand(
                plan: plan,
                input: plan.inputs[0],
                outputURL: output,
                executableURL: URL(fileURLWithPath: "/bundle/ffmpeg")
            )

            XCTAssertTrue(command.arguments.contains(codec))
            XCTAssertTrue(command.arguments.contains(muxer))
            XCTAssertTrue(command.arguments.contains("0:a:0"))
            XCTAssertTrue(command.arguments.contains("pipe:1"))
            XCTAssertEqual(value(after: "-stats_period", in: command.arguments), "0.5")
            XCTAssertFalse(command.arguments.contains("/bin/zsh"))
            XCTAssertEqual(command.arguments.last, output.path)
        }
    }

    func testStripMetadataUsesExplicitNegativeMapping() throws {
        let plan = makePlan(outputFormat: .m4a, stripMetadata: true)
        let command = try FFmpegAudioCommandBuilder().makeCommand(
            plan: plan,
            input: plan.inputs[0],
            outputURL: URL(fileURLWithPath: "/tmp/result.m4a"),
            executableURL: URL(fileURLWithPath: "/bundle/ffmpeg")
        )
        let metadataIndex = try XCTUnwrap(command.arguments.firstIndex(of: "-map_metadata"))
        XCTAssertEqual(command.arguments[metadataIndex + 1], "-1")
    }

    private func makePlan(
        outputFormat: AudioOutputFormat,
        stripMetadata: Bool = false
    ) -> ConversionPlan {
        let input = InputFile(
            url: URL(fileURLWithPath: "/tmp/source.mp3"),
            type: nil,
            fileSize: 100,
            displayName: "source.mp3"
        )
        return ConversionPlan(
            inputs: [input],
            steps: [.audio(AudioIntent(
                outputFormat: outputFormat,
                quality: .balanced,
                stripMetadata: stripMetadata
            ))],
            outputPolicy: .chosenDirectory(
                URL(fileURLWithPath: "/tmp", isDirectory: true),
                suffix: ""
            )
        )
    }

    private func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
