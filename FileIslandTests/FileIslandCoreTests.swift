import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class FileIslandCoreTests: XCTestCase {
    func testCapabilitiesComeFromSharedMatrixAndPresetCatalog() async throws {
        let preset = makeImagePreset(id: "test-image")
        let core = makeCore(
            scan: InputScanResult(selections: [], inputs: []),
            presets: [preset]
        )

        let capabilities = try await core.capabilities()

        XCTAssertEqual(capabilities.schemaVersion, 1)
        XCTAssertEqual(capabilities.image.inputFormats, ["heic", "heif", "jpeg", "png", "tiff", "webp"])
        XCTAssertEqual(capabilities.image.outputFormats, ["jpeg", "png"])
        XCTAssertEqual(capabilities.video.nativeInputFormats, ["m4v", "mov", "mp4"])
        XCTAssertEqual(capabilities.video.fallbackInputFormats, ["mkv", "webm"])
        XCTAssertEqual(capabilities.presets.map(\.id), ["test-image"])
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

    private func makeCore(
        scan: InputScanResult,
        presets: [ConversionPreset] = [],
        coordinator: any BatchJobCoordinating = CoreRecordingBatchCoordinator()
    ) -> FileIslandCore {
        FileIslandCore(
            fileInspector: CoreUnusedFileInspector(),
            inputScanner: CoreStubInputScanner(scan: scan),
            conversionEngine: CoreUnusedConversionEngine(),
            batchCoordinator: coordinator,
            presetCatalogLoader: CoreStubPresetLoader(presets: presets)
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
    ) async throws -> [URL] {
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
