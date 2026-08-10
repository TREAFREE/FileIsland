import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class BatchJobCoordinatorTests: XCTestCase {
    func testPublishesNestedOutputsWithCollisionSafeNamesAndMonotonicProgress() async throws {
        let output = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let request = try makeRequest(output: output, imageCount: 2, videoCount: 1)
        let existingDirectory = output.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: existingDirectory.appendingPathComponent("image-0.png"))
        let engine = BatchTestEngine()
        let recorder = ProgressRecorder()

        let result = try await BatchJobCoordinator(conversionEngine: engine).execute(request) {
            recorder.append($0)
        }

        XCTAssertEqual(result.outputURLs.count, 3)
        XCTAssertTrue(result.outputURLs.contains { $0.lastPathComponent == "image-0-2.png" })
        XCTAssertTrue(result.outputURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let values = recorder.values.map(\.fraction)
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(recorder.values.last?.currentFile, 3)
        XCTAssertEqual(recorder.values.last?.totalFiles, 3)
        XCTAssertFalse(containsStagingDirectory(output))
        let engineMetrics = await engine.metrics
        XCTAssertEqual(engineMetrics.maximumConcurrentExecutions, 1)
    }

    func testLaterGroupFailureRollsBackAllStagedWork() async throws {
        let output = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let request = try makeRequest(output: output, imageCount: 1, videoCount: 1)
        let engine = BatchTestEngine(failingInvocation: 2)

        do {
            _ = try await BatchJobCoordinator(conversionEngine: engine).execute(request) { _ in }
            XCTFail("Expected the second group to fail")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .conversionFailed(underlying: "test"))
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
        XCTAssertFalse(containsStagingDirectory(output))
    }

    func testCancellationForwardsToActivePlanAndLeavesNoResidue() async throws {
        let output = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let request = try makeRequest(output: output, imageCount: 20, videoCount: 0)
        let engine = BatchTestEngine(stepDelayNanoseconds: 20_000_000)
        let coordinator = BatchJobCoordinator(conversionEngine: engine)
        let task = Task {
            try await coordinator.execute(request) { _ in }
        }
        try await Task.sleep(nanoseconds: 60_000_000)

        await coordinator.cancel(requestID: request.id)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as ConversionError {
            XCTAssertEqual(error, .cancelled)
        }
        let engineMetrics = await engine.metrics
        XCTAssertEqual(engineMetrics.cancelledJobCount, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), [])
        XCTAssertFalse(containsStagingDirectory(output))
    }

    func testPublicationFailureRemovesAlreadyPublishedFilesAndCreatedDirectories() async throws {
        let output = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: output) }
        let request = try makeRequest(output: output, imageCount: 1, videoCount: 1)
        let blockingFile = output.appendingPathComponent("videos")
        try Data([0x01]).write(to: blockingFile)

        do {
            _ = try await BatchJobCoordinator(conversionEngine: BatchTestEngine())
                .execute(request) { _ in }
            XCTFail("Expected publication to fail on a non-directory path component")
        } catch {
            XCTAssertTrue(error is ConversionError)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: blockingFile.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: output.appendingPathComponent("nested/image-0.png").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: output.appendingPathComponent("nested").path
        ))
        XCTAssertFalse(containsStagingDirectory(output))
    }

    private func makeRequest(output: URL, imageCount: Int, videoCount: Int) throws -> BatchConversionRequest {
        let root = URL(fileURLWithPath: "/tmp/source", isDirectory: true)
        let selection = InputSelection.folder(root)
        var inputs: [BatchInput] = []
        for index in 0..<imageCount {
            inputs.append(try input(
                root: root,
                selection: selection,
                path: "nested/image-\(index).jpg",
                type: .jpeg
            ))
        }
        for index in 0..<videoCount {
            inputs.append(try input(
                root: root,
                selection: selection,
                path: "videos/video-\(index).mov",
                type: .quickTimeMovie
            ))
        }
        return try BatchRequestBuilder().makeRequest(
            scan: InputScanResult(selections: [selection], inputs: inputs),
            imageIntent: ImageIntent(
                outputFormat: .png,
                maxPixelDimension: nil,
                targetBytes: nil,
                qualityPreference: .balanced,
                stripMetadata: true
            ),
            videoIntent: VideoIntent(
                compatibility: .highCompatibility,
                maxResolution: .source,
                targetBytes: nil,
                qualityPreference: .balanced
            ),
            outputDirectory: output
        )
    }

    private func input(
        root: URL,
        selection: InputSelection,
        path: String,
        type: UTType
    ) throws -> BatchInput {
        let url = root.appendingPathComponent(path)
        return BatchInput(
            file: InputFile(url: url, type: type, fileSize: 100, displayName: url.lastPathComponent),
            selection: selection,
            relativePath: try SafeRelativePath(path)
        )
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func containsStagingDirectory(_ output: URL) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: output.path)) ?? [])
            .contains { $0.hasPrefix(".fileisland-") }
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BatchProgress] = []

    var values: [BatchProgress] { lock.withLock { storage } }
    func append(_ value: BatchProgress) { lock.withLock { storage.append(value) } }
}

private actor BatchTestEngine: ConversionEngine {
    private let failingInvocation: Int?
    private let stepDelayNanoseconds: UInt64
    private var invocations = 0
    private var activeExecutions = 0
    private var cancelledJobs: Set<UUID> = []
    private(set) var maximumConcurrentExecutions = 0
    private(set) var cancelledJobCount = 0

    var metrics: (maximumConcurrentExecutions: Int, cancelledJobCount: Int) {
        (maximumConcurrentExecutions, cancelledJobCount)
    }

    init(failingInvocation: Int? = nil, stepDelayNanoseconds: UInt64 = 0) {
        self.failingInvocation = failingInvocation
        self.stepDelayNanoseconds = stepDelayNanoseconds
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool { true }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        invocations += 1
        let invocation = invocations
        activeExecutions += 1
        maximumConcurrentExecutions = max(maximumConcurrentExecutions, activeExecutions)
        defer { activeExecutions -= 1 }
        if failingInvocation == invocation {
            throw ConversionError.conversionFailed(underlying: "test")
        }
        guard case let .chosenDirectory(directory, _) = plan.outputPolicy else {
            throw ConversionError.permissionDenied
        }
        var outputs: [URL] = []
        for (index, input) in plan.inputs.enumerated() {
            if stepDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: stepDelayNanoseconds)
            }
            guard !cancelledJobs.contains(plan.id), !Task.isCancelled else {
                throw ConversionError.cancelled
            }
            let ext = plan.steps.first?.outputExtension ?? "bin"
            let output = directory
                .appendingPathComponent(input.url.deletingPathExtension().lastPathComponent)
                .appendingPathExtension(ext)
            try Data([UInt8(index % 255)]).write(to: output)
            outputs.append(output)
            progress(Double(index + 1) / Double(plan.inputs.count))
        }
        return outputs
    }

    func cancel(jobID: UUID) async {
        cancelledJobCount += 1
        cancelledJobs.insert(jobID)
    }
}

private extension ConversionStep {
    var outputExtension: String {
        switch self {
        case let .image(intent): intent.outputFormat?.filenameExtension ?? "jpg"
        case .video: "mp4"
        }
    }
}
