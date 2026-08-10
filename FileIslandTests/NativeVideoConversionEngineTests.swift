@preconcurrency import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers
import VideoToolbox
import XCTest
@testable import FileIsland

@MainActor
final class NativeVideoConversionEngineTests: XCTestCase {
    func testConvertsRotatedMOVWithAudioToPlayableH264AACMP4() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("竖屏 视频.mov")
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mov,
            duration: 0.6,
            withAudio: true,
            rotationDegrees: 90
        )
        let inputBytes = try Data(contentsOf: inputURL)
        let plan = try makePlan(inputURLs: [inputURL], resolution: .source, outputDirectory: outputDirectory)
        let progress = LockedVideoProgressRecorder()

        let outputs = try await NativeVideoConversionEngine().execute(plan, progress: progress.record)

        let output = try XCTUnwrap(outputs.first)
        let sourceInfo = try await VideoFixtureFactory.inspect(inputURL)
        let outputInfo = try await VideoFixtureFactory.inspect(output)
        XCTAssertEqual(output.lastPathComponent, "竖屏 视频.mp4")
        XCTAssertGreaterThan(try fileSize(output), 0)
        XCTAssertEqual(outputInfo.videoCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(outputInfo.audioCodec, kAudioFormatMPEG4AAC)
        XCTAssertTrue(outputInfo.isPlayable)
        XCTAssertEqual(outputInfo.duration, sourceInfo.duration, accuracy: 0.1)
        XCTAssertEqual(outputInfo.displaySize.width, sourceInfo.displaySize.width, accuracy: 1)
        XCTAssertEqual(outputInfo.displaySize.height, sourceInfo.displaySize.height, accuracy: 1)
        XCTAssertEqual(try Data(contentsOf: inputURL), inputBytes)
        XCTAssertEqual(progress.values.first, 0)
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertEqual(progress.values, progress.values.sorted())
    }

    func testMP4InputGetsCollisionSuffixAndIsNotUpscaledAt720p() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("clip.mp4")
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mp4,
            width: 320,
            height: 180,
            duration: 0.4,
            withAudio: false
        )
        let plan = try makePlan(inputURLs: [inputURL], resolution: .p720, outputDirectory: workspace)

        let outputs = try await NativeVideoConversionEngine().execute(plan) { _ in }

        let output = try XCTUnwrap(outputs.first)
        let info = try await VideoFixtureFactory.inspect(output)
        XCTAssertEqual(output.lastPathComponent, "clip-2.mp4")
        XCTAssertLessThanOrEqual(info.displaySize.width, 320)
        XCTAssertLessThanOrEqual(info.displaySize.height, 180)
        XCTAssertNil(info.audioCodec)
    }

    func testConvertsM4VWithAudioThroughNativeEngine() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("clip.m4v")
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mp4,
            duration: 0.5,
            withAudio: true
        )
        let inputBytes = try Data(contentsOf: inputURL)
        let plan = try makePlan(
            inputURLs: [inputURL],
            resolution: .source,
            outputDirectory: outputDirectory
        )

        let outputs = try await NativeVideoConversionEngine().execute(plan) { _ in }

        let output = try XCTUnwrap(outputs.first)
        let info = try await VideoFixtureFactory.inspect(output)
        XCTAssertEqual(output.lastPathComponent, "clip.mp4")
        XCTAssertGreaterThan(try fileSize(output), 0)
        XCTAssertTrue(info.isPlayable)
        XCTAssertEqual(info.videoCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(info.audioCodec, kAudioFormatMPEG4AAC)
        XCTAssertEqual(try Data(contentsOf: inputURL), inputBytes)
    }

    func testBatchFailureRollsBackCompletedVideo() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let validURL = workspace.appendingPathComponent("valid.mov")
        let invalidURL = workspace.appendingPathComponent("invalid.mov")
        try await VideoFixtureFactory.writeMovie(
            to: validURL,
            fileType: .mov,
            duration: 0.3,
            withAudio: false
        )
        try Data("not video".utf8).write(to: invalidURL)
        let plan = try makePlan(
            inputURLs: [validURL, invalidURL],
            resolution: .source,
            outputDirectory: outputDirectory
        )

        do {
            _ = try await NativeVideoConversionEngine().execute(plan) { _ in }
            XCTFail("Expected invalid media")
        } catch {
            XCTAssertEqual(error as? ConversionError, .invalidMedia)
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil),
            []
        )
    }

    func testBatchProgressIsMonotonicAcrossTwoVideos() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let firstURL = workspace.appendingPathComponent("first.mov")
        let secondURL = workspace.appendingPathComponent("second.mov")
        try await VideoFixtureFactory.writeMovie(
            to: firstURL,
            fileType: .mov,
            duration: 0.3,
            withAudio: false
        )
        try await VideoFixtureFactory.writeMovie(
            to: secondURL,
            fileType: .mov,
            duration: 0.3,
            withAudio: false
        )
        let plan = try makePlan(
            inputURLs: [firstURL, secondURL],
            resolution: .source,
            outputDirectory: outputDirectory
        )
        let progress = LockedVideoProgressRecorder()

        let outputs = try await NativeVideoConversionEngine().execute(plan, progress: progress.record)

        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(progress.values.first, 0)
        XCTAssertEqual(progress.values.last, 1)
        XCTAssertEqual(progress.values, progress.values.sorted())
        XCTAssertTrue(progress.values.contains(0.5))
    }

    func testCancelledPlanCreatesNoOutput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let inputURL = workspace.appendingPathComponent("cancel.mov")
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mov,
            duration: 0.3,
            withAudio: false
        )
        let plan = try makePlan(inputURLs: [inputURL], resolution: .source, outputDirectory: outputDirectory)
        let engine = NativeVideoConversionEngine()
        await engine.cancel(jobID: plan.id)

        do {
            _ = try await engine.execute(plan) { _ in }
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil),
            []
        )
    }

    func testTargetSizeProducesPlayableOutputWithinPerFileLimit() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let inputURL = workspace.appendingPathComponent("target.mov")
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mov,
            width: 640,
            height: 360,
            duration: 0.8,
            withAudio: true
        )
        let targetBytes: Int64 = 250_000
        let plan = try makePlan(
            inputURLs: [inputURL],
            resolution: .source,
            targetBytes: targetBytes,
            outputDirectory: outputDirectory
        )
        let progress = LockedVideoProgressRecorder()

        let outputs = try await NativeVideoConversionEngine().execute(plan, progress: progress.record)

        let output = try XCTUnwrap(outputs.first)
        let info = try await VideoFixtureFactory.inspect(output)
        XCTAssertGreaterThan(try fileSize(output), 0)
        XCTAssertLessThanOrEqual(Int64(try fileSize(output)), targetBytes)
        XCTAssertTrue(info.isPlayable)
        XCTAssertEqual(info.videoCodec, kCMVideoCodecType_H264)
        XCTAssertEqual(info.audioCodec, kAudioFormatMPEG4AAC)
        XCTAssertEqual(progress.values, progress.values.sorted())
        XCTAssertEqual(progress.values.last, 1)
    }

    func testTargetSizeAppliesToEveryBatchOutput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let firstURL = workspace.appendingPathComponent("first.mov")
        let secondURL = workspace.appendingPathComponent("second.mp4")
        try await VideoFixtureFactory.writeMovie(to: firstURL, fileType: .mov, duration: 0.5, withAudio: false)
        try await VideoFixtureFactory.writeMovie(to: secondURL, fileType: .mp4, duration: 0.5, withAudio: false)
        let targetBytes: Int64 = 200_000
        let plan = try makePlan(
            inputURLs: [firstURL, secondURL],
            resolution: .p720,
            targetBytes: targetBytes,
            outputDirectory: outputDirectory
        )
        let progress = LockedVideoProgressRecorder()

        let outputs = try await NativeVideoConversionEngine().execute(plan, progress: progress.record)

        XCTAssertEqual(outputs.count, 2)
        for output in outputs {
            XCTAssertGreaterThan(try fileSize(output), 0)
            XCTAssertLessThanOrEqual(Int64(try fileSize(output)), targetBytes)
        }
        XCTAssertEqual(progress.values, progress.values.sorted())
        XCTAssertTrue(progress.values.contains(0.5))
        XCTAssertEqual(progress.values.last, 1)
    }

    func testUnreachableVideoTargetLeavesNoOutput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let inputURL = workspace.appendingPathComponent("impossible.mov")
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mov,
            duration: 1,
            withAudio: true
        )
        let plan = try makePlan(
            inputURLs: [inputURL],
            resolution: .source,
            targetBytes: 10_000,
            outputDirectory: outputDirectory
        )

        do {
            _ = try await NativeVideoConversionEngine().execute(plan) { _ in }
            XCTFail("Expected unreachable target")
        } catch {
            XCTAssertEqual(error as? ConversionError, .targetSizeUnreachable)
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil),
            []
        )
    }

    func testStrictTargetAutomaticallyLowersResolution() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "Output", in: workspace)
        let inputURL = workspace.appendingPathComponent("large.mov")
        try await VideoFixtureFactory.writeMovie(
            to: inputURL,
            fileType: .mov,
            width: 960,
            height: 540,
            duration: 0.5,
            withAudio: false
        )
        let targetBytes: Int64 = 30_000
        let plan = try makePlan(
            inputURLs: [inputURL],
            resolution: .source,
            targetBytes: targetBytes,
            outputDirectory: outputDirectory
        )

        let outputs = try await NativeVideoConversionEngine().execute(plan) { _ in }
        let output = try XCTUnwrap(outputs.first)
        let info = try await VideoFixtureFactory.inspect(output)

        XCTAssertLessThanOrEqual(Int64(try fileSize(output)), targetBytes)
        XCTAssertLessThanOrEqual(max(info.displaySize.width, info.displaySize.height), 640)
    }

    private func makePlan(
        inputURLs: [URL],
        resolution: VideoResolution,
        targetBytes: Int64? = nil,
        outputDirectory: URL
    ) throws -> ConversionPlan {
        let inputs = try inputURLs.map { url in
            let contentType: UTType?
            switch url.pathExtension.lowercased() {
            case "mov": contentType = .quickTimeMovie
            case "mp4": contentType = .mpeg4Movie
            default: contentType = nil
            }
            return InputFile(
                url: url,
                type: contentType,
                fileSize: Int64(try fileSize(url)),
                displayName: url.lastPathComponent
            )
        }
        return try VideoConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: VideoIntent(
                compatibility: .highCompatibility,
                maxResolution: resolution,
                targetBytes: targetBytes,
                qualityPreference: .balanced
            ),
            outputDirectory: outputDirectory
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func createDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func fileSize(_ url: URL) throws -> Int {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }
}

private final class LockedVideoProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] { lock.withLock { storage } }

    func record(_ progress: Double) {
        lock.withLock { storage.append(progress) }
    }
}
