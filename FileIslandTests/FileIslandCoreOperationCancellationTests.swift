import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("FileIslandCore operation lifecycle and cancellation")
struct FileIslandCoreOperationCancellationTests {
    @Test("Core forwards validation then rollback when split publication fails")
    func splitPublicationFailureLifecycle() async throws {
        let input = try makeVideoInput(relativePath: "nested/file.mp4")
        let scanner = CoreCancellationStaticScanner(
            result: InputScanResult(selections: [input.selection], inputs: [input])
        )
        let coordinator = CoreCancellationFailingPublicationSplitCoordinator()
        let core = makeCore(
            scanner: scanner,
            splitProbe: CoreCancellationStaticSplitProbe(),
            splitCoordinator: coordinator
        )
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let request = CoreVideoSplitRequest(
            paths: [input.file.url],
            recursive: false,
            outputDirectory: outputDirectory,
            maxBytes: nil,
            maxDurationMilliseconds: 4_000
        )
        let events = CoreCancellationSplitEventRecorder()

        do {
            _ = try await core.split(request, event: events.append)
            Issue.record("Expected split publication to fail")
        } catch let error as VideoSplitJobError {
            #expect(error == .publicationFailed)
        } catch {
            Issue.record("Unexpected split error: \(error)")
        }

        let lifecycle = events.values.filter {
            if case .validation = $0 { return true }
            if case .publication = $0 { return true }
            if case .rollback = $0 { return true }
            return false
        }
        #expect(
            lifecycle == [
                .validation(
                    CoreVideoSplitValidationEvent(
                        requestID: request.id,
                        segmentCount: 1
                    )
                ),
                .rollback(requestID: request.id)
            ]
        )
    }

    @Test("Explicit cancellation interrupts conversion input scanning")
    func cancellationDuringConversionScan() async throws {
        let scanner = CoreCancellationBlockingScanner()
        let coordinator = CoreCancellationRecordingBatchCoordinator()
        let core = makeCore(scanner: scanner, batchCoordinator: coordinator)
        let request = makeConversionRequest()
        let task = Task { try await core.convert(request) { _ in } }
        await scanner.waitUntilStarted()

        await core.cancel(requestID: request.id)

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await scanner.wasCancelled)
        #expect(await coordinator.executionCount == 0)
    }

    @Test("Explicit cancellation interrupts split probing before coordination")
    func cancellationDuringSplitProbe() async throws {
        let input = try makeVideoInput()
        let scanner = CoreCancellationStaticScanner(
            result: InputScanResult(selections: [input.selection], inputs: [input])
        )
        let probe = CoreCancellationBlockingSplitProbe()
        let coordinator = CoreCancellationRecordingSplitCoordinator()
        let core = makeCore(
            scanner: scanner,
            splitProbe: probe,
            splitCoordinator: coordinator
        )
        let request = CoreVideoSplitRequest(
            paths: [input.file.url],
            recursive: false,
            outputDirectory: FileManager.default.temporaryDirectory,
            maxBytes: nil,
            maxDurationMilliseconds: 4_000
        )
        let task = Task { try await core.split(request) { _ in } }
        await probe.waitUntilStarted()

        await core.cancel(requestID: request.id)

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await probe.wasCancelled)
        #expect(await coordinator.executionCount == 0)
    }

    @Test("A duplicate identity across conversion and split fails closed")
    func duplicateActiveIdentityFailsClosedAcrossOperations() async throws {
        let scanner = CoreCancellationBlockingScanner()
        let core = makeCore(scanner: scanner)
        let request = makeConversionRequest()
        let first = Task { try await core.convert(request) { _ in } }
        await scanner.waitUntilStarted()

        await #expect(throws: FileIslandCoreOperationError.requestAlreadyActive) {
            try await core.split(
                CoreVideoSplitRequest(
                    id: request.id,
                    paths: request.paths,
                    recursive: false,
                    outputDirectory: request.outputDirectory,
                    maxBytes: nil,
                    maxDurationMilliseconds: 4_000
                )
            ) { _ in }
        }

        await core.cancel(requestID: request.id)
        await #expect(throws: CancellationError.self) { try await first.value }
    }

    @Test("Late cancellation cannot poison reuse of a completed request identity")
    func lateCancellationIsNoOp() async throws {
        let input = try makeImageInput()
        let scanner = CoreCancellationStaticScanner(
            result: InputScanResult(selections: [input.selection], inputs: [input])
        )
        let coordinator = CoreCancellationRecordingBatchCoordinator()
        let core = makeCore(scanner: scanner, batchCoordinator: coordinator)
        let request = makeConversionRequest(id: UUID(), inputURL: input.file.url)

        _ = try await core.convert(request) { _ in }
        await core.cancel(requestID: request.id)
        _ = try await core.convert(request) { _ in }

        #expect(await coordinator.executionCount == 2)
    }

    private func makeCore(
        scanner: any InputScanning,
        batchCoordinator: any BatchJobCoordinating = CoreCancellationRecordingBatchCoordinator(),
        splitProbe: (any VideoSplitProbing)? = nil,
        splitCoordinator: (any VideoSplitJobCoordinating)? = nil
    ) -> FileIslandCore {
        FileIslandCore(
            fileInspector: CoreCancellationUnusedInspector(),
            inputScanner: scanner,
            conversionEngine: CoreCancellationUnusedEngine(),
            batchCoordinator: batchCoordinator,
            presetCatalogLoader: CoreCancellationPresetLoader(),
            videoSplitProbe: splitProbe,
            videoSplitCoordinator: splitCoordinator
        )
    }

    private func makeConversionRequest(
        id: UUID = UUID(),
        inputURL: URL = URL(fileURLWithPath: "/virtual/photo.png")
    ) -> CoreConversionRequest {
        CoreConversionRequest(
            id: id,
            paths: [inputURL],
            recursive: false,
            outputDirectory: FileManager.default.temporaryDirectory,
            imageIntent: ImageIntent(
                outputFormat: .jpeg,
                maxPixelDimension: nil,
                targetBytes: nil,
                qualityPreference: .balanced,
                stripMetadata: false
            )
        )
    }

    private func makeImageInput() throws -> BatchInput {
        let url = URL(fileURLWithPath: "/virtual/\(UUID().uuidString)/photo.png")
        return BatchInput(
            file: InputFile(url: url, type: .png, fileSize: 123, displayName: "photo.png"),
            selection: .file(url),
            relativePath: try SafeRelativePath("photo.png")
        )
    }

    private func makeVideoInput(
        relativePath: String = "movie.mp4"
    ) throws -> BatchInput {
        let safeRelativePath = try SafeRelativePath(relativePath)
        let fileName = try #require(safeRelativePath.components.last)
        let url = URL(fileURLWithPath: "/virtual/\(UUID().uuidString)/\(fileName)")
        return BatchInput(
            file: InputFile(
                url: url,
                type: .mpeg4Movie,
                fileSize: 123,
                displayName: fileName
            ),
            selection: .file(url),
            relativePath: safeRelativePath
        )
    }
}

private actor CoreCancellationBlockingScanner: InputScanning {
    private var started = false
    private var cancelled = false
    private var cancellationRequested = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<InputScanResult, any Error>?

    var wasCancelled: Bool { cancelled }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func scan(urls _: [URL]) async throws -> InputScanResult {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if cancellationRequested || Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    resultContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelPendingScan() }
        }
    }

    private func cancelPendingScan() {
        cancellationRequested = true
        cancelled = true
        resultContinuation?.resume(throwing: CancellationError())
        resultContinuation = nil
    }
}

private struct CoreCancellationStaticScanner: InputScanning {
    let result: InputScanResult
    func scan(urls _: [URL]) async throws -> InputScanResult { result }
}

private actor CoreCancellationBlockingSplitProbe: VideoSplitProbing {
    private var started = false
    private var cancelled = false
    private var cancellationRequested = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<VideoSplitSourceFacts, any Error>?

    var wasCancelled: Bool { cancelled }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if cancellationRequested || Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    resultContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelPendingProbe() }
        }
    }

    private func cancelPendingProbe() {
        cancellationRequested = true
        cancelled = true
        resultContinuation?.resume(throwing: CancellationError())
        resultContinuation = nil
    }
}

private struct CoreCancellationStaticSplitProbe: VideoSplitProbing {
    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            durationMilliseconds: 10_000,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: 1_000_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 0,
            audioStartMilliseconds: 0,
            audioDurationMilliseconds: 10_000,
            userMetadataKeys: [],
            frameDurationMilliseconds: 40,
            keyframeMilliseconds: [0, 2_000, 4_000, 6_000, 8_000]
        )
    }
}

private actor CoreCancellationRecordingBatchCoordinator: BatchJobCoordinating {
    private(set) var executionCount = 0

    func execute(
        _ request: BatchConversionRequest,
        progress _: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> BatchResult {
        executionCount += 1
        return BatchResult(
            outputURLs: [],
            skippedCount: request.skippedCount,
            failClosedCount: request.failClosedCount
        )
    }

    func cancel(requestID _: UUID) async {}
}

private actor CoreCancellationRecordingSplitCoordinator: VideoSplitJobCoordinating {
    private(set) var executionCount = 0

    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        executionCount += 1
        event(.validationCompleted(requestID: request.id, segmentCount: 0))
        event(.publicationCompleted(requestID: request.id, outputURLs: []))
        return VideoSplitBatchResult(
            requestID: request.id,
            outputURLs: [],
            segmentCount: 0,
            totalBytes: 0
        )
    }

    func cancel(requestID _: UUID) async {}
}

private actor CoreCancellationFailingPublicationSplitCoordinator: VideoSplitJobCoordinating {
    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        event(.validationCompleted(requestID: request.id, segmentCount: 1))
        throw VideoSplitJobError.publicationFailed
    }

    func cancel(requestID _: UUID) async {}
}

private final class CoreCancellationSplitEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CoreVideoSplitEvent] = []

    var values: [CoreVideoSplitEvent] { lock.withLock { storage } }

    func append(_ event: CoreVideoSplitEvent) {
        lock.withLock { storage.append(event) }
    }
}

private struct CoreCancellationUnusedInspector: FileInspecting {
    func inspect(urls _: [URL]) async throws -> [InputFile] { [] }
}

private struct CoreCancellationPresetLoader: PresetCatalogLoading {
    func loadPresets() async throws -> [ConversionPreset] { [] }
}

private actor CoreCancellationUnusedEngine: ConversionEngine {
    nonisolated func canHandle(_: ConversionPlan) -> Bool { false }
    func execute(
        _: ConversionPlan,
        progress _: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult {
        throw ConversionError.engineUnavailable
    }
    func cancel(jobID _: UUID) async {}
}
