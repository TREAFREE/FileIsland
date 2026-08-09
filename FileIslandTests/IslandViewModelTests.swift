import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

@MainActor
final class IslandViewModelTests: XCTestCase {
    func testDropBuildsExpandedSummaryFromInspectorResult() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.jpg"),
            type: .jpeg,
            fileSize: 42,
            displayName: "photo.jpg"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))

        viewModel.receiveDrop(urls: [file.url])
        XCTAssertEqual(viewModel.state, .inspecting)

        for _ in 0..<20 where viewModel.state == .inspecting {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state, .droppedSummary([file]))
        XCTAssertEqual(viewModel.state.layoutMode, .expanded)
    }

    func testDragExitRestoresDroppedSummary() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.jpg"),
            type: .jpeg,
            fileSize: 42,
            displayName: "photo.jpg"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))

        viewModel.receiveDrop(urls: [file.url])
        for _ in 0..<20 where viewModel.state == .inspecting {
            await Task.yield()
        }

        viewModel.dragEntered()
        viewModel.dragExited()

        XCTAssertEqual(viewModel.state, .droppedSummary([file]))
    }

    func testJPEGDropOffersPNGActionDefaults() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.jpg"),
            type: .jpeg,
            fileSize: 42,
            displayName: "photo.jpg"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)

        viewModel.continueToImageActions()

        XCTAssertEqual(viewModel.state, .actionSelection([file]))
        XCTAssertEqual(viewModel.availableOutputFormats, [.png])
        XCTAssertEqual(viewModel.imageIntent?.outputFormat, .png)
        XCTAssertEqual(viewModel.imageIntent?.qualityPreference, .balanced)
        XCTAssertEqual(viewModel.imageIntent?.stripMetadata, true)
    }

    func testUnsupportedFileEntersTypeAwareReadOnlyActions() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/document.pdf"),
            type: .pdf,
            fileSize: 42,
            displayName: "document.pdf"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)

        XCTAssertFalse(viewModel.canConfigureImageConversion(for: [file]))
        viewModel.continueToImageActions()

        XCTAssertEqual(viewModel.state, .actionSelection([file]))
        XCTAssertEqual(viewModel.conversionCapability, .unsupported(kind: .other))
        XCTAssertNil(viewModel.imageIntent)
    }

    func testMOVDropOffersVideoActionsWithoutImageIntent() async {
        let file = makeMOVInput()
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)

        viewModel.continueToActions()

        XCTAssertEqual(viewModel.state, .actionSelection([file]))
        XCTAssertEqual(
            viewModel.conversionCapability,
            .video(availableResolutions: [.source, .p1080, .p720])
        )
        XCTAssertNil(viewModel.imageIntent)
        XCTAssertEqual(viewModel.videoIntent?.compatibility, .highCompatibility)
        XCTAssertEqual(viewModel.videoIntent?.maxResolution, .source)
        XCTAssertNil(viewModel.videoIntent?.targetBytes)
    }

    func testVideoResolutionSelectionFlowsIntoConversionPlan() async {
        let file = makeMOVInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let engine = StubConversionEngine(outputs: [outputDirectory.appendingPathComponent("clip.mp4")])
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()

        viewModel.selectVideoResolution(.p720)
        viewModel.startConversion()
        for _ in 0..<50 where await engine.lastPlan == nil {
            await Task.yield()
        }

        let plan = await engine.lastPlan
        guard case let .video(intent) = plan?.steps.first else {
            return XCTFail("Expected a video conversion plan")
        }
        XCTAssertEqual(intent.maxResolution, .p720)
        XCTAssertEqual(intent.compatibility, .highCompatibility)
        XCTAssertNil(intent.targetBytes)
    }

    func testVideoTargetSelectionFlowsIntoConversionPlan() async {
        let file = makeMOVInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let engine = StubConversionEngine(outputs: [outputDirectory.appendingPathComponent("clip.mp4")])
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()

        viewModel.selectVideoTargetBytes(50_000_000)
        viewModel.startConversion()
        for _ in 0..<50 where await engine.lastPlan == nil {
            await Task.yield()
        }

        let plan = await engine.lastPlan
        guard case let .video(intent) = plan?.steps.first else {
            return XCTFail("Expected a video conversion plan")
        }
        XCTAssertEqual(intent.targetBytes, 50_000_000)
        XCTAssertEqual(plan?.estimatedOutput?.totalBytes, 50_000_000)
    }

    func testCustomVideoTargetUsesFiveMegabyteClampedSteps() async {
        let file = makeMOVInput()
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()

        XCTAssertEqual(viewModel.customVideoTargetMegabytes, 25)
        XCTAssertFalse(viewModel.isUsingCustomVideoTarget)

        viewModel.selectCustomVideoTarget()
        viewModel.adjustCustomVideoTargetMegabytes(by: 5)

        XCTAssertTrue(viewModel.isUsingCustomVideoTarget)
        XCTAssertEqual(viewModel.customVideoTargetMegabytes, 30)
        XCTAssertEqual(viewModel.videoIntent?.targetBytes, 30_000_000)

        viewModel.adjustCustomVideoTargetMegabytes(by: -10_000)
        XCTAssertEqual(viewModel.customVideoTargetMegabytes, 5)
        XCTAssertEqual(viewModel.videoIntent?.targetBytes, 5_000_000)
    }

    func testStartConversionUsesSelectedDirectoryAndShowsSuccess() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.png"),
            type: .png,
            fileSize: 42,
            displayName: "photo.png"
        )
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let outputURL = outputDirectory.appendingPathComponent("photo.jpg")
        let engine = StubConversionEngine(outputs: [outputURL])
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()

        viewModel.startConversion()
        for _ in 0..<50 {
            if case .success = viewModel.state { break }
            await Task.yield()
        }

        guard case let .success(summary) = viewModel.state else {
            return XCTFail("Expected completed conversion")
        }
        XCTAssertEqual(summary.outputURLs, [outputURL])
        XCTAssertEqual(summary.inputBytes, 42)
        let plan = await engine.lastPlan
        guard case let .chosenDirectory(directory, _) = plan?.outputPolicy else {
            return XCTFail("Expected chosen output directory")
        }
        XCTAssertEqual(directory, outputDirectory)
    }

    func testTargetSelectionFlowsIntoConversionPlan() async {
        let file = makePNGInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let engine = StubConversionEngine(outputs: [outputDirectory.appendingPathComponent("photo.jpg")])
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()

        viewModel.selectTargetBytes(500_000)
        viewModel.selectTargetBytes(-1)
        XCTAssertEqual(viewModel.imageIntent?.targetBytes, 500_000)

        viewModel.startConversion()
        for _ in 0..<50 where await engine.lastPlan == nil {
            await Task.yield()
        }

        let capturedPlan = await engine.lastPlan
        guard case let .image(intent) = capturedPlan?.steps.first else {
            return XCTFail("Expected an image conversion plan")
        }
        XCTAssertEqual(intent.targetBytes, 500_000)
        XCTAssertEqual(capturedPlan?.estimatedOutput?.totalBytes, 500_000)
    }

    func testCancelledOutputSelectionKeepsActionSettings() async {
        let file = makePNGInput()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: StubConversionEngine(outputs: []),
            outputDirectorySelector: StubOutputDirectorySelector(url: nil)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()

        viewModel.startConversion()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(viewModel.state, .actionSelection([file]))
    }

    func testStartShowsThatOutputFolderSelectionIsInProgress() async {
        let file = makePNGInput()
        let selector = SuspendedOutputDirectorySelector()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: StubConversionEngine(outputs: []),
            outputDirectorySelector: selector
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()

        viewModel.startConversion()
        for _ in 0..<20 where !viewModel.isChoosingOutputFolder {
            await Task.yield()
        }

        XCTAssertTrue(viewModel.isChoosingOutputFolder)
        for _ in 0..<20 where !selector.isWaiting {
            await Task.yield()
        }
        selector.finish(with: nil)
        for _ in 0..<20 where viewModel.isChoosingOutputFolder {
            await Task.yield()
        }
        XCTAssertFalse(viewModel.isChoosingOutputFolder)
        XCTAssertEqual(viewModel.state, .actionSelection([file]))
    }

    func testInvalidSavedOutputFolderPromptsForReplacement() async {
        let file = makePNGInput()
        let invalidDirectory = URL(
            fileURLWithPath: "/tmp/file-island-missing-\(UUID().uuidString)",
            isDirectory: true
        )
        let replacementDirectory = FileManager.default.temporaryDirectory
        let defaults = UserDefaults(suiteName: "IslandViewModelTests-\(UUID().uuidString)")!
        defaults.set(Data([0x01]), forKey: "outputFolder.securityScopedBookmark")
        let store = OutputFolderBookmarkStore(
            defaults: defaults,
            coder: FixedBookmarkCoder(resolvedURL: invalidDirectory)
        )
        let selector = RecordingOutputDirectorySelector(url: replacementDirectory)
        let engine = StubConversionEngine(outputs: [replacementDirectory.appendingPathComponent("photo.jpg")])
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: selector,
            outputFolderStore: store
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()

        viewModel.startConversion()
        for _ in 0..<50 {
            if case .success = viewModel.state { break }
            await Task.yield()
        }

        XCTAssertEqual(selector.selectionCount, 1)
        guard case let .chosenDirectory(directory, _) = await engine.lastPlan?.outputPolicy else {
            return XCTFail("Expected a plan using the replacement output folder")
        }
        XCTAssertEqual(directory, replacementDirectory)
        XCTAssertEqual(store.displayURL, replacementDirectory)
    }

    func testEngineErrorBecomesUserFacingFailure() async {
        let file = makePNGInput()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: FailingConversionEngine(error: .invalidMedia),
            outputDirectorySelector: StubOutputDirectorySelector(
                url: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
            )
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()

        viewModel.startConversion()
        for _ in 0..<50 {
            if case .failure = viewModel.state { break }
            await Task.yield()
        }

        guard case let .failure(error) = viewModel.state else {
            return XCTFail("Expected structured failure")
        }
        XCTAssertEqual(error.title, "This file couldn’t be decoded")
    }

    func testUnreachableTargetExplainsThatTheSelectedSizeIsTooSmall() async {
        let file = makePNGInput()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: FailingConversionEngine(error: .targetSizeUnreachable),
            outputDirectorySelector: StubOutputDirectorySelector(
                url: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
            )
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()
        viewModel.selectTargetBytes(500_000)

        viewModel.startConversion()
        for _ in 0..<50 {
            if case .failure = viewModel.state { break }
            await Task.yield()
        }

        guard case let .failure(error) = viewModel.state else {
            return XCTFail("Expected a structured target-size failure")
        }
        XCTAssertEqual(error.title, "Couldn’t reach this size")
        XCTAssertEqual(error.message, "The selected limit is too small for a usable media file.")
    }

    func testCancelReturnsToActionsAndForwardsPlanID() async {
        let file = makePNGInput()
        let engine = SuspendedConversionEngine()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(
                url: URL(fileURLWithPath: "/tmp/output", isDirectory: true)
            )
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()
        viewModel.startConversion()
        for _ in 0..<50 {
            if case .converting = viewModel.state { break }
            await Task.yield()
        }

        viewModel.cancelConversion()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(viewModel.state, .actionSelection([file]))
        let cancelledJobID = await engine.cancelledJobID
        XCTAssertNotNil(cancelledJobID)
    }

    private func makePNGInput() -> InputFile {
        InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.png"),
            type: .png,
            fileSize: 42,
            displayName: "photo.png"
        )
    }

    private func makeMOVInput() -> InputFile {
        InputFile(
            url: URL(fileURLWithPath: "/tmp/clip.mov"),
            type: .quickTimeMovie,
            fileSize: 84,
            displayName: "clip.mov"
        )
    }

    private func waitForInspection(in viewModel: IslandViewModel) async {
        for _ in 0..<20 where viewModel.state == .inspecting {
            await Task.yield()
        }
    }
}

private struct StubFileInspector: FileInspecting {
    let files: [InputFile]

    func inspect(urls: [URL]) async throws -> [InputFile] {
        files
    }
}

@MainActor
private struct StubOutputDirectorySelector: OutputDirectorySelecting {
    let url: URL?

    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection? {
        url.map { OutputDirectorySelection(url: $0, didStartAccessingSecurityScope: false) }
    }
}

@MainActor
private final class RecordingOutputDirectorySelector: OutputDirectorySelecting {
    let url: URL?
    private(set) var selectionCount = 0

    init(url: URL?) {
        self.url = url
    }

    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection? {
        selectionCount += 1
        return url.map { OutputDirectorySelection(url: $0, didStartAccessingSecurityScope: false) }
    }
}

@MainActor
private final class SuspendedOutputDirectorySelector: OutputDirectorySelecting {
    private var continuation: CheckedContinuation<OutputDirectorySelection?, Never>?
    private(set) var isWaiting = false

    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            isWaiting = true
        }
    }

    func finish(with selection: OutputDirectorySelection?) {
        continuation?.resume(returning: selection)
        continuation = nil
        isWaiting = false
    }
}

private struct FixedBookmarkCoder: SecurityScopedBookmarkCoding {
    let resolvedURL: URL

    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(url: resolvedURL, isStale: false)
    }
}

private actor StubConversionEngine: ConversionEngine {
    let outputs: [URL]
    private(set) var lastPlan: ConversionPlan?

    init(outputs: [URL]) {
        self.outputs = outputs
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool {
        true
    }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        lastPlan = plan
        progress(0)
        progress(1)
        return outputs
    }

    func cancel(jobID: UUID) async {}
}

private struct FailingConversionEngine: ConversionEngine {
    let error: ConversionError

    func canHandle(_ plan: ConversionPlan) -> Bool { true }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        throw error
    }

    func cancel(jobID: UUID) async {}
}

private actor SuspendedConversionEngine: ConversionEngine {
    private(set) var cancelledJobID: UUID?

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool { true }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        progress(0.25)
        while !Task.isCancelled, cancelledJobID == nil {
            await Task.yield()
        }
        throw ConversionError.cancelled
    }

    func cancel(jobID: UUID) async {
        cancelledJobID = jobID
    }
}
