import Foundation
import XCTest
@testable import FileIsland

final class AudioConversionPlanBuilderTests: XCTestCase {
    func testBuildsIndependentAudioPlanForMixedSupportedInputs() throws {
        let files = ["song.mp3", "voice.flac", "clip.opus"].map(makeInput)
        let intent = AudioIntent(
            outputFormat: .m4a,
            quality: .balanced,
            stripMetadata: true
        )

        let plan = try AudioConversionPlanBuilder().makePlan(
            inputs: files,
            intent: intent,
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        )

        XCTAssertEqual(plan.inputs, files)
        XCTAssertEqual(plan.steps, [.audio(intent)])
    }

    func testRejectsUnsupportedInputAndNeverOffersMP3Output() {
        XCTAssertNil(AudioOutputFormat(rawValue: "mp3"))
        XCTAssertThrowsError(try AudioConversionPlanBuilder().makePlan(
            inputs: [makeInput("notes.txt")],
            intent: AudioIntent(outputFormat: .wav, quality: .high, stripMetadata: false),
            outputDirectory: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        )) { error in
            XCTAssertEqual(error as? ConversionError, .unsupportedInput)
        }
    }

    private func makeInput(_ name: String) -> InputFile {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return InputFile(url: url, type: nil, fileSize: 100, displayName: name)
    }
}
