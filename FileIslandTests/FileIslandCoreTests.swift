import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class FileIslandCoreTests: XCTestCase {
    func testCapabilitiesComeFromSharedMatrixAndPresetCatalog() async throws {
        let preset = makeImagePreset(id: "test-image")
        let core = makeCore(
            scan: InputScanResult(selections: [], inputs: []),
            presets: [preset],
            splitProbe: CoreStubVideoSplitProbe(),
            splitCoordinator: CoreRecordingVideoSplitCoordinator()
        )

        let capabilities = try await core.capabilities()

        XCTAssertEqual(capabilities.schemaVersion, 1)
        XCTAssertEqual(capabilities.image.inputFormats, ["avif", "bmp", "gif", "heic", "heif", "jpeg", "png", "tiff", "webp"])
        XCTAssertEqual(capabilities.image.outputFormats, ["jpeg", "png"])
        XCTAssertEqual(capabilities.video.nativeInputFormats, ["m4v", "mov", "mp4"])
        XCTAssertEqual(capabilities.video.fallbackInputFormats, ["3gp", "avi", "flv", "mkv", "mpeg", "ts", "webm", "wmv"])
        XCTAssertEqual(capabilities.audio.inputFormats, ["aac", "ac3", "aiff", "flac", "m4a", "mp3", "ogg", "opus", "wav"])
        XCTAssertEqual(capabilities.audio.outputFormats, ["m4a", "wav", "flac", "aiff"])
        XCTAssertEqual(capabilities.presets.map(\.id), ["test-image"])
        XCTAssertEqual(
            capabilities.videoSplit,
            CoreVideoSplitCapabilities(
                constraintSources: ["custom"],
                modes: ["fast-keyframe-copy"],
                inputContainers: ["mp4", "mov"],
                videoCodecs: ["h264"],
                audioCodecs: ["aac"],
                allowsNoAudio: true,
                customConstraints: CoreVideoSplitConstraintCapabilities(
                    supported: ["maxBytes", "maxDurationSeconds"],
                    requiresAtLeastOne: true,
                    decimalMegabyteBytes: 1_000_000,
                    durationUnit: "seconds",
                    durationPrecisionMilliseconds: 1
                )
            )
        )
    }

    func testCapabilitiesOmitVideoSplitWhenRuntimeIsUnavailable() async throws {
        let core = makeCore(scan: InputScanResult(selections: [], inputs: []))

        let capabilities = try await core.capabilities()

        XCTAssertNil(capabilities.videoSplit)
    }

    func testInspectRequiresRecursiveFlagForFolderRoots() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let core = makeCore(scan: InputScanResult(selections: [], inputs: []))

        do {
            _ = try await core.inspect(paths: [folder], recursive: false)
            XCTFail("Expected recursiveRequired")
        } catch {
            XCTAssertEqual(error as? FileIslandCoreError, .recursiveRequired)
        }
    }

    func testConvertBuildsExistingPlansAndForwardsCoordinatorResult() async throws {
        let image = makeInput(
            name: "海 岛.png",
            type: .png,
            formatExtension: "png",
            relativePath: "nested/海 岛.png"
        )
        let unknown = makeInput(
            name: "notes.txt",
            type: .plainText,
            formatExtension: "txt",
            relativePath: "notes.txt"
        )
        let scan = InputScanResult(
            selections: [.folder(URL(fileURLWithPath: "/input"))],
            inputs: [image, unknown]
        )
        let coordinator = CoreRecordingBatchCoordinator()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let core = makeCore(scan: scan, coordinator: coordinator)
        let requestID = UUID()
        let request = CoreConversionRequest(
            id: requestID,
            paths: [URL(fileURLWithPath: "/input")],
            recursive: true,
            outputDirectory: output,
            imageIntent: ImageIntent(
                outputFormat: .jpeg,
                maxPixelDimension: 2_048,
                targetBytes: nil,
                qualityPreference: .balanced,
                stripMetadata: true
            ),
            videoIntent: nil,
            imagePresetID: nil,
            videoPresetID: nil
        )

        let result = try await core.convert(request) { _ in }
        let recorded = await coordinator.requests

        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.id, requestID)
        XCTAssertEqual(recorded.first?.group(.image).plan?.steps.count, 1)
        XCTAssertEqual(recorded.first?.group(.unsupported).inputs.count, 1)
        XCTAssertEqual(result.requestID, requestID)
        XCTAssertEqual(result.failClosedCount, 1)
    }

    func testConvertRejectsSupportedGroupWithoutExplicitIntentOrPreset() async throws {
        let image = makeInput(
            name: "photo.png",
            type: .png,
            formatExtension: "png",
            relativePath: "photo.png"
        )
        let scan = InputScanResult(selections: [image.selection], inputs: [image])
        let output = FileManager.default.temporaryDirectory
        let core = makeCore(scan: scan)
        let request = CoreConversionRequest(
            paths: [image.file.url],
            recursive: false,
            outputDirectory: output
        )

        do {
            _ = try await core.convert(request) { _ in }
            XCTFail("Expected missing image configuration")
        } catch {
            XCTAssertEqual(error as? FileIslandCoreError, .missingImageConfiguration)
        }
    }

    func testCancellingCallerCancelsTheSharedCoordinatorRequest() async throws {
        let image = makeInput(
            name: "photo.png",
            type: .png,
            formatExtension: "png",
            relativePath: "photo.png"
        )
        let scan = InputScanResult(selections: [image.selection], inputs: [image])
        let coordinator = CoreBlockingBatchCoordinator()
        let core = makeCore(scan: scan, coordinator: coordinator)
        let requestID = UUID()
        let request = CoreConversionRequest(
            id: requestID,
            paths: [image.file.url],
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
        let task = Task { try await core.convert(request) { _ in } }
        while !(await coordinator.isStarted) { await Task.yield() }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
        let cancelledRequestIDs = await coordinator.cancelledRequestIDs
        XCTAssertEqual(cancelledRequestIDs, [requestID])
    }

    func testSplitBuildsFastCustomPlansAndUsesSharedCoordinator() async throws {
        let video = makeInput(
            name: "Movie.mp4",
            type: .mpeg4Movie,
            formatExtension: "mp4",
            relativePath: "nested/file.mp4"
        )
        let scan = InputScanResult(selections: [video.selection], inputs: [video])
        let coordinator = CoreRecordingVideoSplitCoordinator()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let core = makeCore(
            scan: scan,
            splitProbe: CoreStubVideoSplitProbe(),
            splitCoordinator: coordinator
        )
        let requestID = UUID()
        let recorder = CoreSplitEventRecorder()

        let result = try await core.split(
            CoreVideoSplitRequest(
                id: requestID,
                paths: [video.file.url],
                recursive: false,
                outputDirectory: output,
                maxBytes: nil,
                maxDurationMilliseconds: 4_000
            )
        ) { recorder.append($0) }

        let recorded = await coordinator.requests
        let request = try XCTUnwrap(recorded.first)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(request.id, requestID)
        XCTAssertEqual(request.items.count, 1)
        XCTAssertEqual(request.items[0].plan.intent.source, .custom)
        XCTAssertEqual(request.items[0].plan.intent.mode, .fastKeyframeCopy)
        XCTAssertEqual(request.items[0].plan.intent.constraints.maxDurationMilliseconds, 4_000)
        XCTAssertTrue(
            request.items[0].plan.segments.allSatisfy {
                $0.outputRelativePath.string.hasPrefix("nested/file — Split/")
            }
        )
        XCTAssertEqual(result.requestID, requestID)
        XCTAssertEqual(result.segmentCount, request.items[0].plan.segments.count)
        let events = recorder.values
        XCTAssertTrue(events.contains { if case .plan = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .segment = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .validation = $0 { true } else { false } })
        XCTAssertTrue(events.contains { if case .publication = $0 { true } else { false } })
    }

    func testSplitRejectsMissingLimitsBeforeRuntimeAccess() async {
        let core = makeCore(scan: InputScanResult(selections: [], inputs: []))
        do {
            _ = try await core.split(
                CoreVideoSplitRequest(
                    paths: [URL(fileURLWithPath: "/video.mp4")],
                    recursive: false,
                    outputDirectory: FileManager.default.temporaryDirectory,
                    maxBytes: nil,
                    maxDurationMilliseconds: nil
                )
            ) { _ in }
            XCTFail("Expected invalid split configuration")
        } catch {
            XCTAssertEqual(error as? FileIslandCoreError, .invalidSplitConfiguration)
        }
    }

    func testSplitRejectsMixedVideoAndUnsupportedInputsWithoutSilentlySkipping() async {
        let video = makeInput(
            name: "movie.mp4",
            type: .mpeg4Movie,
            formatExtension: "mp4",
            relativePath: "movie.mp4"
        )
        let unsupported = makeInput(
            name: "notes.txt",
            type: .plainText,
            formatExtension: "txt",
            relativePath: "notes.txt"
        )
        let coordinator = CoreRecordingVideoSplitCoordinator()
        let core = makeCore(
            scan: InputScanResult(
                selections: [video.selection, unsupported.selection],
                inputs: [video, unsupported]
            ),
            splitProbe: CoreStubVideoSplitProbe(),
            splitCoordinator: coordinator
        )

        do {
            _ = try await core.split(
                CoreVideoSplitRequest(
                    paths: [video.file.url, unsupported.file.url],
                    recursive: false,
                    outputDirectory: FileManager.default.temporaryDirectory,
                    maxBytes: nil,
                    maxDurationMilliseconds: 4_000
                )
            ) { _ in }
            XCTFail("Expected mixed split input to fail closed")
        } catch {
            XCTAssertEqual(error as? FileIslandCoreError, .unsupportedInput)
        }
        let recordedRequests = await coordinator.requests
        XCTAssertTrue(recordedRequests.isEmpty)
    }

    private func makeCore(
        scan: InputScanResult,
        presets: [ConversionPreset] = [],
        coordinator: any BatchJobCoordinating = CoreRecordingBatchCoordinator(),
        splitProbe: (any VideoSplitProbing)? = nil,
        splitCoordinator: (any VideoSplitJobCoordinating)? = nil
    ) -> FileIslandCore {
        FileIslandCore(
            fileInspector: CoreUnusedFileInspector(),
            inputScanner: CoreStubInputScanner(scan: scan),
            conversionEngine: CoreUnusedConversionEngine(),
            batchCoordinator: coordinator,
            presetCatalogLoader: CoreStubPresetLoader(presets: presets),
            videoSplitProbe: splitProbe,
            videoSplitCoordinator: splitCoordinator
        )
    }

    private func makeInput(
        name: String,
        type: UTType,
        formatExtension: String,
        relativePath: String
    ) -> BatchInput {
        let url = URL(fileURLWithPath: "/virtual/\(UUID().uuidString)/file.\(formatExtension)")
        return BatchInput(
            file: InputFile(url: url, type: type, fileSize: 123, displayName: name),
            selection: .file(url),
            relativePath: try! SafeRelativePath(relativePath)
        )
    }

    private func makeImagePreset(id: String) -> ConversionPreset {
        ConversionPreset(
            id: id,
            version: 1,
            displayName: "Test Image",
            summary: "Test",
            mediaType: .image,
            output: PresetOutput(
                imageFormat: .jpeg,
                container: nil,
                videoCodec: nil,
                audioCodec: nil,
                compatibility: nil
            ),
            constraints: PresetConstraints(
                maxPixelDimension: 2_048,
                maxResolution: nil,
                maxBytes: nil
            ),
            options: PresetOptions(quality: .balanced, stripMetadata: true)
        )
    }
}

private struct CoreStubVideoSplitProbe: VideoSplitProbing {
    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            durationMilliseconds: 10_000,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: 800_000,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 0,
            audioStartMilliseconds: 0,
            audioDurationMilliseconds: 10_000,
            userMetadataKeys: [],
            frameDurationMilliseconds: 40,
            keyframeMilliseconds: stride(from: Int64(0), to: 10_000, by: 1_000).map { $0 }
        )
    }
}

private actor CoreRecordingVideoSplitCoordinator: VideoSplitJobCoordinating {
    private(set) var requests: [VideoSplitBatchRequest] = []

    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        requests.append(request)
        let segmentCount = request.items.reduce(0) { $0 + $1.plan.segments.count }
        let outputs = request.items.flatMap { item in
            item.plan.segments.map {
                request.outputDirectory.appendingPathComponent($0.outputRelativePath.string)
            }
        }
        event(
            .progress(
                VideoSplitBatchProgress(
                    requestID: request.id,
                    fraction: 1,
                    currentFile: request.items.count,
                    totalFiles: request.items.count,
                    currentDisplayName: request.items.last?.input.file.displayName,
                    currentSegment: request.items.last?.plan.segments.count,
                    totalSegments: request.items.last?.plan.segments.count
                )
            )
        )
        event(
            .validationCompleted(
                requestID: request.id,
                segmentCount: segmentCount
            )
        )
        event(.publicationCompleted(requestID: request.id, outputURLs: outputs))
        return VideoSplitBatchResult(
            requestID: request.id,
            outputURLs: outputs,
            segmentCount: segmentCount,
            totalBytes: 123
        )
    }

    func cancel(requestID: UUID) async {}
}

private final class CoreSplitEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CoreVideoSplitEvent] = []

    var values: [CoreVideoSplitEvent] { lock.withLock { storage } }
    func append(_ value: CoreVideoSplitEvent) { lock.withLock { storage.append(value) } }
}

private struct CoreStubInputScanner: InputScanning {
    let scan: InputScanResult
    func scan(urls: [URL]) async throws -> InputScanResult { scan }
}

private struct CoreStubPresetLoader: PresetCatalogLoading {
    let presets: [ConversionPreset]
    func loadPresets() async throws -> [ConversionPreset] { presets }
}

private struct CoreUnusedFileInspector: FileInspecting {
    func inspect(urls: [URL]) async throws -> [InputFile] { [] }
}

private actor CoreUnusedConversionEngine: ConversionEngine {
    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool { false }
    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult {
        throw ConversionError.engineUnavailable
    }
    func cancel(jobID: UUID) async {}
}

private actor CoreRecordingBatchCoordinator: BatchJobCoordinating {
    private(set) var requests: [BatchConversionRequest] = []

    func execute(
        _ request: BatchConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> BatchResult {
        requests.append(request)
        progress(
            BatchProgress(
                requestID: request.id,
                fraction: 1,
                currentFile: request.processCount,
                totalFiles: request.processCount,
                currentDisplayName: request.groups.flatMap(\.inputs).last?.file.displayName
            )
        )
        return BatchResult(
            outputURLs: [],
            skippedCount: request.skippedCount,
            failClosedCount: request.failClosedCount
        )
    }

    func cancel(requestID: UUID) async {}
}

private actor CoreBlockingBatchCoordinator: BatchJobCoordinating {
    private(set) var isStarted = false
    private(set) var cancelledRequestIDs: [UUID] = []
    private var continuation: CheckedContinuation<BatchResult, Error>?

    func execute(
        _ request: BatchConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> BatchResult {
        isStarted = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func cancel(requestID: UUID) async {
        cancelledRequestIDs.append(requestID)
        continuation?.resume(throwing: ConversionError.cancelled)
        continuation = nil
    }
}
