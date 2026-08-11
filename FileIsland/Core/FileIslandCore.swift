import Foundation

struct FileIslandCore: FileIslandCoreServing, Sendable {
    let fileInspector: any FileInspecting
    let inputScanner: any InputScanning
    let conversionEngine: any ConversionEngine
    let batchCoordinator: any BatchJobCoordinating
    let capabilityResolver: ConversionCapabilityResolver
    let presetCatalogLoader: any PresetCatalogLoading
    let presetResolver: ConversionPresetResolver
    let batchRequestBuilder: BatchRequestBuilder
    let videoSplitProbe: (any VideoSplitProbing)?
    let videoSplitCoordinator: (any VideoSplitJobCoordinating)?
    let videoSplitPlanBuilder: VideoSplitPlanBuilder
    private let operationRegistry = FileIslandCoreOperationRegistry()

    init(
        fileInspector: any FileInspecting,
        inputScanner: any InputScanning,
        conversionEngine: any ConversionEngine,
        batchCoordinator: any BatchJobCoordinating,
        capabilityResolver: ConversionCapabilityResolver = ConversionCapabilityResolver(),
        presetCatalogLoader: any PresetCatalogLoading,
        presetResolver: ConversionPresetResolver = ConversionPresetResolver(),
        batchRequestBuilder: BatchRequestBuilder = BatchRequestBuilder(),
        videoSplitProbe: (any VideoSplitProbing)? = nil,
        videoSplitCoordinator: (any VideoSplitJobCoordinating)? = nil,
        videoSplitPlanBuilder: VideoSplitPlanBuilder = VideoSplitPlanBuilder()
    ) {
        self.fileInspector = fileInspector
        self.inputScanner = inputScanner
        self.conversionEngine = conversionEngine
        self.batchCoordinator = batchCoordinator
        self.capabilityResolver = capabilityResolver
        self.presetCatalogLoader = presetCatalogLoader
        self.presetResolver = presetResolver
        self.batchRequestBuilder = batchRequestBuilder
        self.videoSplitProbe = videoSplitProbe
        self.videoSplitCoordinator = videoSplitCoordinator
        self.videoSplitPlanBuilder = videoSplitPlanBuilder
    }

    static func live(
        presetResourceURL: URL? = Bundle.main.url(
            forResource: "built-in-presets",
            withExtension: "json"
        ),
        ffmpegExecutableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
        ffprobeExecutableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "ffprobe"),
        mediaValidatorExecutableURL: URL? = Bundle.main.url(
            forAuxiliaryExecutable: "FileIslandMediaValidator"
        )
    ) -> FileIslandCore {
        let inspector = URLFileInspector()
        let engine = ConversionEngineRouter(
            engines: [
                ImageConversionEngine(),
                NativeVideoConversionEngine(),
                FFmpegConversionEngine(executableURL: ffmpegExecutableURL),
                FFmpegAudioConversionEngine(executableURL: ffmpegExecutableURL)
            ]
        )
        let splitProbe = ffprobeExecutableURL.map { FFprobeVideoSplitProbe(executableURL: $0) }
        let splitCoordinator: (any VideoSplitJobCoordinating)?
        if let splitProbe,
           let ffmpegExecutableURL,
           let mediaValidatorExecutableURL {
            splitCoordinator = VideoSplitJobCoordinator(
                probe: splitProbe,
                engine: FFmpegVideoSplitEngine(executableURL: ffmpegExecutableURL),
                outputValidator: VideoSplitOutputValidator(
                    probe: splitProbe,
                    decodabilityChecker:
                        AVFoundationVideoSplitSegmentDecodabilityChecker(
                            helperExecutableURL: mediaValidatorExecutableURL
                        )
                )
            )
        } else {
            splitCoordinator = nil
        }
        return FileIslandCore(
            fileInspector: inspector,
            inputScanner: URLInputScanner(fileInspector: inspector),
            conversionEngine: engine,
            batchCoordinator: BatchJobCoordinator(conversionEngine: engine),
            presetCatalogLoader: BundledPresetCatalogLoader(resourceURL: presetResourceURL),
            videoSplitProbe: splitProbe,
            videoSplitCoordinator: splitCoordinator
        )
    }

    func capabilities() async throws -> CoreCapabilities {
        let presets = try await presetCatalogLoader.loadPresets()
        let splitCapabilities: CoreVideoSplitCapabilities?
        if videoSplitProbe != nil, videoSplitCoordinator != nil {
            splitCapabilities = CoreVideoSplitCapabilities(
                constraintSources: ["custom"],
                // This is a public CLI wire token, not the Swift enum raw value.
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
        } else {
            splitCapabilities = nil
        }
        return CoreCapabilities(
            schemaVersion: 1,
            image: CoreMediaCapabilities(
                inputFormats: normalized(MediaConversionMatrix.imageInputFormats),
                outputFormats: MediaConversionMatrix.imageOutputFormats(
                    for: Array(MediaConversionMatrix.imageInputFormats)
                ).map { Self.normalized($0.rawValue) }.sorted()
            ),
            video: CoreVideoCapabilities(
                nativeInputFormats: normalized(MediaConversionMatrix.nativeVideoInputFormats),
                fallbackInputFormats: normalized(MediaConversionMatrix.fallbackVideoInputFormats),
                outputContainer: "mp4",
                resolutions: ["source", "1080p", "720p"],
                nativeSupportsTargetBytes: true,
                fallbackSupportsTargetBytes: false
            ),
            audio: CoreMediaCapabilities(
                inputFormats: normalized(MediaConversionMatrix.audioInputFormats),
                outputFormats: MediaConversionMatrix.audioOutputFormats.map(\.rawValue)
            ),
            presets: presets.map {
                CorePreset(
                    id: $0.id,
                    displayName: $0.displayName,
                    summary: $0.summary,
                    mediaType: $0.mediaType.rawValue
                )
            },
            videoSplit: splitCapabilities
        )
    }

    func inspect(paths: [URL], recursive: Bool) async throws -> CoreInspection {
        let scan = try await scan(paths: paths, recursive: recursive)
        return CoreInspection(
            schemaVersion: 1,
            files: scan.inputs.map {
                CoreInspectedFile(
                    displayName: $0.file.displayName,
                    mediaKind: $0.file.kind.rawValue,
                    format: Self.normalized($0.file.format.rawValue),
                    byteCount: $0.file.fileSize,
                    relativePath: $0.relativePath.string
                )
            }
        )
    }

    func convert(
        _ request: CoreConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> CoreConversionResult {
        let token = try operationRegistry.reserve(requestID: request.id)
        let execution = Task {
            try await performConversion(request, progress: progress)
        }
        operationRegistry.attach(
            requestID: request.id,
            token: token,
            cancellation: { execution.cancel() }
        )
        defer {
            operationRegistry.finish(requestID: request.id, token: token)
        }
        return try await withTaskCancellationHandler {
            try await execution.value
        } onCancel: {
            operationRegistry.cancel(requestID: request.id)
        }
    }

    private func performConversion(
        _ request: CoreConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> CoreConversionResult {
        guard request.imageIntent == nil || request.imagePresetID == nil,
              request.videoIntent == nil || request.videoPresetID == nil else {
            throw FileIslandCoreError.conflictingConfiguration
        }
        let scan = try await scan(paths: request.paths, recursive: request.recursive)
        try Task.checkCancellation()
        let presets = try await presetCatalogLoader.loadPresets()
        try Task.checkCancellation()
        let imageFiles = inputs(.image, scan: scan).map(\.file)
        let nativeVideoFiles = inputs(.nativeVideo, scan: scan).map(\.file)
        let fallbackVideoFiles = inputs(.fallbackVideo, scan: scan).map(\.file)
        let audioFiles = inputs(.audio, scan: scan).map(\.file)

        let imageIntent = try resolvedImageIntent(
            explicit: request.imageIntent,
            presetID: request.imagePresetID,
            files: imageFiles,
            presets: presets
        )
        let videoIntent = try resolvedVideoIntent(
            explicit: request.videoIntent,
            presetID: request.videoPresetID,
            nativeFiles: nativeVideoFiles,
            fallbackFiles: fallbackVideoFiles,
            presets: presets
        )

        if !imageFiles.isEmpty, imageIntent == nil {
            throw FileIslandCoreError.missingImageConfiguration
        }
        if !nativeVideoFiles.isEmpty || !fallbackVideoFiles.isEmpty, videoIntent == nil {
            throw FileIslandCoreError.missingVideoConfiguration
        }
        if !audioFiles.isEmpty, request.audioIntent == nil {
            throw FileIslandCoreError.missingAudioConfiguration
        }
        guard !imageFiles.isEmpty || !nativeVideoFiles.isEmpty
                || !fallbackVideoFiles.isEmpty || !audioFiles.isEmpty else {
            throw FileIslandCoreError.unsupportedInput
        }

        let batch = try batchRequestBuilder.makeRequest(
            id: request.id,
            scan: scan,
            imageIntent: imageIntent,
            videoIntent: videoIntent,
            audioIntent: request.audioIntent,
            outputDirectory: request.outputDirectory
        )
        guard batch.processCount > 0 else { throw FileIslandCoreError.unsupportedInput }
        try Task.checkCancellation()
        let coordinator = batchCoordinator
        let result = try await withTaskCancellationHandler {
            try await coordinator.execute(batch, progress: progress)
        } onCancel: {
            Task { await coordinator.cancel(requestID: batch.id) }
        }
        return CoreConversionResult(
            requestID: batch.id,
            outputURLs: result.outputURLs,
            skippedCount: result.skippedCount,
            failClosedCount: result.failClosedCount
        )
    }

    func cancel(requestID: UUID) async {
        operationRegistry.cancel(requestID: requestID)
        await batchCoordinator.cancel(requestID: requestID)
        await videoSplitCoordinator?.cancel(requestID: requestID)
    }

    func split(
        _ request: CoreVideoSplitRequest,
        event: @Sendable @escaping (CoreVideoSplitEvent) -> Void
    ) async throws -> CoreVideoSplitResult {
        let token = try operationRegistry.reserve(requestID: request.id)
        let execution = Task {
            try await performSplit(request, event: event)
        }
        operationRegistry.attach(
            requestID: request.id,
            token: token,
            cancellation: { execution.cancel() }
        )
        defer {
            operationRegistry.finish(requestID: request.id, token: token)
        }
        return try await withTaskCancellationHandler {
            try await execution.value
        } onCancel: {
            operationRegistry.cancel(requestID: request.id)
        }
    }

    private func performSplit(
        _ request: CoreVideoSplitRequest,
        event: @Sendable @escaping (CoreVideoSplitEvent) -> Void
    ) async throws -> CoreVideoSplitResult {
        guard request.mode == .fastKeyframeCopy,
              request.maxBytes.map({ $0 > 0 }) ?? true,
              request.maxDurationMilliseconds.map({ $0 > 0 }) ?? true,
              request.maxBytes != nil || request.maxDurationMilliseconds != nil else {
            throw FileIslandCoreError.invalidSplitConfiguration
        }
        guard let videoSplitProbe, let videoSplitCoordinator else {
            throw FileIslandCoreError.splitRuntimeUnavailable
        }

        let scan = try await scan(paths: request.paths, recursive: request.recursive)
        try Task.checkCancellation()
        let videoInputs = scan.inputs.filter { $0.file.kind == .video }
        // The split result has no skipped/fail-closed channel. Accepting a
        // mixed request would therefore make automation report success while
        // silently ignoring explicit inputs. Keep the contract fail-closed
        // until partial-split results are modeled deliberately.
        guard !videoInputs.isEmpty,
              videoInputs.count == scan.inputs.count else {
            throw FileIslandCoreError.unsupportedInput
        }

        let intent = VideoSplitIntent(
            source: .custom,
            mode: .fastKeyframeCopy,
            constraints: VideoSegmentConstraints(
                maxBytes: request.maxBytes,
                maxDurationMilliseconds: request.maxDurationMilliseconds,
                safetyRatio: 0.95,
                requiredContainer: nil,
                requiredVideoCodec: nil,
                requiredAudioCodec: nil
            ),
            stripMetadata: request.stripMetadata
        )
        var items: [VideoSplitBatchItem] = []
        items.reserveCapacity(videoInputs.count)
        for (offset, input) in videoInputs.enumerated() {
            try Task.checkCancellation()
            let facts = try await videoSplitProbe.probe(input.file)
            try Task.checkCancellation()
            guard Self.isAuditedFastSplitSource(facts) else {
                throw FileIslandCoreError.unsupportedInput
            }
            let plan = try videoSplitPlanBuilder.makePlan(
                input: input.file,
                intent: intent,
                source: facts,
                inputRelativePath: input.relativePath
            )
            items.append(VideoSplitBatchItem(input: input, plan: plan))
            event(
                .plan(
                    CoreVideoSplitPlanEvent(
                        requestID: request.id,
                        inputOrdinal: offset + 1,
                        totalInputs: videoInputs.count,
                        displayName: input.file.displayName,
                        segmentRelativePaths: plan.segments.map(\.outputRelativePath)
                    )
                )
            )
        }

        let batch = VideoSplitBatchRequest(
            id: request.id,
            selections: scan.selections,
            outputDirectory: request.outputDirectory,
            items: items
        )
        try Task.checkCancellation()
        let result: VideoSplitBatchResult
        do {
            result = try await withTaskCancellationHandler {
                try await videoSplitCoordinator.execute(batch, event: { coordinatorEvent in
                    switch coordinatorEvent {
                    case let .progress(progress):
                        event(.segment(progress))
                    case let .validationCompleted(requestID, segmentCount):
                        event(
                            .validation(
                                CoreVideoSplitValidationEvent(
                                    requestID: requestID,
                                    segmentCount: segmentCount
                                )
                            )
                        )
                    case let .publicationCompleted(requestID, outputURLs):
                        event(
                            .publication(
                                CoreVideoSplitPublicationEvent(
                                    requestID: requestID,
                                    outputURLs: outputURLs
                                )
                            )
                        )
                    }
                })
            } onCancel: {
                Task { await videoSplitCoordinator.cancel(requestID: request.id) }
            }
        } catch {
            event(.rollback(requestID: request.id))
            throw error
        }
        return CoreVideoSplitResult(
            requestID: result.requestID,
            outputURLs: result.outputURLs,
            segmentCount: result.segmentCount,
            totalBytes: result.totalBytes
        )
    }

    private func scan(paths: [URL], recursive: Bool) async throws -> InputScanResult {
        try Task.checkCancellation()
        if !recursive, try containsDirectory(paths) {
            throw FileIslandCoreError.recursiveRequired
        }
        try Task.checkCancellation()
        let result = try await inputScanner.scan(urls: paths)
        try Task.checkCancellation()
        return result
    }

    private func containsDirectory(_ paths: [URL]) throws -> Bool {
        for path in paths {
            try Task.checkCancellation()
            if (try? path.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return true
            }
        }
        return false
    }

    private func resolvedImageIntent(
        explicit: ImageIntent?,
        presetID: String?,
        files: [InputFile],
        presets: [ConversionPreset]
    ) throws -> ImageIntent? {
        if let explicit { return explicit }
        guard let presetID, !files.isEmpty else { return nil }
        let recommendations = presetResolver.recommendations(
            for: files,
            capability: capabilityResolver.resolve(files),
            presets: presets
        )
        guard let recommendation = recommendations.first(where: { $0.preset.id == presetID }),
              case let .convertImage(intent) = recommendation.intent else {
            throw FileIslandCoreError.presetNotApplicable(presetID)
        }
        return intent
    }

    private func resolvedVideoIntent(
        explicit: VideoIntent?,
        presetID: String?,
        nativeFiles: [InputFile],
        fallbackFiles: [InputFile],
        presets: [ConversionPreset]
    ) throws -> VideoIntent? {
        if let explicit { return explicit }
        let files = nativeFiles + fallbackFiles
        guard let presetID, !files.isEmpty else { return nil }
        let capability: ConversionCapability = .video(
            availableResolutions: [.source, .p1080, .p720],
            supportsTargetSize: fallbackFiles.isEmpty
        )
        let recommendations = presetResolver.recommendations(
            for: files,
            capability: capability,
            presets: presets
        )
        guard let recommendation = recommendations.first(where: { $0.preset.id == presetID }),
              case let .convertVideo(intent) = recommendation.intent else {
            throw FileIslandCoreError.presetNotApplicable(presetID)
        }
        return intent
    }

    private func inputs(_ kind: ConversionGroupKind, scan: InputScanResult) -> [BatchInput] {
        scan.inputs.filter { input in
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

    private func normalized(_ formats: Set<InputFileFormat>) -> [String] {
        formats.map { Self.normalized($0.rawValue) }.sorted()
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
    }

    private static func isAuditedFastSplitSource(
        _ source: VideoSplitSourceFacts
    ) -> Bool {
        ["mp4", "mov", "quicktime"].contains(source.container.lowercased())
            && source.videoCodec == "h264"
            && (source.audioCodec == nil || source.audioCodec == "aac")
    }
}

enum FileIslandCoreOperationError: Error, Equatable, Sendable {
    case requestAlreadyActive
}

private final class FileIslandCoreOperationRegistry: @unchecked Sendable {
    struct Token: Hashable, Sendable {
        fileprivate let value = UUID()
    }

    private struct Entry {
        let token: Token
        var cancellation: (@Sendable () -> Void)?
        var cancellationRequested: Bool
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    func reserve(requestID: UUID) throws -> Token {
        try lock.withLock {
            guard entries[requestID] == nil else {
                throw FileIslandCoreOperationError.requestAlreadyActive
            }
            let token = Token()
            entries[requestID] = Entry(
                token: token,
                cancellation: nil,
                cancellationRequested: false
            )
            return token
        }
    }

    func attach(
        requestID: UUID,
        token: Token,
        cancellation: @escaping @Sendable () -> Void
    ) {
        let cancelImmediately = lock.withLock {
            guard var entry = entries[requestID], entry.token == token else {
                return false
            }
            entry.cancellation = cancellation
            entries[requestID] = entry
            return entry.cancellationRequested
        }
        if cancelImmediately { cancellation() }
    }

    func cancel(requestID: UUID) {
        let cancellation: (@Sendable () -> Void)? = lock.withLock {
            guard var entry = entries[requestID] else { return nil }
            entry.cancellationRequested = true
            entries[requestID] = entry
            return entry.cancellation
        }
        cancellation?()
    }

    func finish(requestID: UUID, token: Token) {
        lock.withLock {
            guard entries[requestID]?.token == token else { return }
            entries.removeValue(forKey: requestID)
        }
    }
}
