import AppKit
import Foundation
import Observation

enum BatchSection: Equatable, Sendable {
    case image
    case video
    case unsupported
}

@MainActor
@Observable
final class IslandViewModel {
    private(set) var state: IslandState = .idle
    private(set) var presentationMode: IslandPresentationMode = .floatingPill
    private(set) var notchOcclusionHeight: CGFloat = 0

    @ObservationIgnored
    private let inputScanner: any InputScanning

    @ObservationIgnored
    private let conversionEngine: any ConversionEngine

    @ObservationIgnored
    private let batchCoordinator: any BatchJobCoordinating

    @ObservationIgnored
    private let outputDirectorySelector: any OutputDirectorySelecting

    @ObservationIgnored
    private let outputFolderStore: OutputFolderBookmarkStore?

    @ObservationIgnored
    private let preferences: AppPreferences

    @ObservationIgnored
    private let capabilityResolver: ConversionCapabilityResolver

    @ObservationIgnored
    private let thumbnailLoader: any ThumbnailLoading

    @ObservationIgnored
    private let imagePlanBuilder: ImageConversionPlanBuilder

    @ObservationIgnored
    private let videoPlanBuilder: VideoConversionPlanBuilder

    @ObservationIgnored
    private let presetResolver: ConversionPresetResolver

    @ObservationIgnored
    private let batchRequestBuilder: BatchRequestBuilder

    @ObservationIgnored
    private var inspectionTask: Task<Void, Never>?

    @ObservationIgnored
    private var conversionTask: Task<Void, Never>?

    @ObservationIgnored
    private var thumbnailTask: Task<Void, Never>?

    @ObservationIgnored
    private var presetLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var presetCatalog: [ConversionPreset] = []

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var activePlanID: UUID?

    @ObservationIgnored
    private var activeBatchRequestID: UUID?

    @ObservationIgnored
    private var activeScanResult: InputScanResult?

    private(set) var imageIntent: ImageIntent?
    private(set) var videoIntent: VideoIntent?
    private(set) var customVideoTargetMegabytes = 25
    private(set) var isUsingCustomVideoTarget = false
    private(set) var activeFiles: [InputFile] = []
    private(set) var conversionCapability: ConversionCapability = .unsupported(kind: .other)
    private(set) var previewImage: NSImage?
    private(set) var isChoosingOutputFolder = false
    private(set) var availablePresetRecommendations: [PresetRecommendation] = []
    private(set) var selectedPresetID: String?
    private(set) var selectedBatchSection: BatchSection = .unsupported

    @ObservationIgnored
    private var stateBeforeDrag: IslandState?

    @ObservationIgnored
    var onLayoutModeChange: ((IslandLayoutMode) -> Void)?

    @ObservationIgnored
    var onStateChange: ((IslandState) -> Void)?

    init(
        fileInspector: any FileInspecting,
        inputScanner: (any InputScanning)? = nil,
        conversionEngine: any ConversionEngine = ImageConversionEngine(),
        batchCoordinator: (any BatchJobCoordinating)? = nil,
        outputDirectorySelector: any OutputDirectorySelecting = AppKitOutputDirectorySelector(),
        outputFolderStore: OutputFolderBookmarkStore? = nil,
        preferences: AppPreferences? = nil,
        capabilityResolver: ConversionCapabilityResolver = ConversionCapabilityResolver(),
        thumbnailLoader: any ThumbnailLoading = QuickLookThumbnailLoader(),
        imagePlanBuilder: ImageConversionPlanBuilder = ImageConversionPlanBuilder(),
        videoPlanBuilder: VideoConversionPlanBuilder = VideoConversionPlanBuilder(),
        presetCatalogLoader: any PresetCatalogLoading = BundledPresetCatalogLoader(),
        presetResolver: ConversionPresetResolver = ConversionPresetResolver(),
        batchRequestBuilder: BatchRequestBuilder = BatchRequestBuilder()
    ) {
        self.inputScanner = inputScanner ?? ExplicitFileInputScanner(fileInspector: fileInspector)
        self.conversionEngine = conversionEngine
        self.batchCoordinator = batchCoordinator ?? BatchJobCoordinator(conversionEngine: conversionEngine)
        self.outputDirectorySelector = outputDirectorySelector
        self.outputFolderStore = outputFolderStore
        self.preferences = preferences ?? AppPreferences()
        self.capabilityResolver = capabilityResolver
        self.thumbnailLoader = thumbnailLoader
        self.imagePlanBuilder = imagePlanBuilder
        self.videoPlanBuilder = videoPlanBuilder
        self.presetResolver = presetResolver
        self.batchRequestBuilder = batchRequestBuilder
        self.islandOpacity = self.preferences.islandOpacity
        self.preferences.onIslandOpacityChange = { [weak self] opacity in
            self?.islandOpacity = opacity
        }
        presetLoadTask = Task { [weak self, presetCatalogLoader] in
            let presets = (try? await presetCatalogLoader.loadPresets()) ?? []
            guard !Task.isCancelled else { return }
            self?.finishPresetLoading(presets)
        }
    }

    func dragEntered() {
        guard acceptsFileDrops else { return }
        guard state != .dragHover else { return }
        stateBeforeDrag = state
        setState(.dragHover)
    }

    func dragExited() {
        guard state == .dragHover else { return }
        setState(stateBeforeDrag ?? .idle)
        stateBeforeDrag = nil
    }

    func receiveDrop(urls: [URL]) {
        guard acceptsFileDrops else { return }
        stateBeforeDrag = nil
        inspectionTask?.cancel()

        let requestID = UUID()
        activeRequestID = requestID
        setState(.inspecting)

        inspectionTask = Task { [weak self, inputScanner] in
            do {
                let scan = try await inputScanner.scan(urls: urls)
                guard !Task.isCancelled else { return }
                self?.finishInspection(requestID: requestID, result: .success(scan))
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishInspection(requestID: requestID, result: .failure(error))
            }
        }
    }

    func reset() {
        inspectionTask?.cancel()
        conversionTask?.cancel()
        thumbnailTask?.cancel()
        if let activePlanID {
            Task { [conversionEngine] in await conversionEngine.cancel(jobID: activePlanID) }
        }
        if let activeBatchRequestID {
            Task { [batchCoordinator] in
                await batchCoordinator.cancel(requestID: activeBatchRequestID)
            }
        }
        activeRequestID = nil
        activePlanID = nil
        activeBatchRequestID = nil
        activeScanResult = nil
        isChoosingOutputFolder = false
        activeFiles = []
        imageIntent = nil
        videoIntent = nil
        customVideoTargetMegabytes = 25
        isUsingCustomVideoTarget = false
        conversionCapability = .unsupported(kind: .other)
        previewImage = nil
        availablePresetRecommendations = []
        selectedPresetID = nil
        selectedBatchSection = .unsupported
        stateBeforeDrag = nil
        setState(.idle)
    }

    var availableOutputFormats: [ImageOutputFormat] {
        guard case let .image(formats) = conversionCapability else { return [] }
        return formats
    }

    var supportsVideoTargetSize: Bool {
        if isBatchWorkflow {
            return batchInputs(for: .nativeVideo).isEmpty == false
        }
        guard case let .video(_, supportsTargetSize) = conversionCapability else { return false }
        return supportsTargetSize
    }

    var isBatchWorkflow: Bool {
        guard let scan = activeScanResult else { return false }
        if scan.containsFolderRoot { return true }
        let nonemptyKinds = ConversionGroupKind.allCases.filter {
            !batchInputs(for: $0).isEmpty
        }
        return nonemptyKinds.count > 1
    }

    var batchImageCount: Int { batchInputs(for: .image).count }
    var batchVideoCount: Int {
        batchInputs(for: .nativeVideo).count + batchInputs(for: .fallbackVideo).count
    }
    var batchHasFallbackVideo: Bool { !batchInputs(for: .fallbackVideo).isEmpty }
    var batchUnsupportedCount: Int { batchInputs(for: .unsupported).count }

    var batchProcessCount: Int { batchRequestPreview?.processCount ?? 0 }
    var batchSkippedCount: Int { batchRequestPreview?.skippedCount ?? 0 }
    var batchFailClosedCount: Int { batchRequestPreview?.failClosedCount ?? 0 }

    var selectedPresetDisplayName: String? {
        guard let selectedPresetID else { return nil }
        return availablePresetRecommendations.first {
            $0.preset.id == selectedPresetID
        }?.preset.displayName
    }

    func canConfigureImageConversion(for files: [InputFile]) -> Bool {
        if case .image = capabilityResolver.resolve(files) { return true }
        return false
    }

    var acceptsFileDrops: Bool {
        switch state {
        case .preparing, .converting:
            false
        default:
            true
        }
    }

    func continueToActions() {
        guard case let .droppedSummary(files) = state else { return }
        let imageFiles = batchInputs(for: .image).map(\.file)
        let videoFiles = (
            batchInputs(for: .nativeVideo) + batchInputs(for: .fallbackVideo)
        ).map(\.file)
        if !imageFiles.isEmpty {
            selectedBatchSection = .image
            activeFiles = imageFiles
        } else if !videoFiles.isEmpty {
            selectedBatchSection = .video
            activeFiles = videoFiles
        } else {
            selectedBatchSection = .unsupported
            activeFiles = batchInputs(for: .unsupported).map(\.file)
        }
        conversionCapability = capabilityForSelectedSection()
        loadPreview(for: activeFiles.first)
        if !imageFiles.isEmpty,
           case let .image(formats) = capabilityResolver.resolve(imageFiles),
           let defaultFormat = formats.first {
            imageIntent = ImageIntent(
                outputFormat: defaultFormat,
                maxPixelDimension: nil,
                targetBytes: nil,
                qualityPreference: preferences.defaultQuality,
                stripMetadata: preferences.stripMetadataByDefault
            )
        } else {
            imageIntent = nil
        }
        if !videoFiles.isEmpty {
            isUsingCustomVideoTarget = false
            videoIntent = VideoIntent(
                compatibility: .highCompatibility,
                maxResolution: .source,
                targetBytes: nil,
                qualityPreference: .balanced
            )
        } else {
            videoIntent = nil
        }
        selectedPresetID = nil
        refreshPresetRecommendations()
        setState(.actionSelection(files))
    }

    func selectBatchSection(_ section: BatchSection) {
        guard isBatchWorkflow else { return }
        let files: [InputFile]
        switch section {
        case .image:
            files = batchInputs(for: .image).map(\.file)
        case .video:
            files = (
                batchInputs(for: .nativeVideo) + batchInputs(for: .fallbackVideo)
            ).map(\.file)
        case .unsupported:
            files = batchInputs(for: .unsupported).map(\.file)
        }
        guard !files.isEmpty else { return }
        selectedBatchSection = section
        activeFiles = files
        conversionCapability = capabilityForSelectedSection()
        selectedPresetID = nil
        loadPreview(for: files.first)
        refreshPresetRecommendations()
    }

    func continueToImageActions() {
        continueToActions()
    }

    func selectOutputFormat(_ format: ImageOutputFormat) {
        guard availableOutputFormats.contains(format) else { return }
        clearPresetSelection()
        imageIntent?.outputFormat = format
    }

    func selectMaximumDimension(_ dimension: Int?) {
        guard dimension.map({ $0 > 0 }) ?? true else { return }
        guard imageIntent != nil else { return }
        clearPresetSelection()
        imageIntent?.maxPixelDimension = dimension
    }

    func selectQuality(_ quality: QualityPreference) {
        guard imageIntent != nil else { return }
        clearPresetSelection()
        imageIntent?.qualityPreference = quality
    }

    func selectTargetBytes(_ targetBytes: Int64?) {
        guard targetBytes.map({ $0 > 0 }) ?? true else { return }
        guard imageIntent != nil else { return }
        clearPresetSelection()
        imageIntent?.targetBytes = targetBytes
    }

    func setStripMetadata(_ stripMetadata: Bool) {
        guard imageIntent != nil else { return }
        clearPresetSelection()
        imageIntent?.stripMetadata = stripMetadata
    }

    func selectVideoResolution(_ resolution: VideoResolution) {
        guard case let .video(resolutions, _) = conversionCapability,
              resolutions.contains(resolution) else { return }
        clearPresetSelection()
        videoIntent?.maxResolution = resolution
    }

    func selectVideoTargetBytes(_ targetBytes: Int64?) {
        guard supportsVideoTargetSize else { return }
        guard targetBytes.map({ $0 > 0 }) ?? true else { return }
        clearPresetSelection()
        isUsingCustomVideoTarget = false
        videoIntent?.targetBytes = targetBytes
    }

    func selectCustomVideoTarget() {
        guard supportsVideoTargetSize, videoIntent != nil else { return }
        clearPresetSelection()
        isUsingCustomVideoTarget = true
        videoIntent?.targetBytes = Int64(customVideoTargetMegabytes) * 1_000_000
    }

    func adjustCustomVideoTargetMegabytes(by delta: Int) {
        guard supportsVideoTargetSize else { return }
        clearPresetSelection()
        let nextValue = min(max(customVideoTargetMegabytes + delta, 5), 2_000)
        customVideoTargetMegabytes = nextValue
        if isUsingCustomVideoTarget {
            videoIntent?.targetBytes = Int64(nextValue) * 1_000_000
        }
    }

    func returnToSummary() {
        guard let files = activeScanResult?.files, !files.isEmpty else { return }
        imageIntent = nil
        videoIntent = nil
        isUsingCustomVideoTarget = false
        availablePresetRecommendations = []
        selectedPresetID = nil
        activeFiles = files
        conversionCapability = capabilityResolver.resolve(files)
        setState(.droppedSummary(files))
    }

    func applyPreset(id: String) {
        guard let recommendation = availablePresetRecommendations.first(where: {
            $0.preset.id == id
        }) else { return }

        switch recommendation.intent {
        case let .convertImage(intent):
            imageIntent = intent
            if !isBatchWorkflow { videoIntent = nil }
            isUsingCustomVideoTarget = false
        case let .convertVideo(intent):
            if !isBatchWorkflow { imageIntent = nil }
            videoIntent = intent
            isUsingCustomVideoTarget = false
        }
        selectedPresetID = recommendation.preset.id
    }

    func startConversion() {
        if isBatchWorkflow {
            guard case .actionSelection = state,
                  batchProcessCount > 0,
                  !isChoosingOutputFolder else { return }
            conversionTask?.cancel()
            isChoosingOutputFolder = true
            conversionTask = Task { [weak self] in
                await self?.performBatchConversion()
            }
            return
        }
        let intent: ConversionIntent?
        if let imageIntent {
            intent = .convertImage(imageIntent)
        } else if let videoIntent {
            intent = .convertVideo(videoIntent)
        } else {
            intent = nil
        }
        guard case .actionSelection = state,
              let intent,
              !activeFiles.isEmpty,
              !isChoosingOutputFolder else { return }

        conversionTask?.cancel()
        isChoosingOutputFolder = true
        conversionTask = Task { [weak self] in
            await self?.performConversion(intent: intent)
        }
    }

    func cancelConversion() {
        if let requestID = activeBatchRequestID {
            activeBatchRequestID = nil
            conversionTask?.cancel()
            conversionTask = nil
            Task { [batchCoordinator] in
                await batchCoordinator.cancel(requestID: requestID)
            }
            setState(.actionSelection(activeScanResult?.files ?? activeFiles))
            return
        }
        guard let planID = activePlanID else { return }
        activePlanID = nil
        conversionTask?.cancel()
        conversionTask = nil
        Task { [conversionEngine] in await conversionEngine.cancel(jobID: planID) }
        setState(.actionSelection(activeFiles))
    }

    func updatePresentation(
        mode: IslandPresentationMode,
        notchOcclusionHeight: CGFloat,
        notchOcclusionWidth: CGFloat = 0,
        islandWidth: CGFloat = 0
    ) {
        presentationMode = mode
        self.notchOcclusionHeight = notchOcclusionHeight
        self.notchOcclusionWidth = notchOcclusionWidth
        self.islandWidth = islandWidth
    }

    private(set) var notchOcclusionWidth: CGFloat = 0
    private(set) var islandWidth: CGFloat = 0

    private(set) var islandOpacity: Double = 1

    private func finishInspection(
        requestID: UUID,
        result: Result<InputScanResult, Error>
    ) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil

        switch result {
        case let .success(scan):
            activeScanResult = scan
            activeFiles = scan.files
            setState(.droppedSummary(scan.files))
        case .failure:
            setState(
                .failure(
                    UserFacingError(
                        title: "Couldn’t read this item",
                        message: "File Island accepts readable, ordinary files in this technical preview."
                    )
                )
            )
        }
    }

    private func performConversion(intent: ConversionIntent) async {
        let suggestedDirectory = activeFiles.first?.url.deletingLastPathComponent()
        let outputSelection = await resolveOutputDirectory(
            suggestedDirectory: suggestedDirectory
        )
        isChoosingOutputFolder = false
        guard let outputSelection, !Task.isCancelled else {
            conversionTask = nil
            return
        }
        defer {
            if outputSelection.didStartAccessingSecurityScope {
                outputSelection.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let plan: ConversionPlan
            let estimatedOutputBytes: Int64?
            let actionLabel: String
            switch intent {
            case let .convertImage(imageIntent):
                plan = try imagePlanBuilder.makePlan(
                    inputs: activeFiles,
                    intent: imageIntent,
                    outputDirectory: outputSelection.url
                )
                estimatedOutputBytes = imageIntent.targetBytes.map {
                    $0 * Int64(activeFiles.count)
                }
                actionLabel = "Converting image…"
            case let .convertVideo(videoIntent):
                plan = try videoPlanBuilder.makePlan(
                    inputs: activeFiles,
                    intent: videoIntent,
                    outputDirectory: outputSelection.url
                )
                estimatedOutputBytes = plan.estimatedOutput?.totalBytes
                actionLabel = "Converting video…"
            }
            activePlanID = plan.id
            setState(.preparing)
            let totalInputBytes = activeFiles.reduce(Int64(0)) { $0 + $1.fileSize }
            let totalFiles = activeFiles.count
            let outputs = try await conversionEngine.execute(plan) { [weak self] progress in
                Task { @MainActor in
                    guard self?.activePlanID == plan.id else { return }
                    let currentFile = progress > 0
                        ? min(totalFiles, max(1, Int(ceil(progress * Double(totalFiles)))))
                        : 0
                    self?.setState(
                        .converting(
                            JobSnapshot(
                                actionLabel: actionLabel,
                                progress: progress,
                                isEstimated: false,
                                currentFile: currentFile,
                                totalFiles: totalFiles,
                                inputBytes: totalInputBytes,
                                estimatedOutputBytes: estimatedOutputBytes
                            )
                        )
                    )
                }
            }
            guard activePlanID == plan.id else { return }
            activePlanID = nil
            conversionTask = nil
            let outputBytes = outputs.reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            setState(
                .success(
                    ResultSummary(
                        outputURLs: outputs,
                        inputBytes: totalInputBytes,
                        outputBytes: outputBytes
                    )
                )
            )
            if preferences.revealOutputOnCompletion {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
            }
        } catch let error as ConversionError {
            activePlanID = nil
            conversionTask = nil
            if error == .permissionDenied {
                outputFolderStore?.clear()
            }
            if error == .cancelled {
                setState(.actionSelection(activeFiles))
            } else {
                setState(.failure(Self.userFacingError(for: error)))
            }
        } catch {
            activePlanID = nil
            conversionTask = nil
            setState(.failure(Self.userFacingError(for: .conversionFailed(underlying: nil))))
        }
    }

    private func performBatchConversion() async {
        guard let scan = activeScanResult else {
            isChoosingOutputFolder = false
            conversionTask = nil
            return
        }
        let suggestedDirectory = scan.selections.first?.url.deletingLastPathComponent()
        let outputSelection = await resolveOutputDirectory(
            suggestedDirectory: suggestedDirectory
        )
        isChoosingOutputFolder = false
        guard let outputSelection, !Task.isCancelled else {
            conversionTask = nil
            return
        }
        defer {
            if outputSelection.didStartAccessingSecurityScope {
                outputSelection.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let request = try batchRequestBuilder.makeRequest(
                scan: scan,
                imageIntent: imageIntent,
                videoIntent: videoIntent,
                outputDirectory: outputSelection.url
            )
            guard request.processCount > 0 else {
                conversionTask = nil
                setState(.actionSelection(scan.files))
                return
            }
            activeBatchRequestID = request.id
            setState(.preparing)
            let totalInputBytes = scan.files.reduce(Int64(0)) { $0 + $1.fileSize }
            let estimatedOutputBytes = request.executableGroups.compactMap {
                $0.plan?.estimatedOutput?.totalBytes
            }.reduce(Int64(0), +)
            let result = try await batchCoordinator.execute(request) { [weak self] progress in
                Task { @MainActor in
                    guard self?.activeBatchRequestID == progress.requestID else { return }
                    self?.setState(
                        .converting(
                            JobSnapshot(
                                actionLabel: progress.currentDisplayName.map {
                                    "Converting \($0)…"
                                } ?? "Converting batch…",
                                progress: progress.fraction,
                                isEstimated: false,
                                currentFile: progress.currentFile,
                                totalFiles: progress.totalFiles,
                                inputBytes: totalInputBytes,
                                estimatedOutputBytes: estimatedOutputBytes > 0
                                    ? estimatedOutputBytes
                                    : nil
                            )
                        )
                    )
                }
            }
            guard activeBatchRequestID == request.id else { return }
            activeBatchRequestID = nil
            conversionTask = nil
            let outputBytes = result.outputURLs.reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            setState(
                .success(
                    ResultSummary(
                        outputURLs: result.outputURLs,
                        inputBytes: totalInputBytes,
                        outputBytes: outputBytes
                    )
                )
            )
            if preferences.revealOutputOnCompletion, !result.outputURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs)
            }
        } catch let error as ConversionError {
            activeBatchRequestID = nil
            conversionTask = nil
            if error == .permissionDenied { outputFolderStore?.clear() }
            if error == .cancelled {
                setState(.actionSelection(scan.files))
            } else {
                setState(.failure(Self.userFacingError(for: error)))
            }
        } catch {
            activeBatchRequestID = nil
            conversionTask = nil
            setState(.failure(Self.userFacingError(for: .conversionFailed(underlying: nil))))
        }
    }

    private static let unsupportedMediaError = UserFacingError(
        title: "This conversion isn’t available yet",
        message: "Use a supported image, or a readable MOV/MP4/M4V/MKV/WebM video."
    )

    private static func userFacingError(for error: ConversionError) -> UserFacingError {
        switch error {
        case .permissionDenied:
            UserFacingError(
                title: "Couldn’t save the result",
                message: "Choose another output folder and try again."
            )
        case .invalidMedia:
            UserFacingError(
                title: "This file couldn’t be decoded",
                message: "The file may be damaged or contain unsupported media data."
            )
        case .unsupportedInput, .unsupportedOutput:
            unsupportedMediaError
        case .targetSizeUnreachable:
            UserFacingError(
                title: "Couldn’t reach this size",
                message: "The selected limit is too small for a usable media file."
            )
        case .insufficientDiskSpace:
            UserFacingError(title: "Not enough storage", message: "Free some disk space and try again.")
        case .cancelled:
            UserFacingError(title: "Cancelled", message: "No converted files were kept.")
        case .engineUnavailable, .conversionFailed:
            UserFacingError(title: "Conversion failed", message: "The original files were not changed.")
        }
    }

    private func setState(_ newState: IslandState) {
        let previousLayout = state.layoutMode
        state = newState
        onStateChange?(newState)
        if previousLayout != newState.layoutMode {
            onLayoutModeChange?(newState.layoutMode)
        }
    }

    private func finishPresetLoading(_ presets: [ConversionPreset]) {
        presetCatalog = presets
        if case .actionSelection = state {
            refreshPresetRecommendations()
        }
    }

    private func refreshPresetRecommendations() {
        availablePresetRecommendations = presetResolver.recommendations(
            for: activeFiles,
            capability: conversionCapability,
            presets: presetCatalog
        )
        if !availablePresetRecommendations.contains(where: {
            $0.preset.id == selectedPresetID
        }) {
            selectedPresetID = nil
        }
    }

    private func clearPresetSelection() {
        selectedPresetID = nil
    }

    private var batchRequestPreview: BatchConversionRequest? {
        guard let activeScanResult else { return nil }
        return try? batchRequestBuilder.makeRequest(
            scan: activeScanResult,
            imageIntent: imageIntent,
            videoIntent: videoIntent,
            outputDirectory: URL(fileURLWithPath: "/", isDirectory: true)
        )
    }

    private func batchInputs(for kind: ConversionGroupKind) -> [BatchInput] {
        guard let inputs = activeScanResult?.inputs else { return [] }
        return inputs.filter { input in
            switch kind {
            case .image:
                MediaConversionMatrix.imageInputFormats.contains(input.file.format)
            case .nativeVideo:
                MediaConversionMatrix.nativeVideoInputFormats.contains(input.file.format)
            case .fallbackVideo:
                MediaConversionMatrix.fallbackVideoInputFormats.contains(input.file.format)
            case .unsupported:
                !MediaConversionMatrix.imageInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.nativeVideoInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.fallbackVideoInputFormats.contains(input.file.format)
            }
        }
    }

    private func capabilityForSelectedSection() -> ConversionCapability {
        switch selectedBatchSection {
        case .image:
            capabilityResolver.resolve(batchInputs(for: .image).map(\.file))
        case .video:
            .video(
                availableResolutions: [.source, .p1080, .p720],
                supportsTargetSize: !batchInputs(for: .nativeVideo).isEmpty
            )
        case .unsupported:
            .unsupported(kind: .other)
        }
    }

    private func loadPreview(for file: InputFile?) {
        thumbnailTask?.cancel()
        previewImage = nil
        guard let file else { return }
        thumbnailTask = Task { [weak self, thumbnailLoader] in
            let image = await thumbnailLoader.thumbnail(
                for: file.url,
                size: CGSize(width: 180, height: 120)
            )
            guard !Task.isCancelled else { return }
            self?.previewImage = image
        }
    }

    private func resolveOutputDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection? {
        if let outputFolderStore {
            do {
                if let resolved = try outputFolderStore.resolve() {
                    let didStartAccessing = resolved.url.startAccessingSecurityScopedResource()
                    if Self.isExistingDirectory(resolved.url) {
                        return OutputDirectorySelection(
                            url: resolved.url,
                            didStartAccessingSecurityScope: didStartAccessing
                        )
                    }
                    if didStartAccessing {
                        resolved.url.stopAccessingSecurityScopedResource()
                    }
                    outputFolderStore.clear()
                }
            } catch {
                outputFolderStore.clear()
            }
        }

        guard let selection = await outputDirectorySelector.selectDirectory(
            suggestedDirectory: suggestedDirectory
        ) else { return nil }
        if let outputFolderStore {
            do {
                try outputFolderStore.save(selection.url)
            } catch {
                if selection.didStartAccessingSecurityScope {
                    selection.url.stopAccessingSecurityScopedResource()
                }
                setState(
                    .failure(
                        UserFacingError(
                            title: "Couldn’t remember this folder",
                            message: "Choose another output folder and try again."
                        )
                    )
                )
                return nil
            }
        }
        return selection
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
