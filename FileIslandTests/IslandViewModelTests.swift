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

    func testUnsupportedFileCannotEnterImageActions() async {
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

        guard case .failure = viewModel.state else {
            return XCTFail("Expected a scoped unsupported-conversion error")
        }
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
        XCTAssertEqual(error.title, "This image couldn’t be decoded")
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
        progress: @Sendable (Double) -> Void
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
        progress: @Sendable (Double) -> Void
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
        progress: @Sendable (Double) -> Void
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
