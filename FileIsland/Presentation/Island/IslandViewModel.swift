import AppKit
import Foundation
import Observation

enum BatchSection: Equatable, Sendable {
    case image
    case video
    case audio
    case unsupported
}

private struct VideoSplitPlanningFingerprint: Equatable, Sendable {
    let inputs: [BatchInput]
    let limits: VideoSplitCustomLimits
}

private enum VideoSplitPlanningOutcome: Sendable {
    case success([VideoSplitBatchItem])
    case failure(IslandVideoSplitIssue)
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
    private let videoSplitProbe: (any VideoSplitProbing)?

    @ObservationIgnored
    private let videoSplitCoordinator: (any VideoSplitJobCoordinating)?

    @ObservationIgnored
    private let videoSplitPlanBuilder: VideoSplitPlanBuilder

    @ObservationIgnored
    private let videoSplitRuntimeAvailable: Bool

    @ObservationIgnored
    private let videoSplitPlanningDebounce: Duration

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
    private let audioPlanBuilder: AudioConversionPlanBuilder

    @ObservationIgnored
    private let presetResolver: ConversionPresetResolver

    @ObservationIgnored
    private let batchRequestBuilder: BatchRequestBuilder

    @ObservationIgnored
    private let successDisplayDuration: Duration

    @ObservationIgnored
    private var inspectionTask: Task<Void, Never>?

    @ObservationIgnored
    private var conversionTask: Task<Void, Never>?

    @ObservationIgnored
    private var videoSplitPlanningTask: Task<Void, Never>?

    @ObservationIgnored
    private var thumbnailTask: Task<Void, Never>?

    @ObservationIgnored
    private var presetLoadTask: Task<Void, Never>?

    @ObservationIgnored
    private var successCollapseTask: Task<Void, Never>?

    @ObservationIgnored
    private var successCollapsePending = false

    @ObservationIgnored
    private var isPointerInside = false

    @ObservationIgnored
    private var presetCatalog: [ConversionPreset] = []

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var activePlanID: UUID?

    @ObservationIgnored
    private var activeBatchRequestID: UUID?

    @ObservationIgnored
    private var activeVideoSplitRequestID: UUID?

    @ObservationIgnored
    private var videoSplitPlanningToken: UUID?

    @ObservationIgnored
    private var videoSplitPlanFingerprint: VideoSplitPlanningFingerprint?

    @ObservationIgnored
    private var plannedVideoSplitItems: [VideoSplitBatchItem] = []

    @ObservationIgnored
    private var videoSplitLastProgressFraction = 0.0

    @ObservationIgnored
    private var activeScanResult: InputScanResult?

    @ObservationIgnored
    private var previousConfigurableBatchSection: BatchSection?

    private(set) var imageIntent: ImageIntent?
    private(set) var videoIntent: VideoIntent?
    private(set) var audioIntent: AudioIntent?
    private(set) var customVideoTargetMegabytes = 25
    private(set) var isUsingCustomVideoTarget = false
    private(set) var activeFiles: [InputFile] = []
    private(set) var conversionCapability: ConversionCapability = .unsupported(kind: .other)
    private(set) var previewImage: NSImage?
    private(set) var isChoosingOutputFolder = false {
        didSet {
            guard isChoosingOutputFolder != oldValue else { return }
            onInputAvailabilityChange?(acceptsFileDrops)
        }
    }
    private(set) var availablePresetRecommendations: [PresetRecommendation] = []
    private(set) var selectedPresetID: String?
    private(set) var selectedBatchSection: BatchSection = .unsupported
    private(set) var videoOperation: IslandVideoOperation = .convert
    private(set) var videoSplitMaximumMegabytesText = "100"
    private(set) var videoSplitMaximumDurationSecondsText = ""
    private(set) var videoSplitSizeUnit: VideoSplitSizeUnit = .megabytes
    private(set) var videoSplitDurationUnit: VideoSplitDurationUnit = .seconds
    private(set) var videoSplitPlanningState: IslandVideoSplitPlanningState = .inactive
    private(set) var videoSplitPlanPreview: VideoSplitBatchPlanPreview?
    private(set) var videoSplitProgress: VideoSplitBatchProgress?
    private(set) var lastVideoSplitResult: VideoSplitBatchResult?

    @ObservationIgnored
    private var stateBeforeDrag: IslandState?

    @ObservationIgnored
    var onLayoutModeChange: ((IslandLayoutMode) -> Void)?

    @ObservationIgnored
    var onStateChange: ((IslandState) -> Void)?

    @ObservationIgnored
    var onInputAvailabilityChange: ((Bool) -> Void)?

    @ObservationIgnored
    private var isKeyboardInteractionActive = false

    init(
        fileInspector: any FileInspecting,
        inputScanner: (any InputScanning)? = nil,
        conversionEngine: any ConversionEngine = ImageConversionEngine(),
        batchCoordinator: (any BatchJobCoordinating)? = nil,
        videoSplitProbe: (any VideoSplitProbing)? = nil,
        videoSplitCoordinator: (any VideoSplitJobCoordinating)? = nil,
        videoSplitPlanBuilder: VideoSplitPlanBuilder = VideoSplitPlanBuilder(),
        videoSplitRuntimeAvailable: Bool? = nil,
        videoSplitPlanningDebounce: Duration = .milliseconds(250),
        outputDirectorySelector: any OutputDirectorySelecting = AppKitOutputDirectorySelector(),
        outputFolderStore: OutputFolderBookmarkStore? = nil,
        preferences: AppPreferences? = nil,
        capabilityResolver: ConversionCapabilityResolver = ConversionCapabilityResolver(),
        thumbnailLoader: any ThumbnailLoading = QuickLookThumbnailLoader(),
        imagePlanBuilder: ImageConversionPlanBuilder = ImageConversionPlanBuilder(),
        videoPlanBuilder: VideoConversionPlanBuilder = VideoConversionPlanBuilder(),
        audioPlanBuilder: AudioConversionPlanBuilder = AudioConversionPlanBuilder(),
        presetCatalogLoader: any PresetCatalogLoading = BundledPresetCatalogLoader(),
        presetResolver: ConversionPresetResolver = ConversionPresetResolver(),
        batchRequestBuilder: BatchRequestBuilder = BatchRequestBuilder(),
        successDisplayDuration: Duration = IslandMotionPolicy.successDisplayDuration
    ) {
        self.inputScanner = inputScanner ?? ExplicitFileInputScanner(fileInspector: fileInspector)
        self.conversionEngine = conversionEngine
        self.batchCoordinator =
            batchCoordinator ?? BatchJobCoordinator(conversionEngine: conversionEngine)
        self.videoSplitProbe = videoSplitProbe
        self.videoSplitCoordinator = videoSplitCoordinator
        self.videoSplitPlanBuilder = videoSplitPlanBuilder
        self.videoSplitRuntimeAvailable =
            videoSplitRuntimeAvailable
            ?? (videoSplitProbe != nil && videoSplitCoordinator != nil)
        self.videoSplitPlanningDebounce = videoSplitPlanningDebounce
        self.outputDirectorySelector = outputDirectorySelector
        self.outputFolderStore = outputFolderStore
        self.preferences = preferences ?? AppPreferences()
        self.capabilityResolver = capabilityResolver
        self.thumbnailLoader = thumbnailLoader
        self.imagePlanBuilder = imagePlanBuilder
        self.videoPlanBuilder = videoPlanBuilder
        self.audioPlanBuilder = audioPlanBuilder
        self.presetResolver = presetResolver
        self.batchRequestBuilder = batchRequestBuilder
        self.successDisplayDuration = successDisplayDuration
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
        invalidateVideoSplitPlanning(resetOperation: true)

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
        videoSplitPlanningTask?.cancel()
        thumbnailTask?.cancel()
        successCollapseTask?.cancel()
        successCollapseTask = nil
        successCollapsePending = false
        if let activePlanID {
            Task { [conversionEngine] in await conversionEngine.cancel(jobID: activePlanID) }
        }
        if let activeBatchRequestID {
            Task { [batchCoordinator] in
                await batchCoordinator.cancel(requestID: activeBatchRequestID)
            }
        }
        if let activeVideoSplitRequestID, let videoSplitCoordinator {
            Task {
                await videoSplitCoordinator.cancel(requestID: activeVideoSplitRequestID)
            }
        }
        activeRequestID = nil
        activePlanID = nil
        activeBatchRequestID = nil
        activeVideoSplitRequestID = nil
        videoSplitPlanningToken = nil
        videoSplitPlanFingerprint = nil
        plannedVideoSplitItems = []
        videoSplitLastProgressFraction = 0
        activeScanResult = nil
        isChoosingOutputFolder = false
        activeFiles = []
        imageIntent = nil
        videoIntent = nil
        audioIntent = nil
        customVideoTargetMegabytes = 25
        isUsingCustomVideoTarget = false
        conversionCapability = .unsupported(kind: .other)
        previewImage = nil
        availablePresetRecommendations = []
        selectedPresetID = nil
        selectedBatchSection = .unsupported
        videoOperation = .convert
        videoSplitMaximumMegabytesText = "100"
        videoSplitMaximumDurationSecondsText = ""
        videoSplitSizeUnit = .megabytes
        videoSplitDurationUnit = .seconds
        videoSplitPlanningState = .inactive
        videoSplitPlanPreview = nil
        videoSplitProgress = nil
        lastVideoSplitResult = nil
        previousConfigurableBatchSection = nil
        stateBeforeDrag = nil
        setState(.idle)
    }

    func setPointerInside(_ isInside: Bool) {
        isPointerInside = isInside
        guard !isInside,
            !isKeyboardInteractionActive,
            successCollapsePending
        else { return }
        successCollapsePending = false
        reset()
    }

    func setKeyboardInteractionActive(_ isActive: Bool) {
        isKeyboardInteractionActive = isActive
        guard !isActive,
            !isPointerInside,
            successCollapsePending
        else { return }
        successCollapsePending = false
        reset()
    }

    var availableOutputFormats: [ImageOutputFormat] {
        guard case .image(let formats) = conversionCapability else { return [] }
        return formats
    }

    var supportsVideoTargetSize: Bool {
        if isBatchWorkflow {
            return batchInputs(for: .nativeVideo).isEmpty == false
        }
        guard case .video(_, let supportsTargetSize) = conversionCapability else { return false }
        return supportsTargetSize
    }

    var isVideoSplitSelected: Bool {
        videoOperation == .splitForSharing
    }

    var videoSplitInputCount: Int {
        videoInputsForSplit.count
    }

    var canStartVideoSplit: Bool {
        guard isVideoSplitSelected,
            videoSplitRuntimeAvailable,
            !isChoosingOutputFolder,
            activeVideoSplitRequestID == nil,
            videoSplitPlanningState == .ready,
            let preview = videoSplitPlanPreview,
            preview.isExecutionAvailable,
            !plannedVideoSplitItems.isEmpty,
            let currentFingerprint = makeVideoSplitPlanningFingerprint(),
            videoSplitPlanFingerprint == currentFingerprint
        else {
            return false
        }
        return plannedVideoSplitItems.count == videoInputsForSplit.count
            && zip(plannedVideoSplitItems, videoInputsForSplit).allSatisfy {
                $0.input == $1 && $0.plan.input == $1.file
            }
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
    var batchAudioCount: Int { batchInputs(for: .audio).count }
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
        state.allowsInputSelection && !isChoosingOutputFolder
    }

    func continueToActions() {
        guard case .droppedSummary(let files) = state else { return }
        invalidateVideoSplitPlanning(resetOperation: true)
        let imageFiles = batchInputs(for: .image).map(\.file)
        let videoFiles = (batchInputs(for: .nativeVideo) + batchInputs(for: .fallbackVideo)).map(\.file)
        let audioFiles = batchInputs(for: .audio).map(\.file)
        if !imageFiles.isEmpty {
            selectedBatchSection = .image
            previousConfigurableBatchSection = .image
            activeFiles = imageFiles
        } else if !videoFiles.isEmpty {
            selectedBatchSection = .video
            previousConfigurableBatchSection = .video
            activeFiles = videoFiles
        } else if !audioFiles.isEmpty {
            selectedBatchSection = .audio
            previousConfigurableBatchSection = .audio
            activeFiles = audioFiles
        } else {
            selectedBatchSection = .unsupported
            previousConfigurableBatchSection = nil
            activeFiles = batchInputs(for: .unsupported).map(\.file)
        }
        conversionCapability = capabilityForSelectedSection()
        loadPreview(for: activeFiles.first)
        if !imageFiles.isEmpty,
            case .image(let formats) = capabilityResolver.resolve(imageFiles),
            let defaultFormat = formats.first
        {
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
        audioIntent =
            audioFiles.isEmpty
            ? nil
            : AudioIntent(
                outputFormat: .m4a,
                quality: .balanced,
                stripMetadata: preferences.stripMetadataByDefault
            )
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
            files = (batchInputs(for: .nativeVideo) + batchInputs(for: .fallbackVideo)).map(\.file)
        case .audio:
            files = batchInputs(for: .audio).map(\.file)
        case .unsupported:
            files = batchInputs(for: .unsupported).map(\.file)
        }
        guard !files.isEmpty else { return }
        if selectedBatchSection != section,
            selectedBatchSection == .image || selectedBatchSection == .video
                || selectedBatchSection == .audio
        {
            previousConfigurableBatchSection = selectedBatchSection
        }
        selectedBatchSection = section
        activeFiles = files
        conversionCapability = capabilityForSelectedSection()
        selectedPresetID = nil
        loadPreview(for: files.first)
        refreshPresetRecommendations()
        if section == .video, isVideoSplitSelected {
            scheduleVideoSplitPlanning()
        } else {
            invalidateVideoSplitPlanning(resetOperation: false)
        }
    }

    func returnFromUnsupportedSection() {
        guard isBatchWorkflow, selectedBatchSection == .unsupported else {
            returnToSummary()
            return
        }

        let fallbackSections: [BatchSection] = [
            previousConfigurableBatchSection,
            batchImageCount > 0 ? .image : nil,
            batchVideoCount > 0 ? .video : nil,
            batchAudioCount > 0 ? .audio : nil,
        ].compactMap { $0 }

        guard
            let destination = fallbackSections.first(where: { section in
                switch section {
                case .image: batchImageCount > 0
                case .video: batchVideoCount > 0
                case .audio: batchAudioCount > 0
                case .unsupported: false
                }
            })
        else {
            returnToSummary()
            return
        }
        selectBatchSection(destination)
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
        guard case .video(let resolutions, _) = conversionCapability,
            resolutions.contains(resolution)
        else { return }
        clearPresetSelection()
        videoIntent?.maxResolution = resolution
    }

    func selectVideoOperation(_ operation: IslandVideoOperation) {
        guard case .video = conversionCapability,
            operation != videoOperation
        else { return }
        videoOperation = operation
        selectedPresetID = nil
        lastVideoSplitResult = nil
        videoSplitProgress = nil
        if operation == .splitForSharing {
            scheduleVideoSplitPlanning()
        } else {
            invalidateVideoSplitPlanning(resetOperation: false)
        }
    }

    func updateVideoSplitMaximumMegabytes(_ value: String) {
        guard isVideoSplitSelected else { return }
        videoSplitMaximumMegabytesText = value
        scheduleVideoSplitPlanning()
    }

    func updateVideoSplitMaximumDurationSeconds(_ value: String) {
        guard isVideoSplitSelected else { return }
        videoSplitMaximumDurationSecondsText = value
        scheduleVideoSplitPlanning()
    }

    func selectVideoSplitSizeUnit(_ unit: VideoSplitSizeUnit) {
        guard isVideoSplitSelected, unit != videoSplitSizeUnit else { return }
        videoSplitMaximumMegabytesText = VideoSplitLimitDisplayFormatter.convertedText(
            videoSplitMaximumMegabytesText,
            from: videoSplitSizeUnit,
            to: unit
        )
        videoSplitSizeUnit = unit
        scheduleVideoSplitPlanning()
    }

    func selectVideoSplitDurationUnit(_ unit: VideoSplitDurationUnit) {
        guard isVideoSplitSelected, unit != videoSplitDurationUnit else { return }
        videoSplitMaximumDurationSecondsText = VideoSplitLimitDisplayFormatter.convertedText(
            videoSplitMaximumDurationSecondsText,
            from: videoSplitDurationUnit,
            to: unit
        )
        videoSplitDurationUnit = unit
        scheduleVideoSplitPlanning()
    }

    var videoSplitSizeSliderPosition: Double {
        let canonical =
            VideoSplitLimitDisplayFormatter.decimal(
                from: canonicalVideoSplitLimitTexts.megabytes
            ) ?? 100
        return VideoSplitLimitSliderScale.sizePosition(forCanonicalMegabytes: canonical)
    }

    var videoSplitDurationSliderPosition: Double {
        let canonical =
            VideoSplitLimitDisplayFormatter.decimal(
                from: canonicalVideoSplitLimitTexts.seconds
            ) ?? 10
        return VideoSplitLimitSliderScale.durationPosition(forCanonicalSeconds: canonical)
    }

    func updateVideoSplitSizeSliderPosition(_ position: Double) {
        guard isVideoSplitSelected else { return }
        let canonical = VideoSplitLimitSliderScale.canonicalMegabytes(at: position)
        videoSplitMaximumMegabytesText = VideoSplitLimitDisplayFormatter.displayText(
            forCanonicalValue: canonical,
            unit: videoSplitSizeUnit
        )
        scheduleVideoSplitPlanning()
    }

    func updateVideoSplitDurationSliderPosition(_ position: Double) {
        guard isVideoSplitSelected else { return }
        let canonical = VideoSplitLimitSliderScale.canonicalSeconds(at: position)
        videoSplitMaximumDurationSecondsText = VideoSplitLimitDisplayFormatter.displayText(
            forCanonicalValue: canonical,
            unit: videoSplitDurationUnit
        )
        scheduleVideoSplitPlanning()
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

    func selectAudioOutputFormat(_ format: AudioOutputFormat) {
        guard case .audio(let formats) = conversionCapability,
            formats.contains(format)
        else { return }
        audioIntent?.outputFormat = format
    }

    func selectAudioQuality(_ quality: AudioQuality) {
        guard audioIntent != nil else { return }
        audioIntent?.quality = quality
    }

    func setAudioStripMetadata(_ stripMetadata: Bool) {
        guard audioIntent != nil else { return }
        audioIntent?.stripMetadata = stripMetadata
    }

    func returnToSummary() {
        guard let files = activeScanResult?.files, !files.isEmpty else { return }
        invalidateVideoSplitPlanning(resetOperation: true)
        imageIntent = nil
        videoIntent = nil
        audioIntent = nil
        isUsingCustomVideoTarget = false
        availablePresetRecommendations = []
        selectedPresetID = nil
        activeFiles = files
        conversionCapability = capabilityResolver.resolve(files)
        setState(.droppedSummary(files))
    }

    func applyPreset(id: String) {
        guard
            let recommendation = availablePresetRecommendations.first(where: {
                $0.preset.id == id
            })
        else { return }

        switch recommendation.intent {
        case .convertImage(let intent):
            imageIntent = intent
            if !isBatchWorkflow { videoIntent = nil }
            isUsingCustomVideoTarget = false
        case .convertVideo(let intent):
            if !isBatchWorkflow { imageIntent = nil }
            videoIntent = intent
            isUsingCustomVideoTarget = false
        case .convertAudio(let intent):
            if !isBatchWorkflow {
                imageIntent = nil
                videoIntent = nil
            }
            audioIntent = intent
        }
        selectedPresetID = recommendation.preset.id
    }

    func startConversion() {
        if isBatchWorkflow {
            guard case .actionSelection = state,
                batchProcessCount > 0,
                !isChoosingOutputFolder
            else { return }
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
        } else if let audioIntent {
            intent = .convertAudio(audioIntent)
        } else {
            intent = nil
        }
        guard case .actionSelection = state,
            let intent,
            !activeFiles.isEmpty,
            !isChoosingOutputFolder
        else { return }

        conversionTask?.cancel()
        isChoosingOutputFolder = true
        conversionTask = Task { [weak self] in
            await self?.performConversion(intent: intent)
        }
    }

    func startVideoSplit() {
        guard canStartVideoSplit,
            case .actionSelection = state,
            let scan = activeScanResult,
            let fingerprint = videoSplitPlanFingerprint,
            let currentFingerprint = makeVideoSplitPlanningFingerprint(),
            fingerprint == currentFingerprint,
            let videoSplitCoordinator
        else { return }

        let items = plannedVideoSplitItems
        conversionTask?.cancel()
        isChoosingOutputFolder = true
        conversionTask = Task { [weak self] in
            await self?.performVideoSplit(
                scan: scan,
                items: items,
                fingerprint: fingerprint,
                coordinator: videoSplitCoordinator
            )
        }
    }

    func cancelConversion() {
        if let requestID = activeVideoSplitRequestID,
            let videoSplitCoordinator
        {
            activeVideoSplitRequestID = nil
            conversionTask?.cancel()
            conversionTask = nil
            videoSplitProgress = nil
            videoSplitLastProgressFraction = 0
            Task {
                await videoSplitCoordinator.cancel(requestID: requestID)
            }
            setState(.actionSelection(activeScanResult?.files ?? activeFiles))
            return
        }
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
        case .success(let scan):
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

    private func performVideoSplit(
        scan: InputScanResult,
        items: [VideoSplitBatchItem],
        fingerprint: VideoSplitPlanningFingerprint,
        coordinator: any VideoSplitJobCoordinating
    ) async {
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
        guard isVideoSplitSelected,
            makeVideoSplitPlanningFingerprint() == fingerprint,
            plannedVideoSplitItems == items,
            videoSplitPlanFingerprint == fingerprint
        else {
            conversionTask = nil
            setState(.actionSelection(scan.files))
            return
        }

        let request = VideoSplitBatchRequest(
            selections: scan.selections,
            outputDirectory: outputSelection.url,
            items: items
        )
        let totalInputBytes = items.reduce(Int64(0)) { partial, item in
            let (sum, overflow) = partial.addingReportingOverflow(item.input.file.fileSize)
            return overflow ? Int64.max : sum
        }
        activeVideoSplitRequestID = request.id
        videoSplitLastProgressFraction = 0
        videoSplitProgress = nil
        lastVideoSplitResult = nil
        setState(.preparing)

        do {
            let result = try await coordinator.execute(request) { [weak self] progress in
                Task { @MainActor in
                    guard self?.activeVideoSplitRequestID == progress.requestID else { return }
                    guard progress.fraction >= (self?.videoSplitLastProgressFraction ?? 0) else {
                        return
                    }
                    let fraction = max(
                        self?.videoSplitLastProgressFraction ?? 0,
                        min(max(progress.fraction, 0), 1)
                    )
                    self?.videoSplitLastProgressFraction = fraction
                    let stableProgress = VideoSplitBatchProgress(
                        requestID: progress.requestID,
                        fraction: fraction,
                        currentFile: progress.currentFile,
                        totalFiles: progress.totalFiles,
                        currentDisplayName: progress.currentDisplayName,
                        currentSegment: progress.currentSegment,
                        totalSegments: progress.totalSegments
                    )
                    self?.videoSplitProgress = stableProgress
                    self?.setState(
                        .converting(
                            JobSnapshot(
                                actionLabel: "Splitting video…",
                                progress: fraction,
                                isEstimated: false,
                                currentFile: progress.currentFile,
                                totalFiles: progress.totalFiles,
                                inputBytes: totalInputBytes,
                                estimatedOutputBytes: nil
                            )
                        )
                    )
                }
            }
            guard activeVideoSplitRequestID == request.id else { return }
            activeVideoSplitRequestID = nil
            conversionTask = nil
            videoSplitLastProgressFraction = 1
            lastVideoSplitResult = result
            setState(
                .success(
                    ResultSummary(
                        outputURLs: result.outputURLs,
                        inputBytes: totalInputBytes,
                        outputBytes: result.totalBytes
                    )
                )
            )
            if preferences.revealOutputOnCompletion, !result.outputURLs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs)
            }
        } catch let error as VideoSplitJobError {
            guard activeVideoSplitRequestID == request.id else { return }
            activeVideoSplitRequestID = nil
            conversionTask = nil
            videoSplitProgress = nil
            videoSplitLastProgressFraction = 0
            if error == .cancelled {
                setState(.actionSelection(scan.files))
            } else {
                setState(.failure(Self.userFacingError(for: error)))
            }
        } catch is CancellationError {
            guard activeVideoSplitRequestID == request.id else { return }
            activeVideoSplitRequestID = nil
            conversionTask = nil
            videoSplitProgress = nil
            videoSplitLastProgressFraction = 0
            setState(.actionSelection(scan.files))
        } catch {
            guard activeVideoSplitRequestID == request.id else { return }
            activeVideoSplitRequestID = nil
            conversionTask = nil
            videoSplitProgress = nil
            videoSplitLastProgressFraction = 0
            setState(.failure(Self.userFacingError(for: .validationFailed)))
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
            case .convertImage(let imageIntent):
                plan = try imagePlanBuilder.makePlan(
                    inputs: activeFiles,
                    intent: imageIntent,
                    outputDirectory: outputSelection.url
                )
                estimatedOutputBytes = imageIntent.targetBytes.map {
                    $0 * Int64(activeFiles.count)
                }
                actionLabel = "Converting image…"
            case .convertVideo(let videoIntent):
                plan = try videoPlanBuilder.makePlan(
                    inputs: activeFiles,
                    intent: videoIntent,
                    outputDirectory: outputSelection.url
                )
                estimatedOutputBytes = plan.estimatedOutput?.totalBytes
                actionLabel = "Converting video…"
            case .convertAudio(let audioIntent):
                plan = try audioPlanBuilder.makePlan(
                    inputs: activeFiles,
                    intent: audioIntent,
                    outputDirectory: outputSelection.url
                )
                estimatedOutputBytes = nil
                actionLabel = "Converting audio…"
            }
            activePlanID = plan.id
            setState(.preparing)
            let totalInputBytes = activeFiles.reduce(Int64(0)) { $0 + $1.fileSize }
            let totalFiles = activeFiles.count
            let executionResult = try await conversionEngine.execute(plan) { [weak self] progress in
                Task { @MainActor in
                    guard self?.activePlanID == plan.id else { return }
                    let currentFile =
                        progress > 0
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
            let outputs = executionResult.outputURLs
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
                audioIntent: audioIntent,
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
        message: "Use a supported image, video, or audio file."
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

    private static func userFacingError(for error: VideoSplitJobError) -> UserFacingError {
        switch error {
        case .cancelled:
            UserFacingError(
                title: "Split cancelled",
                message: "No video segments were kept."
            )
        case .stalePlan:
            UserFacingError(
                title: "The source video changed",
                message: "Drop the source again to build a new split plan."
            )
        case .keyframeSpacingUnreachable, .retryLimitReached:
            UserFacingError(
                title: "These limits can’t be met in fast mode",
                message: "Increase the size or duration limit and try again."
            )
        case .engineUnavailable:
            UserFacingError(
                title: "Split runtime unavailable",
                message: "Reinstall File Island so its bundled media tools are available."
            )
        case .invalidOutputDirectory, .publicationFailed:
            UserFacingError(
                title: "Couldn’t save the video segments",
                message: "Choose another output folder and try again."
            )
        case .anotherRequestIsRunning:
            UserFacingError(
                title: "Another split is still running",
                message: "Wait for it to finish or cancel it before starting again."
            )
        case .emptyRequest, .duplicateInputIdentity, .validationFailed:
            UserFacingError(
                title: "Couldn’t split these videos",
                message: "The original files were not changed and no partial results were kept."
            )
        }
    }

    private func setState(_ newState: IslandState) {
        let previousLayout = state.layoutMode
        if newState.visualPhase != .success {
            successCollapseTask?.cancel()
            successCollapseTask = nil
            successCollapsePending = false
        }
        state = newState
        onStateChange?(newState)
        onInputAvailabilityChange?(acceptsFileDrops)
        if previousLayout != newState.layoutMode {
            onLayoutModeChange?(newState.layoutMode)
        }
        if newState.visualPhase == .success {
            scheduleSuccessCollapse()
        }
    }

    private func scheduleSuccessCollapse() {
        successCollapseTask?.cancel()
        successCollapseTask = Task { [weak self, successDisplayDuration] in
            do {
                try await Task.sleep(for: successDisplayDuration)
            } catch {
                return
            }
            guard let self, self.state.visualPhase == .success else { return }
            self.successCollapseTask = nil
            if self.isPointerInside || self.isKeyboardInteractionActive {
                self.successCollapsePending = true
            } else {
                self.reset()
            }
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
            audioIntent: audioIntent,
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
            case .audio:
                MediaConversionMatrix.audioInputFormats.contains(input.file.format)
            case .unsupported:
                !MediaConversionMatrix.imageInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.nativeVideoInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.fallbackVideoInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.audioInputFormats.contains(input.file.format)
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
        case .audio:
            .audio(availableFormats: MediaConversionMatrix.audioOutputFormats)
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

    private var videoInputsForSplit: [BatchInput] {
        guard let inputs = activeScanResult?.inputs else { return [] }
        return inputs.filter { $0.file.kind == .video }
    }

    private var canonicalVideoSplitLimitTexts: (megabytes: String, seconds: String) {
        (
            VideoSplitLimitDisplayFormatter.canonicalText(
                videoSplitMaximumMegabytesText,
                unit: videoSplitSizeUnit
            ),
            VideoSplitLimitDisplayFormatter.canonicalText(
                videoSplitMaximumDurationSecondsText,
                unit: videoSplitDurationUnit
            )
        )
    }

    private func makeVideoSplitPlanningFingerprint() -> VideoSplitPlanningFingerprint? {
        let canonicalLimits = canonicalVideoSplitLimitTexts
        guard isVideoSplitSelected,
            !videoInputsForSplit.isEmpty,
            let limits = try? VideoSplitCustomLimits.parse(
                maximumMegabytes: canonicalLimits.megabytes,
                maximumDurationSeconds: canonicalLimits.seconds
            )
        else {
            return nil
        }
        return VideoSplitPlanningFingerprint(
            inputs: videoInputsForSplit,
            limits: limits
        )
    }

    private func invalidateVideoSplitPlanning(resetOperation: Bool) {
        videoSplitPlanningTask?.cancel()
        videoSplitPlanningTask = nil
        videoSplitPlanningToken = nil
        videoSplitPlanFingerprint = nil
        plannedVideoSplitItems = []
        videoSplitPlanPreview = nil
        videoSplitPlanningState = .inactive
        if resetOperation {
            videoOperation = .convert
            videoSplitProgress = nil
            lastVideoSplitResult = nil
            videoSplitLastProgressFraction = 0
        }
    }

    private func scheduleVideoSplitPlanning() {
        videoSplitPlanningTask?.cancel()
        videoSplitPlanningTask = nil
        videoSplitPlanningToken = nil
        videoSplitPlanFingerprint = nil
        plannedVideoSplitItems = []
        videoSplitPlanPreview = nil

        guard isVideoSplitSelected else {
            videoSplitPlanningState = .inactive
            return
        }
        guard videoSplitRuntimeAvailable,
            let videoSplitProbe,
            videoSplitCoordinator != nil
        else {
            videoSplitPlanningState = .blocked(.runtimeUnavailable)
            return
        }

        let limits: VideoSplitCustomLimits
        let canonicalLimits = canonicalVideoSplitLimitTexts
        do {
            limits = try VideoSplitCustomLimits.parse(
                maximumMegabytes: canonicalLimits.megabytes,
                maximumDurationSeconds: canonicalLimits.seconds
            )
        } catch let error as VideoSplitCustomLimitError {
            videoSplitPlanningState = .blocked(Self.issue(for: error))
            return
        } catch {
            videoSplitPlanningState = .blocked(.planningFailed)
            return
        }

        let inputs = videoInputsForSplit
        guard !inputs.isEmpty else {
            videoSplitPlanningState = .blocked(.unsupportedSource)
            return
        }
        let fingerprint = VideoSplitPlanningFingerprint(inputs: inputs, limits: limits)
        let token = UUID()
        let intent = VideoSplitIntent(
            source: .custom,
            mode: .fastKeyframeCopy,
            constraints: limits.constraints,
            stripMetadata: preferences.stripMetadataByDefault
        )
        let debounce = videoSplitPlanningDebounce
        let planBuilder = videoSplitPlanBuilder
        videoSplitPlanningToken = token
        videoSplitPlanningState = .planning

        videoSplitPlanningTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if debounce > .zero {
                    try await Task.sleep(for: debounce)
                }
                var items: [VideoSplitBatchItem] = []
                items.reserveCapacity(inputs.count)
                for input in inputs {
                    try Task.checkCancellation()
                    let source = try await videoSplitProbe.probe(input.file)
                    guard Self.isAuditedFastSplitSource(source) else {
                        await self?.finishVideoSplitPlanning(
                            token: token,
                            fingerprint: fingerprint,
                            outcome: .failure(.unsupportedSource)
                        )
                        return
                    }
                    let plan = try planBuilder.makePlan(
                        input: input.file,
                        intent: intent,
                        source: source,
                        inputRelativePath: input.relativePath
                    )
                    items.append(VideoSplitBatchItem(input: input, plan: plan))
                }
                try Task.checkCancellation()
                await self?.finishVideoSplitPlanning(
                    token: token,
                    fingerprint: fingerprint,
                    outcome: .success(items)
                )
            } catch is CancellationError {
                return
            } catch let error as VideoSplitProbeError {
                await self?.finishVideoSplitPlanning(
                    token: token,
                    fingerprint: fingerprint,
                    outcome: .failure(Self.issue(for: error))
                )
            } catch let error as VideoSplitPlanningError {
                await self?.finishVideoSplitPlanning(
                    token: token,
                    fingerprint: fingerprint,
                    outcome: .failure(Self.issue(for: error))
                )
            } catch {
                await self?.finishVideoSplitPlanning(
                    token: token,
                    fingerprint: fingerprint,
                    outcome: .failure(.planningFailed)
                )
            }
        }
    }

    private func finishVideoSplitPlanning(
        token: UUID,
        fingerprint: VideoSplitPlanningFingerprint,
        outcome: VideoSplitPlanningOutcome
    ) {
        guard videoSplitPlanningToken == token,
            isVideoSplitSelected,
            makeVideoSplitPlanningFingerprint() == fingerprint
        else { return }
        videoSplitPlanningTask = nil
        videoSplitPlanningToken = nil

        switch outcome {
        case .success(let items):
            let preview = VideoSplitBatchPlanPreview(
                items: items,
                runtimeAvailable: videoSplitRuntimeAvailable
            )
            guard preview.isExecutionAvailable else {
                videoSplitPlanningState = .blocked(.runtimeUnavailable)
                return
            }
            plannedVideoSplitItems = items
            videoSplitPlanFingerprint = fingerprint
            videoSplitPlanPreview = preview
            videoSplitPlanningState = .ready
        case .failure(let issue):
            plannedVideoSplitItems = []
            videoSplitPlanFingerprint = nil
            videoSplitPlanPreview = nil
            videoSplitPlanningState = .blocked(issue)
        }
    }

    nonisolated private static func isAuditedFastSplitSource(
        _ source: VideoSplitSourceFacts
    ) -> Bool {
        ["mp4", "mov", "quicktime"].contains(source.container.lowercased())
            && source.videoCodec == "h264"
            && (source.audioCodec == nil || source.audioCodec == "aac")
    }

    nonisolated private static func issue(
        for error: VideoSplitCustomLimitError
    ) -> IslandVideoSplitIssue {
        switch error {
        case .missingLimits: .enterAtLeastOneLimit
        case .invalidMaximumMegabytes: .invalidMaximumMegabytes
        case .invalidMaximumDuration: .invalidMaximumDuration
        }
    }

    nonisolated private static func issue(
        for error: VideoSplitProbeError
    ) -> IslandVideoSplitIssue {
        switch error {
        case .fileChangedDuringProbe, .inputIdentityMismatch:
            .sourceChanged
        case .unsupportedMedia, .invalidMediaIdentity:
            .unsupportedSource
        case .probeUnavailable:
            .runtimeUnavailable
        default:
            .planningFailed
        }
    }

    nonisolated private static func issue(
        for error: VideoSplitPlanningError
    ) -> IslandVideoSplitIssue {
        switch error {
        case .keyframeSpacingUnreachable, .splitTargetUnreachable:
            .keyframesTooFarApart
        case .unsupportedInput, .requiredMediaIncompatible:
            .unsupportedSource
        case .invalidProbe(.fileChangedDuringProbe),
            .invalidProbe(.inputIdentityMismatch):
            .sourceChanged
        default:
            .planningFailed
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

        guard
            let selection = await outputDirectorySelector.selectDirectory(
                suggestedDirectory: suggestedDirectory
            )
        else { return nil }
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
