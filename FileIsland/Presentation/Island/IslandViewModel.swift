import Foundation
import Observation

@MainActor
@Observable
final class IslandViewModel {
    private(set) var state: IslandState = .idle
    private(set) var presentationMode: IslandPresentationMode = .floatingPill
    private(set) var notchOcclusionHeight: CGFloat = 0

    @ObservationIgnored
    private let fileInspector: any FileInspecting

    @ObservationIgnored
    private let conversionEngine: any ConversionEngine

    @ObservationIgnored
    private let outputDirectorySelector: any OutputDirectorySelecting

    @ObservationIgnored
    private let imagePlanBuilder: ImageConversionPlanBuilder

    @ObservationIgnored
    private var inspectionTask: Task<Void, Never>?

    @ObservationIgnored
    private var conversionTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var activePlanID: UUID?

    private(set) var imageIntent: ImageIntent?
    private(set) var activeFiles: [InputFile] = []

    @ObservationIgnored
    private var stateBeforeDrag: IslandState?

    @ObservationIgnored
    var onLayoutModeChange: ((IslandLayoutMode) -> Void)?

    init(
        fileInspector: any FileInspecting,
        conversionEngine: any ConversionEngine = ImageConversionEngine(),
        outputDirectorySelector: any OutputDirectorySelecting = AppKitOutputDirectorySelector(),
        imagePlanBuilder: ImageConversionPlanBuilder = ImageConversionPlanBuilder()
    ) {
        self.fileInspector = fileInspector
        self.conversionEngine = conversionEngine
        self.outputDirectorySelector = outputDirectorySelector
        self.imagePlanBuilder = imagePlanBuilder
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

        inspectionTask = Task { [weak self, fileInspector] in
            do {
                let files = try await fileInspector.inspect(urls: urls)
                guard !Task.isCancelled else { return }
                self?.finishInspection(requestID: requestID, result: .success(files))
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishInspection(requestID: requestID, result: .failure(error))
            }
        }
    }

    func reset() {
        inspectionTask?.cancel()
        conversionTask?.cancel()
        if let activePlanID {
            Task { [conversionEngine] in await conversionEngine.cancel(jobID: activePlanID) }
        }
        activeRequestID = nil
        activePlanID = nil
        activeFiles = []
        imageIntent = nil
        stateBeforeDrag = nil
        setState(.idle)
    }

    var availableOutputFormats: [ImageOutputFormat] {
        [ImageOutputFormat.jpeg, .png].filter { format in
            !activeFiles.isEmpty && activeFiles.allSatisfy { format.canConvert($0.format) }
        }
    }

    func canConfigureImageConversion(for files: [InputFile]) -> Bool {
        [ImageOutputFormat.jpeg, .png].contains { format in
            !files.isEmpty && files.allSatisfy { format.canConvert($0.format) }
        }
    }

    var acceptsFileDrops: Bool {
        switch state {
        case .preparing, .converting:
            false
        default:
            true
        }
    }

    func continueToImageActions() {
        guard case let .droppedSummary(files) = state else { return }
        let formats = [ImageOutputFormat.jpeg, .png].filter { format in
            files.allSatisfy { format.canConvert($0.format) }
        }
        guard let defaultFormat = formats.first else {
            setState(.failure(Self.unsupportedImageError))
            return
        }

        activeFiles = files
        imageIntent = ImageIntent(
            outputFormat: defaultFormat,
            maxPixelDimension: nil,
            targetBytes: nil,
            qualityPreference: .balanced,
            stripMetadata: true
        )
        setState(.actionSelection(files))
    }

    func selectOutputFormat(_ format: ImageOutputFormat) {
        guard availableOutputFormats.contains(format) else { return }
        imageIntent?.outputFormat = format
    }

    func selectMaximumDimension(_ dimension: Int?) {
        guard dimension.map({ $0 > 0 }) ?? true else { return }
        imageIntent?.maxPixelDimension = dimension
    }

    func selectQuality(_ quality: QualityPreference) {
        imageIntent?.qualityPreference = quality
    }

    func setStripMetadata(_ stripMetadata: Bool) {
        imageIntent?.stripMetadata = stripMetadata
    }

    func returnToSummary() {
        guard !activeFiles.isEmpty else { return }
        imageIntent = nil
        setState(.droppedSummary(activeFiles))
    }

    func startConversion() {
        guard case .actionSelection = state,
              let intent = imageIntent,
              !activeFiles.isEmpty else { return }

        conversionTask?.cancel()
        conversionTask = Task { [weak self] in
            await self?.performConversion(intent: intent)
        }
    }

    func cancelConversion() {
        guard let planID = activePlanID else { return }
        activePlanID = nil
        conversionTask?.cancel()
        conversionTask = nil
        Task { [conversionEngine] in await conversionEngine.cancel(jobID: planID) }
        setState(.actionSelection(activeFiles))
    }

    func updatePresentation(
        mode: IslandPresentationMode,
        notchOcclusionHeight: CGFloat
    ) {
        presentationMode = mode
        self.notchOcclusionHeight = notchOcclusionHeight
    }

    private func finishInspection(
        requestID: UUID,
        result: Result<[InputFile], Error>
    ) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil

        switch result {
        case let .success(files):
            setState(.droppedSummary(files))
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

    private func performConversion(intent: ImageIntent) async {
        let suggestedDirectory = activeFiles.first?.url.deletingLastPathComponent()
        guard let outputSelection = await outputDirectorySelector.selectDirectory(
            suggestedDirectory: suggestedDirectory
        ), !Task.isCancelled else {
            return
        }
        defer {
            if outputSelection.didStartAccessingSecurityScope {
                outputSelection.url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let plan = try imagePlanBuilder.makePlan(
                inputs: activeFiles,
                intent: intent,
                outputDirectory: outputSelection.url
            )
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
                                actionLabel: "Converting…",
                                progress: progress,
                                isEstimated: false,
                                currentFile: currentFile,
                                totalFiles: totalFiles,
                                inputBytes: totalInputBytes,
                                estimatedOutputBytes: nil
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
        } catch let error as ConversionError {
            guard activePlanID != nil else { return }
            activePlanID = nil
            conversionTask = nil
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

    private static let unsupportedImageError = UserFacingError(
        title: "This conversion isn’t available yet",
        message: "Task 003 supports HEIC or PNG to JPEG, and JPEG to PNG."
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
                title: "This image couldn’t be decoded",
                message: "The file may be damaged or use unsupported image data."
            )
        case .unsupportedInput, .unsupportedOutput, .targetSizeUnreachable:
            unsupportedImageError
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
        if previousLayout != newState.layoutMode {
            onLayoutModeChange?(newState.layoutMode)
        }
    }
}
