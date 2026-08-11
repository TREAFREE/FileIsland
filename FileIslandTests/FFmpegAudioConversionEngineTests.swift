@preconcurrency import AVFoundation
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class FFmpegAudioConversionEngineTests: XCTestCase {
    func testEveryDocumentedAudioInputProducesValidatedM4A() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = FFmpegAudioConversionEngine(executableURL: try bundledFFmpegURL())

        for filenameExtension in ["mp3", "wav", "aiff", "m4a", "aac", "flac", "ogg", "opus", "ac3"] {
            let input = try fixture(named: "tone.\(filenameExtension)")
            let plan = try makePlan(input: input, output: output, format: .m4a)
            let outputs = try await engine.execute(plan) { _ in }
            let result = try XCTUnwrap(outputs.first)
            XCTAssertEqual(result.pathExtension, "m4a")
            try await assertValidAudio(result)
        }
    }

    func testEveryDocumentedAudioOutputIsNonemptyAndDecodable() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let engine = FFmpegAudioConversionEngine(executableURL: try bundledFFmpegURL())
        let input = try fixture(named: "tone.mp3")

        for format in MediaConversionMatrix.audioOutputFormats {
            let outputs = try await engine.execute(
                try makePlan(input: input, output: output, format: format)
            ) { _ in }
            let result = try XCTUnwrap(outputs.first)
            XCTAssertEqual(result.pathExtension, format.filenameExtension)
            try await assertValidAudio(result)
        }
    }

    func testInvalidLaterInputRollsBackEarlierAudioOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let valid = try fixture(named: "tone.mp3")
        let invalid = workspace.appendingPathComponent("broken.mp3")
        try Data("not audio".utf8).write(to: invalid)
        let files = [valid, invalid].map { url in
            InputFile(url: url, type: .mp3, fileSize: 100, displayName: url.lastPathComponent)
        }
        let plan = try AudioConversionPlanBuilder().makePlan(
            inputs: files,
            intent: AudioIntent(outputFormat: .m4a, quality: .balanced, stripMetadata: false),
            outputDirectory: output
        )

        do {
            _ = try await FFmpegAudioConversionEngine(
                executableURL: try bundledFFmpegURL()
            ).execute(plan) { _ in }
            XCTFail("Expected conversion failure")
        } catch {
            XCTAssertNotEqual(error as? ConversionError, .cancelled)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
    }

    func testCancellationStopsAudioProcessAndLeavesNoOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let runner = BlockingFFmpegProcessRunner()
        let engine = FFmpegAudioConversionEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner
        )
        let plan = try makePlan(input: fixture(named: "tone.mp3"), output: output, format: .m4a)
        let task = Task { try await engine.execute(plan) { _ in } }

        try await Task.sleep(for: .milliseconds(20))
        await engine.cancel(jobID: plan.id)
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
        let cancelledJobID = await runner.cancelledJobID
        XCTAssertEqual(cancelledJobID, plan.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
    }

    func testRejectsUnexpectedFFmpegPolicyBeforeAudioConversion() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let runner = VersionReportingFFmpegProcessRunner(
            versionText: "ffmpeg version 8.1.2\nconfiguration: --enable-gpl --disable-network\n"
        )
        let engine = FFmpegAudioConversionEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner
        )
        let plan = try makePlan(
            input: fixture(named: "tone.mp3"),
            output: workspace,
            format: .m4a
        )

        do {
            _ = try await engine.execute(plan) { _ in }
            XCTFail("Expected binary policy rejection")
        } catch {
            XCTAssertEqual(error as? ConversionError, .engineUnavailable)
        }
        let invocationCount = await runner.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testUsesBoundedProfilesAndMapsTypedProcessTimeout() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let output = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let runner = VersionReportingFFmpegProcessRunner(
            versionText: "ffmpeg version 8.1.2\nconfiguration: --disable-network\n",
            conversionFailure: .timedOut
        )
        let engine = FFmpegAudioConversionEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner
        )

        do {
            _ = try await engine.execute(
                try makePlan(input: fixture(named: "tone.mp3"), output: output, format: .m4a)
            ) { _ in }
            XCTFail("Expected process timeout")
        } catch let error as ConversionError {
            guard case let .conversionFailed(message) = error else {
                return XCTFail("Unexpected conversion error: \(error)")
            }
            XCTAssertTrue(message?.contains("stopped responding") == true)
        }
        let capturedLimits = await runner.capturedLimits
        XCTAssertEqual(capturedLimits, [.versionValidation, .conversion])
    }

    private func makePlan(
        input: URL,
        output: URL,
        format: AudioOutputFormat
    ) throws -> ConversionPlan {
        let file = InputFile(
            url: input,
            type: UTType(filenameExtension: input.pathExtension),
            fileSize: Int64(try fileSize(input)),
            displayName: input.lastPathComponent
        )
        return try AudioConversionPlanBuilder().makePlan(
            inputs: [file],
            intent: AudioIntent(outputFormat: format, quality: .balanced, stripMetadata: true),
            outputDirectory: output
        )
    }

    private func fixture(named name: String) throws -> URL {
        try XCTUnwrap(
            Bundle(for: FFmpegAudioConversionEngineTests.self)
                .url(forResource: name, withExtension: nil)
        )
    }

    private func bundledFFmpegURL() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"))
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-AudioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func assertValidAudio(_ url: URL) async throws {
        XCTAssertGreaterThan(try fileSize(url), 0)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertGreaterThan(duration, 0)
        XCTAssertFalse(audioTracks.isEmpty)
        XCTAssertTrue(videoTracks.isEmpty)
    }
}
