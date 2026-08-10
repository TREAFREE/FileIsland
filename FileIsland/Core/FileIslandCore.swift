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

    init(
        fileInspector: any FileInspecting,
        inputScanner: any InputScanning,
        conversionEngine: any ConversionEngine,
        batchCoordinator: any BatchJobCoordinating,
        capabilityResolver: ConversionCapabilityResolver = ConversionCapabilityResolver(),
        presetCatalogLoader: any PresetCatalogLoading,
        presetResolver: ConversionPresetResolver = ConversionPresetResolver(),
        batchRequestBuilder: BatchRequestBuilder = BatchRequestBuilder()
    ) {
        self.fileInspector = fileInspector
        self.inputScanner = inputScanner
        self.conversionEngine = conversionEngine
        self.batchCoordinator = batchCoordinator
        self.capabilityResolver = capabilityResolver
        self.presetCatalogLoader = presetCatalogLoader
        self.presetResolver = presetResolver
        self.batchRequestBuilder = batchRequestBuilder
    }

    static func live(
        presetResourceURL: URL? = Bundle.main.url(
            forResource: "built-in-presets",
            withExtension: "json"
        ),
        ffmpegExecutableURL: URL? = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")
    ) -> FileIslandCore {
        let inspector = URLFileInspector()
        let engine = ConversionEngineRouter(
            engines: [
                ImageConversionEngine(),
                NativeVideoConversionEngine(),
                FFmpegConversionEngine(executableURL: ffmpegExecutableURL)
            ]
        )
        return FileIslandCore(
            fileInspector: inspector,
            inputScanner: URLInputScanner(fileInspector: inspector),
            conversionEngine: engine,
            batchCoordinator: BatchJobCoordinator(conversionEngine: engine),
            presetCatalogLoader: BundledPresetCatalogLoader(resourceURL: presetResourceURL)
        )
    }

    func capabilities() async throws -> CoreCapabilities {
        let presets = try await presetCatalogLoader.loadPresets()
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
            presets: presets.map {
                CorePreset(
                    id: $0.id,
                    displayName: $0.displayName,
                    summary: $0.summary,
                    mediaType: $0.mediaType.rawValue
                )
            }
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
        guard request.imageIntent == nil || request.imagePresetID == nil,
              request.videoIntent == nil || request.videoPresetID == nil else {
            throw FileIslandCoreError.conflictingConfiguration
        }
        let scan = try await scan(paths: request.paths, recursive: request.recursive)
        let presets = try await presetCatalogLoader.loadPresets()
        let imageFiles = inputs(.image, scan: scan).map(\.file)
        let nativeVideoFiles = inputs(.nativeVideo, scan: scan).map(\.file)
        let fallbackVideoFiles = inputs(.fallbackVideo, scan: scan).map(\.file)

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
        guard !imageFiles.isEmpty || !nativeVideoFiles.isEmpty || !fallbackVideoFiles.isEmpty else {
            throw FileIslandCoreError.unsupportedInput
        }

        let batch = try batchRequestBuilder.makeRequest(
            id: request.id,
            scan: scan,
            imageIntent: imageIntent,
            videoIntent: videoIntent,
            outputDirectory: request.outputDirectory
        )
        guard batch.processCount > 0 else { throw FileIslandCoreError.unsupportedInput }
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
        await batchCoordinator.cancel(requestID: requestID)
    }

    private func scan(paths: [URL], recursive: Bool) async throws -> InputScanResult {
        guard recursive || !containsDirectory(paths) else {
            throw FileIslandCoreError.recursiveRequired
        }
        return try await inputScanner.scan(urls: paths)
    }

    private func containsDirectory(_ paths: [URL]) -> Bool {
        paths.contains {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
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
            case .unsupported:
                !MediaConversionMatrix.imageInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.nativeVideoInputFormats.contains(input.file.format)
                    && !MediaConversionMatrix.fallbackVideoInputFormats.contains(input.file.format)
            }
        }
    }

    private func normalized(_ formats: Set<InputFileFormat>) -> [String] {
        formats.map { Self.normalized($0.rawValue) }.sorted()
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
    }
}
