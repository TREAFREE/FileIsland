import AppKit
import Foundation
import UniformTypeIdentifiers
import XCTest

@testable import FileIsland

@MainActor
final class IslandViewModelTests: XCTestCase {
    func testUnsupportedBatchSectionDoesNotDemandAWindowLargerThanActionLayout() async throws {
        let scan = try makeMixedFolderScan()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan)
        )
        viewModel.receiveDrop(urls: scan.selections.map(\.url))
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        let preferred = IslandLayout.preferredSize(for: .expandedActions)
        let localization = LocalizationController(
            preferences: AppPreferences(
                defaults: UserDefaults(suiteName: "IslandViewModelTests.Localization")!
            )
        )
        let imageContainer = IslandDropContainerView(
            viewModel: viewModel,
            localization: localization
        )
        imageContainer.frame = CGRect(origin: .zero, size: preferred)
        imageContainer.layoutSubtreeIfNeeded()
        let imageFittingSize = imageContainer.fittingSize

        viewModel.selectBatchSection(.unsupported)
        let unsupportedContainer = IslandDropContainerView(
            viewModel: viewModel,
            localization: localization
        )
        unsupportedContainer.frame = CGRect(origin: .zero, size: preferred)
        unsupportedContainer.layoutSubtreeIfNeeded()
        let unsupportedFittingSize = unsupportedContainer.fittingSize

        XCTAssertLessThanOrEqual(
            unsupportedFittingSize.width,
            preferred.width,
            "image=\(imageFittingSize), unsupported=\(unsupportedFittingSize)"
        )
        XCTAssertLessThanOrEqual(unsupportedFittingSize.height, preferred.height)
    }

    func testBackFromUnsupportedBatchReturnsToPreviousGroupWithoutLosingConfiguration() async throws {
        let scan = try makeMixedFolderScan()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan)
        )
        viewModel.receiveDrop(urls: scan.selections.map(\.url))
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        let originalImageIntent = viewModel.imageIntent

        viewModel.selectBatchSection(.video)
        viewModel.selectVideoResolution(.p720)
        viewModel.selectBatchSection(.unsupported)
        viewModel.returnFromUnsupportedSection()

        XCTAssertEqual(viewModel.selectedBatchSection, .video)
        XCTAssertEqual(viewModel.state, .actionSelection(scan.files))
        XCTAssertEqual(viewModel.imageIntent, originalImageIntent)
        XCTAssertEqual(viewModel.videoIntent?.maxResolution, .p720)
    }

    func testFolderBatchKeepsIndependentImageAndVideoConfiguration() async throws {
        let scan = try makeMixedFolderScan()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan)
        )

        viewModel.receiveDrop(urls: scan.selections.map(\.url))
        await waitForInspection(in: viewModel)
        XCTAssertEqual(viewModel.state, .droppedSummary(scan.files))

        viewModel.continueToActions()

        XCTAssertTrue(viewModel.isBatchWorkflow)
        XCTAssertEqual(viewModel.batchImageCount, 1)
        XCTAssertEqual(viewModel.batchVideoCount, 1)
        XCTAssertEqual(viewModel.batchUnsupportedCount, 1)
        XCTAssertNotNil(viewModel.imageIntent)
        XCTAssertNotNil(viewModel.videoIntent)
        XCTAssertEqual(viewModel.selectedBatchSection, .image)
        let originalImageIntent = viewModel.imageIntent

        viewModel.selectBatchSection(.video)
        viewModel.selectVideoResolution(.p720)

        XCTAssertEqual(viewModel.selectedBatchSection, .video)
        XCTAssertEqual(viewModel.videoIntent?.maxResolution, .p720)
        XCTAssertEqual(viewModel.imageIntent, originalImageIntent)
        XCTAssertEqual(viewModel.batchProcessCount, 2)
        XCTAssertEqual(viewModel.batchSkippedCount, 0)
        XCTAssertEqual(viewModel.batchFailClosedCount, 1)
    }

    func testFolderBatchUsesOneStartAndOneCoordinatorRequest() async throws {
        let scan = try makeMixedFolderScan()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let coordinator = RecordingBatchCoordinator()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            batchCoordinator: coordinator,
            outputDirectorySelector: StubOutputDirectorySelector(url: output)
        )
        viewModel.receiveDrop(urls: scan.selections.map(\.url))
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()

        viewModel.startConversion()
        for _ in 0..<100 {
            if case .success = viewModel.state { break }
            await Task.yield()
        }

        let requests = await coordinator.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.processCount, 2)
        XCTAssertEqual(requests.first?.failClosedCount, 1)
        if case .success = viewModel.state {
            // Expected.
        } else {
            XCTFail("Expected one batch conversion to complete")
        }
    }

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

    func testJPEGDropOffersJPEGAndPNGActionDefaults() async {
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
        XCTAssertEqual(viewModel.availableOutputFormats, [.jpeg, .png])
        XCTAssertEqual(viewModel.imageIntent?.outputFormat, .jpeg)
        XCTAssertEqual(viewModel.imageIntent?.qualityPreference, .balanced)
        XCTAssertEqual(viewModel.imageIntent?.stripMetadata, true)
    }

    func testAppliesImagePresetLoadedThroughInjectedCatalog() async throws {
        let file = makePNGInput()
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            presetCatalogLoader: StaticPresetCatalogLoader(presets: presets)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        await waitForPresets(in: viewModel)

        XCTAssertEqual(viewModel.availablePresetRecommendations.map(\.preset.id), ["image-for-web"])
        viewModel.applyPreset(id: "image-for-web")

        XCTAssertEqual(viewModel.selectedPresetID, "image-for-web")
        XCTAssertEqual(viewModel.selectedPresetDisplayName, "Image for Web")
        XCTAssertEqual(
            viewModel.imageIntent,
            ImageIntent(
                outputFormat: .jpeg,
                maxPixelDimension: 2_048,
                targetBytes: nil,
                qualityPreference: .balanced,
                stripMetadata: true
            )
        )
    }

    func testManualImageAndVideoEditsClearPresetSelection() async throws {
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()

        let imageViewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [makePNGInput()]),
            presetCatalogLoader: StaticPresetCatalogLoader(presets: presets)
        )
        imageViewModel.receiveDrop(urls: [makePNGInput().url])
        await waitForInspection(in: imageViewModel)
        imageViewModel.continueToActions()
        await waitForPresets(in: imageViewModel)
        imageViewModel.applyPreset(id: "image-for-web")
        imageViewModel.selectMaximumDimension(1_280)
        XCTAssertNil(imageViewModel.selectedPresetID)

        let video = makeMOVInput()
        let videoViewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [video]),
            presetCatalogLoader: StaticPresetCatalogLoader(presets: presets)
        )
        videoViewModel.receiveDrop(urls: [video.url])
        await waitForInspection(in: videoViewModel)
        videoViewModel.continueToActions()
        await waitForPresets(in: videoViewModel)
        videoViewModel.applyPreset(id: "web-friendly-video")
        videoViewModel.selectVideoResolution(.p720)
        XCTAssertNil(videoViewModel.selectedPresetID)
    }

    func testAppliedPresetFlowsIntoConversionPlan() async throws {
        let file = makePNGInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let engine = StubConversionEngine(
            outputs: [outputDirectory.appendingPathComponent("photo.jpg")]
        )
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory),
            presetCatalogLoader: StaticPresetCatalogLoader(presets: presets)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        await waitForPresets(in: viewModel)
        viewModel.applyPreset(id: "image-for-web")

        viewModel.startConversion()
        for _ in 0..<50 where await engine.lastPlan == nil {
            await Task.yield()
        }

        guard case .image(let intent) = await engine.lastPlan?.steps.first else {
            return XCTFail("Expected image plan")
        }
        XCTAssertEqual(intent.outputFormat, .jpeg)
        XCTAssertEqual(intent.maxPixelDimension, 2_048)
        XCTAssertEqual(intent.qualityPreference, .balanced)
        XCTAssertTrue(intent.stripMetadata)
    }

    func testUnder100MBPresetFlowsIntoNativeVideoPlan() async throws {
        let file = makeMOVInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let engine = StubConversionEngine(
            outputs: [outputDirectory.appendingPathComponent("clip.mp4")]
        )
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: engine,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory),
            presetCatalogLoader: StaticPresetCatalogLoader(presets: presets)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        await waitForPresets(in: viewModel)
        viewModel.applyPreset(id: "under-100mb-video")

        viewModel.startConversion()
        for _ in 0..<50 where await engine.lastPlan == nil {
            await Task.yield()
        }

        let plan = await engine.lastPlan
        guard case .video(let intent) = plan?.steps.first else {
            return XCTFail("Expected video plan")
        }
        XCTAssertEqual(intent.compatibility, .highCompatibility)
        XCTAssertEqual(intent.maxResolution, .source)
        XCTAssertEqual(intent.targetBytes, 100_000_000)
        XCTAssertEqual(plan?.estimatedOutput?.totalBytes, 100_000_000)
    }

    func testPresetLoadFailurePreservesManualConversionControls() async {
        let file = makePNGInput()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            presetCatalogLoader: FailingPresetCatalogLoader()
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(viewModel.availablePresetRecommendations.isEmpty)
        XCTAssertEqual(viewModel.imageIntent?.outputFormat, .jpeg)
        XCTAssertEqual(viewModel.state, .actionSelection([file]))
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
            .video(
                availableResolutions: [.source, .p1080, .p720],
                supportsTargetSize: true
            )
        )
        XCTAssertNil(viewModel.imageIntent)
        XCTAssertEqual(viewModel.videoIntent?.compatibility, .highCompatibility)
        XCTAssertEqual(viewModel.videoIntent?.maxResolution, .source)
        XCTAssertNil(viewModel.videoIntent?.targetBytes)
    }

    func testWebMDropUsesFallbackOptionsAndRejectsTargetSizeSelection() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/clip.webm"),
            type: UTType(filenameExtension: "webm")!,
            fileSize: 84,
            displayName: "clip.webm"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)

        viewModel.continueToActions()
        viewModel.selectVideoTargetBytes(50_000_000)
        viewModel.selectCustomVideoTarget()
        viewModel.adjustCustomVideoTargetMegabytes(by: 5)

        XCTAssertEqual(
            viewModel.conversionCapability,
            .video(
                availableResolutions: [.source, .p1080, .p720],
                supportsTargetSize: false
            )
        )
        XCTAssertFalse(viewModel.supportsVideoTargetSize)
        XCTAssertFalse(viewModel.isUsingCustomVideoTarget)
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
        guard case .video(let intent) = plan?.steps.first else {
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
        guard case .video(let intent) = plan?.steps.first else {
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

        guard case .success(let summary) = viewModel.state else {
            return XCTFail("Expected completed conversion")
        }
        XCTAssertEqual(summary.outputURLs, [outputURL])
        XCTAssertEqual(summary.inputBytes, 42)
        let plan = await engine.lastPlan
        guard case .chosenDirectory(let directory, _) = plan?.outputPolicy else {
            return XCTFail("Expected chosen output directory")
        }
        XCTAssertEqual(directory, outputDirectory)
    }

    func testSuccessAutomaticallyCollapsesWhenPointerIsOutside() async throws {
        let viewModel = makeSuccessfulViewModel(successDisplayDuration: .milliseconds(20))
        await startSuccessfulConversion(in: viewModel)
        guard case .success = viewModel.state else {
            return XCTFail("Expected success before automatic collapse")
        }

        try await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(viewModel.state, .idle)
    }

    func testSuccessWaitsForHoverToExitBeforeCollapsing() async throws {
        let viewModel = makeSuccessfulViewModel(successDisplayDuration: .milliseconds(20))
        viewModel.setPointerInside(true)
        await startSuccessfulConversion(in: viewModel)
        try await Task.sleep(for: .milliseconds(60))

        guard case .success = viewModel.state else {
            return XCTFail("Success must remain visible while hovered")
        }

        viewModel.setPointerInside(false)
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testSuccessWaitsForKeyboardInteractionToEndBeforeCollapsing() async throws {
        let viewModel = makeSuccessfulViewModel(successDisplayDuration: .milliseconds(20))
        viewModel.setKeyboardInteractionActive(true)
        await startSuccessfulConversion(in: viewModel)
        try await Task.sleep(for: .milliseconds(60))

        guard case .success = viewModel.state else {
            return XCTFail("Success must remain visible while keyboard interaction is active")
        }

        viewModel.setKeyboardInteractionActive(false)
        XCTAssertEqual(viewModel.state, .idle)
    }

    func testTargetSelectionFlowsIntoConversionPlan() async {
        let file = makePNGInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let engine = StubConversionEngine(outputs: [outputDirectory.appendingPathComponent("photo.jpg")]
        )
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
        guard case .image(let intent) = capturedPlan?.steps.first else {
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
        XCTAssertFalse(viewModel.acceptsFileDrops)
        for _ in 0..<20 where !selector.isWaiting {
            await Task.yield()
        }
        selector.finish(with: nil)
        for _ in 0..<20 where viewModel.isChoosingOutputFolder {
            await Task.yield()
        }
        XCTAssertFalse(viewModel.isChoosingOutputFolder)
        XCTAssertTrue(viewModel.acceptsFileDrops)
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
        let engine = StubConversionEngine(outputs: [
            replacementDirectory.appendingPathComponent("photo.jpg")
        ])
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
        guard case .chosenDirectory(let directory, _) = await engine.lastPlan?.outputPolicy else {
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

        guard case .failure(let error) = viewModel.state else {
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

        guard case .failure(let error) = viewModel.state else {
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

    func testVideoSplitCustomPlanEnablesStartOnlyAfterCurrentProbeCompletes() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let probe = StaticVideoSplitProbe(facts: makeSplitFacts(for: file))
        let coordinator = RecordingVideoSplitCoordinator()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: probe,
            videoSplitCoordinator: coordinator,
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero
        )

        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)

        XCTAssertFalse(viewModel.canStartVideoSplit)
        await waitForVideoSplitPlanning(in: viewModel)

        XCTAssertEqual(viewModel.videoSplitPlanningState, .ready)
        XCTAssertTrue(viewModel.canStartVideoSplit)
        XCTAssertEqual(viewModel.videoSplitPlanPreview?.segmentCount, 1)
        XCTAssertTrue(viewModel.videoSplitPlanPreview?.noSplitNeeded == true)
        XCTAssertEqual(viewModel.videoSplitMaximumMegabytesText, "100")
    }

    func testVideoSplitUnitsAndSlidersKeepCanonicalConstraintsStable() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: StaticVideoSplitProbe(facts: makeSplitFacts(for: file)),
            videoSplitCoordinator: RecordingVideoSplitCoordinator(),
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero
        )

        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        await waitForVideoSplitPlanning(in: viewModel)

        viewModel.updateVideoSplitMaximumMegabytes("500")
        viewModel.selectVideoSplitSizeUnit(.gigabytes)
        viewModel.updateVideoSplitMaximumDurationSeconds("120")
        viewModel.selectVideoSplitDurationUnit(.minutes)
        await waitForVideoSplitPlanning(in: viewModel)

        XCTAssertEqual(viewModel.videoSplitMaximumMegabytesText, "0.5")
        XCTAssertEqual(viewModel.videoSplitMaximumDurationSecondsText, "2")
        XCTAssertEqual(viewModel.videoSplitSizeUnit, .gigabytes)
        XCTAssertEqual(viewModel.videoSplitDurationUnit, .minutes)
        XCTAssertEqual(viewModel.videoSplitPlanPreview?.maxBytes, 500_000_000)
        XCTAssertEqual(viewModel.videoSplitPlanPreview?.maxDurationMilliseconds, 120_000)

        let sliderPosition = 0.64
        let expectedSeconds = VideoSplitLimitSliderScale.canonicalSeconds(
            at: sliderPosition
        )
        viewModel.updateVideoSplitDurationSliderPosition(sliderPosition)
        await waitForVideoSplitPlanning(in: viewModel)

        XCTAssertEqual(
            VideoSplitLimitDisplayFormatter.canonicalText(
                viewModel.videoSplitMaximumDurationSecondsText,
                unit: viewModel.videoSplitDurationUnit
            ),
            NSDecimalNumber(decimal: expectedSeconds).stringValue
        )
        XCTAssertEqual(
            viewModel.videoSplitPlanPreview?.maxDurationMilliseconds,
            NSDecimalNumber(decimal: expectedSeconds * 1_000).int64Value
        )
    }

    func testVideoSplitInvalidCustomLimitsInvalidatePreviousPlan() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: StaticVideoSplitProbe(facts: makeSplitFacts(for: file)),
            videoSplitCoordinator: RecordingVideoSplitCoordinator(),
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        await waitForVideoSplitPlanning(in: viewModel)
        XCTAssertTrue(viewModel.canStartVideoSplit)

        viewModel.updateVideoSplitMaximumMegabytes("")

        XCTAssertEqual(
            viewModel.videoSplitPlanningState,
            .blocked(.enterAtLeastOneLimit)
        )
        XCTAssertNil(viewModel.videoSplitPlanPreview)
        XCTAssertFalse(viewModel.canStartVideoSplit)

        viewModel.updateVideoSplitMaximumMegabytes("-2")
        XCTAssertEqual(
            viewModel.videoSplitPlanningState,
            .blocked(.invalidMaximumMegabytes)
        )
    }

    func testVideoSplitExecutionUsesMonotonicProgressAndReportsSegments() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let outputs = (1...3).map { index in
            outputDirectory.appendingPathComponent("clip-part-0\(index).mov")
        }
        let coordinator = RecordingVideoSplitCoordinator(
            outputURLs: outputs,
            segmentCount: 3,
            totalBytes: 72
        )
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: StaticVideoSplitProbe(facts: makeSplitFacts(for: file)),
            videoSplitCoordinator: coordinator,
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        var observedFractions: [Double] = []
        viewModel.onStateChange = { state in
            if case .converting(let snapshot) = state {
                observedFractions.append(snapshot.progress)
            }
        }
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        await waitForVideoSplitPlanning(in: viewModel)

        viewModel.startVideoSplit()
        for _ in 0..<200 {
            if case .success = viewModel.state { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        guard case .success(let summary) = viewModel.state else {
            return XCTFail("Expected split success")
        }
        XCTAssertEqual(summary.outputURLs, outputs)
        XCTAssertEqual(summary.outputBytes, 72)
        XCTAssertEqual(viewModel.lastVideoSplitResult?.segmentCount, 3)
        XCTAssertEqual(viewModel.lastVideoSplitResult?.totalBytes, 72)
        XCTAssertEqual(observedFractions, observedFractions.sorted())
        XCTAssertTrue(observedFractions.contains(0.6))
        XCTAssertFalse(observedFractions.contains(0.4))
        let requestCount = await coordinator.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testVideoSplitLatePlanningCompletionCannotReplaceNewerConstraints() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let probe = DelayedFirstVideoSplitProbe(facts: makeSplitFacts(for: file))
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: probe,
            videoSplitCoordinator: RecordingVideoSplitCoordinator(),
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        for _ in 0..<100 where await probe.callCount == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }

        viewModel.updateVideoSplitMaximumMegabytes("50.5")
        await waitForVideoSplitPlanning(in: viewModel)
        XCTAssertEqual(viewModel.videoSplitPlanPreview?.maxBytes, 50_500_000)

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(viewModel.videoSplitPlanningState, .ready)
        XCTAssertEqual(viewModel.videoSplitPlanPreview?.maxBytes, 50_500_000)
        XCTAssertTrue(viewModel.canStartVideoSplit)
    }

    func testVideoSplitFlowStaysInsideExpandedActionsLayout() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: StaticVideoSplitProbe(facts: makeSplitFacts(for: file)),
            videoSplitCoordinator: RecordingVideoSplitCoordinator(),
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        await waitForVideoSplitPlanning(in: viewModel)

        let preferred = IslandLayout.preferredSize(for: .expandedActions)
        let localization = LocalizationController(
            preferences: AppPreferences(
                defaults: UserDefaults(
                    suiteName: "IslandViewModelTests.SplitLayout-\(UUID().uuidString)"
                )!
            )
        )
        localization.language = .simplifiedChinese
        let container = IslandDropContainerView(
            viewModel: viewModel,
            localization: localization
        )
        container.frame = CGRect(origin: .zero, size: preferred)
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(viewModel.state.layoutMode, .expandedActions)
        XCTAssertLessThanOrEqual(container.fittingSize.width, preferred.width)
        XCTAssertLessThanOrEqual(container.fittingSize.height, preferred.height)
    }

    func testCancellingVideoSplitReturnsToCurrentActionsAndForwardsRequestID() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let coordinator = SuspendedVideoSplitCoordinator()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: StaticVideoSplitProbe(facts: makeSplitFacts(for: file)),
            videoSplitCoordinator: coordinator,
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        await waitForVideoSplitPlanning(in: viewModel)
        viewModel.startVideoSplit()
        for _ in 0..<100 {
            if case .converting = viewModel.state { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let requestID = await coordinator.requestID
        XCTAssertNotNil(requestID)

        viewModel.cancelConversion()
        for _ in 0..<100 where await coordinator.cancelledRequestID == nil {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state, .actionSelection(scan.files))
        let cancelledRequestID = await coordinator.cancelledRequestID
        XCTAssertEqual(cancelledRequestID, requestID)
        XCTAssertTrue(viewModel.canStartVideoSplit)
    }

    func testLateCancelledSplitCannotClearImmediatelyRestartedSplit() async throws {
        let file = makeMOVInput()
        let scan = try makeVideoScan(file)
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let coordinator = RestartableVideoSplitCoordinator()
        let viewModel = IslandViewModel(
            fileInspector: StubFileInspector(files: []),
            inputScanner: StubInputScanner(result: scan),
            videoSplitProbe: StaticVideoSplitProbe(facts: makeSplitFacts(for: file)),
            videoSplitCoordinator: coordinator,
            videoSplitRuntimeAvailable: true,
            videoSplitPlanningDebounce: .zero,
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory)
        )
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToActions()
        viewModel.selectVideoOperation(.splitForSharing)
        await waitForVideoSplitPlanning(in: viewModel)

        viewModel.startVideoSplit()
        for _ in 0..<100 where await coordinator.requestIDs.count < 1 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let initialRequestIDs = await coordinator.requestIDs
        let firstRequestID = try XCTUnwrap(initialRequestIDs.first)
        viewModel.cancelConversion()
        for _ in 0..<100 where !(await coordinator.cancelledRequestIDs).contains(firstRequestID) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTAssertTrue(viewModel.canStartVideoSplit)

        viewModel.startVideoSplit()
        for _ in 0..<100 where await coordinator.requestIDs.count < 2 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let requestIDs = await coordinator.requestIDs
        XCTAssertEqual(requestIDs.count, 2)
        let secondRequestID = requestIDs[1]
        if case .converting = viewModel.state {
            // Expected while the restarted request is active.
        } else {
            XCTFail("Expected the restarted split to be converting")
        }

        await coordinator.releaseFirstCancellation()
        for _ in 0..<20 { await Task.yield() }
        if case .converting = viewModel.state {
            // The stale catch from request A must not overwrite request B.
        } else {
            XCTFail("A stale cancelled request replaced the restarted split state")
        }

        viewModel.cancelConversion()
        for _ in 0..<100 where !(await coordinator.cancelledRequestIDs).contains(secondRequestID) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let finalCancelledRequestIDs = await coordinator.cancelledRequestIDs
        XCTAssertTrue(finalCancelledRequestIDs.contains(secondRequestID))
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

    private func makeVideoScan(_ file: InputFile) throws -> InputScanResult {
        InputScanResult(
            selections: [.file(file.url)],
            inputs: [
                BatchInput(
                    file: file,
                    selection: .file(file.url),
                    relativePath: try SafeRelativePath(file.url.lastPathComponent)
                )
            ]
        )
    }

    private func makeSplitFacts(for file: InputFile) -> VideoSplitSourceFacts {
        VideoSplitSourceFacts(
            inputID: file.id,
            sourceURL: file.url,
            fileIdentity: makeVideoSplitTestIdentity(byteCount: file.fileSize),
            durationMilliseconds: 10_000,
            displayWidth: 1_920,
            displayHeight: 1_080,
            averageBitrateBitsPerSecond: 1_000_000,
            container: "quicktime",
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

    private func makeSuccessfulViewModel(
        successDisplayDuration: Duration
    ) -> IslandViewModel {
        let file = makePNGInput()
        let outputDirectory = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        return IslandViewModel(
            fileInspector: StubFileInspector(files: [file]),
            conversionEngine: StubConversionEngine(
                outputs: [outputDirectory.appendingPathComponent("photo.jpg")]
            ),
            outputDirectorySelector: StubOutputDirectorySelector(url: outputDirectory),
            successDisplayDuration: successDisplayDuration
        )
    }

    private func startSuccessfulConversion(in viewModel: IslandViewModel) async {
        let file = makePNGInput()
        viewModel.receiveDrop(urls: [file.url])
        await waitForInspection(in: viewModel)
        viewModel.continueToImageActions()
        viewModel.startConversion()
        for _ in 0..<50 {
            if case .success = viewModel.state { break }
            await Task.yield()
        }
    }

    private func makeMixedFolderScan() throws -> InputScanResult {
        let root = URL(fileURLWithPath: "/tmp/drop", isDirectory: true)
        let selection = InputSelection.folder(root)
        let fixtures: [(String, UTType)] = [
            ("photos/photo.jpg", .jpeg),
            ("videos/clip.mov", .quickTimeMovie),
            ("notes/readme.txt", .plainText),
        ]
        return InputScanResult(
            selections: [selection],
            inputs: try fixtures.map { path, type in
                let url = root.appendingPathComponent(path)
                return BatchInput(
                    file: InputFile(
                        url: url,
                        type: type,
                        fileSize: 42,
                        displayName: url.lastPathComponent
                    ),
                    selection: selection,
                    relativePath: try SafeRelativePath(path)
                )
            }
        )
    }

    private func waitForInspection(in viewModel: IslandViewModel) async {
        for _ in 0..<200 {
            guard viewModel.state == .inspecting else { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Inspection did not finish within one second")
    }

    private func waitForPresets(in viewModel: IslandViewModel) async {
        for _ in 0..<50 where viewModel.availablePresetRecommendations.isEmpty {
            await Task.yield()
        }
    }

    private func waitForVideoSplitPlanning(in viewModel: IslandViewModel) async {
        for _ in 0..<200 {
            if viewModel.videoSplitPlanningState != .planning { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Video split planning did not finish within one second")
    }
}

private struct StubFileInspector: FileInspecting {
    let files: [InputFile]

    func inspect(urls: [URL]) async throws -> [InputFile] {
        files
    }
}

private struct StubInputScanner: InputScanning {
    let result: InputScanResult

    func scan(urls: [URL]) async throws -> InputScanResult { result }
}

private actor RecordingBatchCoordinator: BatchJobCoordinating {
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
                currentDisplayName: request.executableGroups.last?.plan?.inputs.last?.displayName
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

private struct StaticVideoSplitProbe: VideoSplitProbing {
    let facts: VideoSplitSourceFacts

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        guard input.id == facts.inputID else {
            throw VideoSplitProbeError.inputIdentityMismatch
        }
        return facts
    }
}

private actor DelayedFirstVideoSplitProbe: VideoSplitProbing {
    let facts: VideoSplitSourceFacts
    private(set) var callCount = 0

    init(facts: VideoSplitSourceFacts) {
        self.facts = facts
    }

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(70))
        }
        guard input.id == facts.inputID else {
            throw VideoSplitProbeError.inputIdentityMismatch
        }
        return facts
    }
}

private actor RecordingVideoSplitCoordinator: VideoSplitJobCoordinating {
    private(set) var requests: [VideoSplitBatchRequest] = []
    private(set) var cancelledRequestIDs: [UUID] = []
    let outputURLs: [URL]
    let segmentCount: Int
    let totalBytes: Int64

    init(
        outputURLs: [URL] = [],
        segmentCount: Int = 1,
        totalBytes: Int64 = 1
    ) {
        self.outputURLs = outputURLs
        self.segmentCount = segmentCount
        self.totalBytes = totalBytes
    }

    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        requests.append(request)
        event(
            .progress(
                VideoSplitBatchProgress(
                    requestID: request.id,
                    fraction: 0.6,
                    currentFile: 1,
                    totalFiles: request.items.count,
                    currentDisplayName: request.items.first?.input.file.displayName,
                    currentSegment: 2,
                    totalSegments: 3
                )
            )
        )
        try? await Task.sleep(for: .milliseconds(10))
        event(
            .progress(
                VideoSplitBatchProgress(
                    requestID: request.id,
                    fraction: 0.4,
                    currentFile: 1,
                    totalFiles: request.items.count,
                    currentDisplayName: request.items.first?.input.file.displayName,
                    currentSegment: 2,
                    totalSegments: 3
                )
            )
        )
        try? await Task.sleep(for: .milliseconds(10))
        event(
            .progress(
                VideoSplitBatchProgress(
                    requestID: request.id,
                    fraction: 1,
                    currentFile: request.items.count,
                    totalFiles: request.items.count,
                    currentDisplayName: request.items.last?.input.file.displayName,
                    currentSegment: segmentCount,
                    totalSegments: segmentCount
                )
            )
        )
        try? await Task.sleep(for: .milliseconds(10))
        event(.validationCompleted(requestID: request.id, segmentCount: segmentCount))
        event(.publicationCompleted(requestID: request.id, outputURLs: outputURLs))
        return VideoSplitBatchResult(
            requestID: request.id,
            outputURLs: outputURLs,
            segmentCount: segmentCount,
            totalBytes: totalBytes
        )
    }

    func cancel(requestID: UUID) async {
        cancelledRequestIDs.append(requestID)
    }
}

private actor SuspendedVideoSplitCoordinator: VideoSplitJobCoordinating {
    private(set) var requestID: UUID?
    private(set) var cancelledRequestID: UUID?

    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        requestID = request.id
        event(
            .progress(
                VideoSplitBatchProgress(
                    requestID: request.id,
                    fraction: 0.2,
                    currentFile: 1,
                    totalFiles: request.items.count,
                    currentDisplayName: request.items.first?.input.file.displayName,
                    currentSegment: 1,
                    totalSegments: 1
                )
            )
        )
        while cancelledRequestID == nil, !Task.isCancelled {
            await Task.yield()
        }
        throw VideoSplitJobError.cancelled
    }

    func cancel(requestID: UUID) async {
        cancelledRequestID = requestID
    }
}

private actor RestartableVideoSplitCoordinator: VideoSplitJobCoordinating {
    private(set) var requestIDs: [UUID] = []
    private(set) var cancelledRequestIDs: [UUID] = []
    private var firstCancellationContinuation: CheckedContinuation<Void, Never>?

    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        requestIDs.append(request.id)
        let requestOrdinal = requestIDs.count
        event(
            .progress(
                VideoSplitBatchProgress(
                    requestID: request.id,
                    fraction: 0.2,
                    currentFile: 1,
                    totalFiles: request.items.count,
                    currentDisplayName: request.items.first?.input.file.displayName,
                    currentSegment: 1,
                    totalSegments: 1
                )
            )
        )
        if requestOrdinal == 1 {
            await withCheckedContinuation { continuation in
                firstCancellationContinuation = continuation
            }
            throw VideoSplitJobError.cancelled
        }
        while !cancelledRequestIDs.contains(request.id) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        throw VideoSplitJobError.cancelled
    }

    func cancel(requestID: UUID) async {
        cancelledRequestIDs.append(requestID)
    }

    func releaseFirstCancellation() {
        firstCancellationContinuation?.resume()
        firstCancellationContinuation = nil
    }
}

private struct StaticPresetCatalogLoader: PresetCatalogLoading {
    let presets: [ConversionPreset]

    func loadPresets() async throws -> [ConversionPreset] { presets }
}

private struct FailingPresetCatalogLoader: PresetCatalogLoading {
    func loadPresets() async throws -> [ConversionPreset] {
        throw PresetCatalogError.resourceMissing
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
    ) async throws -> EngineExecutionResult {
        lastPlan = plan
        progress(0)
        progress(1)
        return EngineExecutionResult(
            artifacts: outputs.enumerated().map { index, output in
                StagedOutputArtifact(
                    id: OutputArtifactID(
                        sourceInputID: plan.inputs.indices.contains(index)
                            ? plan.inputs[index].id
                            : UUID(),
                        role: .converted
                    ),
                    fileURL: output
                )
            }
        )
    }

    func cancel(jobID: UUID) async {}
}

private struct FailingConversionEngine: ConversionEngine {
    let error: ConversionError

    func canHandle(_ plan: ConversionPlan) -> Bool { true }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult {
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
    ) async throws -> EngineExecutionResult {
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
