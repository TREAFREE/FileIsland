import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class FFmpegConversionEngineTests: XCTestCase {
    func testConvertsMKVAndWebMFixturesToPlayableH264AACMP4() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let engine = FFmpegConversionEngine(executableURL: try bundledFFmpegURL())

        for fixtureName in ["task007-landscape.mkv", "task007-portrait.webm"] {
            let inputURL = try copyFixture(named: fixtureName, to: workspace)
            let plan = try makePlan(inputs: [inputURL], outputDirectory: outputDirectory)
            let progress = LockedProgressRecorder()

            let outputs = try await engine.execute(plan) { progress.append($0) }

            let output = try XCTUnwrap(outputs.first)
            XCTAssertEqual(output.pathExtension.lowercased(), "mp4")
            try await assertValidOutput(output, matchingFixture: fixtureName)
            XCTAssertEqual(progress.values.first, 0)
            XCTAssertEqual(progress.values.last, 1)
            XCTAssertTrue(isMonotonic(progress.values))
        }
    }

    func testBatchUsesCollisionSafeNamesAndMonotonicProgress() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let first = try copyFixture(named: "task007-landscape.mkv", to: workspace)
        let second = try copyFixture(named: "task007-portrait.webm", to: workspace)
        let collision = outputDirectory.appendingPathComponent("task007-landscape.mp4")
        try Data("existing".utf8).write(to: collision)
        let engine = FFmpegConversionEngine(executableURL: try bundledFFmpegURL())
        let progress = LockedProgressRecorder()

        let outputs = try await engine.execute(
            try makePlan(inputs: [first, second], outputDirectory: outputDirectory)
        ) { progress.append($0) }

        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(outputs[0].lastPathComponent, "task007-landscape-2.mp4")
        XCTAssertEqual(outputs[1].lastPathComponent, "task007-portrait.mp4")
        XCTAssertTrue(isMonotonic(progress.values))
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertEqual(try Data(contentsOf: collision), Data("existing".utf8))
    }

    func testFailureRollsBackEarlierBatchOutputAndTemporaryFiles() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let valid = try copyFixture(named: "task007-landscape.mkv", to: workspace)
        let invalid = workspace.appendingPathComponent("broken.webm")
        try Data("not media".utf8).write(to: invalid)
        let engine = FFmpegConversionEngine(executableURL: try bundledFFmpegURL())

        do {
            _ = try await engine.execute(
                try makePlan(inputs: [valid, invalid], outputDirectory: outputDirectory)
            ) { _ in }
            XCTFail("Expected conversion failure")
        } catch {
            XCTAssertNotEqual(error as? ConversionError, .cancelled)
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path), [])
    }

    func testCancelForwardsToRunnerAndLeavesNoOutput() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let input = try copyFixture(named: "task007-landscape.mkv", to: workspace)
        let runner = BlockingFFmpegProcessRunner()
        let engine = FFmpegConversionEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner
        )
        let plan = try makePlan(inputs: [input], outputDirectory: outputDirectory)
        let task = Task { try await engine.execute(plan) { _ in } }

        try await Task.sleep(for: .milliseconds(50))
        await engine.cancel(jobID: plan.id)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
        let cancelledJobID = await runner.cancelledJobID
        XCTAssertEqual(cancelledJobID, plan.id)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path), [])
    }

    func testRejectsUnexpectedFFmpegVersionBeforeConversion() async throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let input = try copyFixture(named: "task007-landscape.mkv", to: workspace)
        let runner = VersionReportingFFmpegProcessRunner(
            versionText: "ffmpeg version 7.0\nconfiguration: --enable-gpl\n"
        )
        let engine = FFmpegConversionEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner
        )

        do {
            _ = try await engine.execute(
                try makePlan(inputs: [input], outputDirectory: outputDirectory)
            ) { _ in }
            XCTFail("Expected binary rejection")
        } catch {
            XCTAssertEqual(error as? ConversionError, .engineUnavailable)
        }
        let invocationCount = await runner.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    private func makePlan(inputs: [URL], outputDirectory: URL) throws -> ConversionPlan {
        let inputFiles = try inputs.map { url in
            InputFile(
                url: url,
                type: UTType(filenameExtension: url.pathExtension),
                fileSize: Int64(try fileSize(url)),
                displayName: url.lastPathComponent
            )
        }
        return try VideoConversionPlanBuilder().makePlan(
            inputs: inputFiles,
            intent: VideoIntent(
                compatibility: .highCompatibility,
                maxResolution: .source,
                targetBytes: nil,
                qualityPreference: .balanced
            ),
            outputDirectory: outputDirectory
        )
    }

    private func bundledFFmpegURL() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"))
    }

    private func copyFixture(named name: String, to directory: URL) throws -> URL {
        let source = try XCTUnwrap(
            Bundle(for: FFmpegConversionEngineTests.self)
                .url(forResource: name, withExtension: nil)
        )
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-FFmpegTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fileSize(_ url: URL) throws -> Int {
        try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    }

    private func assertValidOutput(_ output: URL, matchingFixture fixtureName: String) async throws {
        XCTAssertGreaterThan(try fileSize(output), 0)
        let asset = AVURLAsset(url: output)
        let isPlayable = try await asset.load(.isPlayable)
        XCTAssertTrue(isPlayable)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.12)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let videoDescriptions = try await videoTrack.load(.formatDescriptions)
        let videoDescription = try XCTUnwrap(videoDescriptions.first)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(videoDescription), kCMVideoCodecType_H264)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let audioDescriptions = try await audioTrack.load(.formatDescriptions)
        let audioDescription = try XCTUnwrap(audioDescriptions.first)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(audioDescription), kAudioFormatMPEG4AAC)
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let displaySize = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized.size
        if fixtureName.contains("portrait") {
            XCTAssertGreaterThan(displaySize.height, displaySize.width)
        } else {
            XCTAssertGreaterThan(displaySize.width, displaySize.height)
        }
    }

    private func isMonotonic(_ values: [Double]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }
}

private final class LockedProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.withLock { storage }
    }

    func append(_ value: Double) {
        lock.withLock { storage.append(value) }
    }
}

private actor BlockingFFmpegProcessRunner: FFmpegProcessRunning {
    private(set) var cancelledJobID: UUID?
    private var continuation: CheckedContinuation<FFmpegProcessResult, Error>?

    func run(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func cancel(jobID: UUID) {
        cancelledJobID = jobID
        continuation?.resume(throwing: ConversionError.cancelled)
        continuation = nil
    }
}

private actor VersionReportingFFmpegProcessRunner: FFmpegProcessRunning {
    private let versionText: String
    private(set) var invocationCount = 0

    init(versionText: String) {
        self.versionText = versionText
    }

    func run(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        invocationCount += 1
        eventHandler(.standardOutput(Data(versionText.utf8)))
        return FFmpegProcessResult(exitCode: 0)
    }

    func cancel(jobID: UUID) {}
}
