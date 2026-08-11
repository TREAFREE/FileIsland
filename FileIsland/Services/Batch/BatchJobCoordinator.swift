import Foundation

protocol BatchOutputArtifactPublishing: Sendable {
    func publish(
        _ manifest: ValidatedOutputArtifactManifest,
        to outputRoot: URL,
        protectedURLs: Set<URL>,
        collisionPolicy: OutputArtifactCollisionPolicy,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> [PublishedOutputArtifact]
}

extension OutputArtifactPublisher: BatchOutputArtifactPublishing {}

actor BatchJobCoordinator: BatchJobCoordinating {
    private let conversionEngine: any ConversionEngine
    private let artifactValidator: OutputArtifactManifestValidator
    private let artifactPublisher: any BatchOutputArtifactPublishing
    private let fileManager: FileManager
    private nonisolated let cancellationRegistry = BatchCancellationRegistry()
    private var activeRequestID: UUID?
    private var activePlanID: UUID?
    private var cancelledRequestIDs: Set<UUID> = []

    init(
        conversionEngine: any ConversionEngine,
        artifactValidator: OutputArtifactManifestValidator = OutputArtifactManifestValidator(),
        artifactPublisher: any BatchOutputArtifactPublishing = OutputArtifactPublisher(),
        fileManager: FileManager = .default
    ) {
        self.conversionEngine = conversionEngine
        self.artifactValidator = artifactValidator
        self.artifactPublisher = artifactPublisher
        self.fileManager = fileManager
    }

    func execute(
        _ request: BatchConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> BatchResult {
        guard activeRequestID == nil else { throw ConversionError.engineUnavailable }
        guard Self.isExistingDirectory(request.outputDirectory) else {
            throw ConversionError.permissionDenied
        }
        activeRequestID = request.id
        cancelledRequestIDs.remove(request.id)
        cancellationRegistry.begin(request.id)
        defer {
            activeRequestID = nil
            activePlanID = nil
            cancelledRequestIDs.remove(request.id)
            cancellationRegistry.finish(request.id)
        }

        let securityScopedURLs = Self.uniqueSecurityScopeURLs(for: request)
        let acquiredScopes = securityScopedURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer { acquiredScopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        guard request.processCount > 0 else {
            progress(
                BatchProgress(
                    requestID: request.id,
                    fraction: 1,
                    currentFile: 0,
                    totalFiles: 0,
                    currentDisplayName: nil
                )
            )
            return BatchResult(
                outputURLs: [],
                skippedCount: request.skippedCount,
                failClosedCount: request.failClosedCount
            )
        }

        let stagingRoot = request.outputDirectory.appendingPathComponent(
            ".fileisland-\(request.id.uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        var plannedArtifacts: [PlannedOutputArtifact] = []
        var stagedArtifacts: [StagedOutputArtifact] = []
        let reporter = BatchProgressReporter(
            requestID: request.id,
            totalFiles: request.processCount,
            callback: progress
        )

        do {
            var completedFiles = 0
            for (groupIndex, group) in request.executableGroups.enumerated() {
                try checkCancellation(request.id)
                guard let plan = group.plan else { continue }
                let groupDirectory = stagingRoot.appendingPathComponent(
                    "group-\(groupIndex)",
                    isDirectory: true
                )
                try fileManager.createDirectory(
                    at: groupDirectory,
                    withIntermediateDirectories: false
                )
                let stagingPlan = ConversionPlan(
                    id: plan.id,
                    inputs: plan.inputs,
                    steps: plan.steps,
                    outputPolicy: .chosenDirectory(groupDirectory, suffix: ""),
                    estimatedOutput: plan.estimatedOutput
                )
                activePlanID = stagingPlan.id
                let base = completedFiles
                let count = stagingPlan.inputs.count
                let result = try await conversionEngine.execute(stagingPlan) { localProgress in
                    Task {
                        await reporter.reportConversion(
                            completedBeforeGroup: base,
                            groupInputs: stagingPlan.inputs,
                            localProgress: localProgress
                        )
                    }
                }
                activePlanID = nil
                try checkCancellation(request.id)
                let groupManifest = try makeConversionManifest(
                    plan: stagingPlan,
                    batchInputs: group.inputs
                )
                _ = try artifactValidator.validate(
                    plannedArtifacts: groupManifest,
                    stagedArtifacts: result.artifacts,
                    allowedSourceInputIDs: Set(stagingPlan.inputs.map(\.id)),
                    stagingRoot: groupDirectory
                )
                plannedArtifacts.append(contentsOf: groupManifest)
                stagedArtifacts.append(contentsOf: result.artifacts)
                completedFiles += count
                await reporter.completeConversionGroup(
                    completedFiles: completedFiles,
                    displayName: stagingPlan.inputs.last?.displayName
                )
            }

            let allowedSourceInputIDs = Set(plannedArtifacts.map(\.id.sourceInputID))
            let validatedManifest = try artifactValidator.validate(
                plannedArtifacts: plannedArtifacts,
                stagedArtifacts: stagedArtifacts,
                allowedSourceInputIDs: allowedSourceInputIDs,
                stagingRoot: stagingRoot
            )
            try checkCancellation(request.id)
            let publishedArtifacts = try artifactPublisher.publish(
                validatedManifest,
                to: request.outputDirectory,
                protectedURLs: Set(request.groups.flatMap(\.inputs).map(\.file.url)),
                collisionPolicy: .rename,
                cancellationCheck: { [cancellationRegistry] in
                    try Task.checkCancellation()
                    guard !cancellationRegistry.isCancelled(request.id) else {
                        throw CancellationError()
                    }
                }
            )
            // `OutputArtifactPublisher` checks cancellation after its final move.
            // A successful return is the linearization point for publication:
            // cancellation before that gate rolls the complete journal back;
            // cancellation after it cannot turn committed output into a failure.
            cancellationRegistry.commitPublication(request.id)
            for (index, artifact) in publishedArtifacts.enumerated() {
                let displayName = request.groups
                    .flatMap(\.inputs)
                    .first(where: { $0.file.id == artifact.id.sourceInputID })?
                    .file.displayName
                await reporter.reportPublication(
                    publishedFiles: index + 1,
                    displayName: displayName
                )
            }

            try? fileManager.removeItem(at: stagingRoot)
            let lastDisplayName = request.groups
                .flatMap(\.inputs)
                .first(where: {
                    $0.file.id == publishedArtifacts.last?.id.sourceInputID
                })?
                .file.displayName
            await reporter.finish(displayName: lastDisplayName)
            return BatchResult(
                outputURLs: publishedArtifacts.map(\.fileURL),
                skippedCount: request.skippedCount,
                failClosedCount: request.failClosedCount
            )
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            if cancelledRequestIDs.contains(request.id)
                || cancellationRegistry.isCancelled(request.id)
                || Task.isCancelled {
                throw ConversionError.cancelled
            }
            if error is OutputArtifactManifestError
                || error is OutputArtifactPublisherError {
                throw ConversionError.conversionFailed(
                    underlying: "Output safety validation failed."
                )
            }
            if let conversionError = error as? ConversionError {
                throw conversionError
            }
            throw ConversionError.conversionFailed(underlying: error.localizedDescription)
        }
    }

    nonisolated func cancel(requestID: UUID) async {
        cancellationRegistry.cancel(requestID)
        await cancelActiveRequest(requestID: requestID)
    }

    private func cancelActiveRequest(requestID: UUID) async {
        guard activeRequestID == requestID,
              !cancellationRegistry.isPublicationCommitted(requestID) else {
            return
        }
        cancelledRequestIDs.insert(requestID)
        if let activePlanID {
            await conversionEngine.cancel(jobID: activePlanID)
        }
    }

    private func checkCancellation(_ requestID: UUID) throws {
        guard !cancelledRequestIDs.contains(requestID),
              !cancellationRegistry.isCancelled(requestID),
              !Task.isCancelled else {
            throw ConversionError.cancelled
        }
    }

    private func makeConversionManifest(
        plan: ConversionPlan,
        batchInputs: [BatchInput]
    ) throws -> [PlannedOutputArtifact] {
        guard let outputExtension = Self.outputExtension(for: plan) else {
            throw ConversionError.unsupportedOutput
        }
        var inputsByID: [UUID: BatchInput] = [:]
        for input in batchInputs {
            guard inputsByID.updateValue(input, forKey: input.file.id) == nil else {
                throw ConversionError.conversionFailed(
                    underlying: "Duplicate input identity in batch."
                )
            }
        }

        return try plan.inputs.map { file in
            guard let input = inputsByID[file.id] else {
                throw ConversionError.conversionFailed(
                    underlying: "A planned input was not part of its batch group."
                )
            }
            let baseName = file.url.deletingPathExtension().lastPathComponent
            let filename = "\(baseName).\(outputExtension)"
            let path = (input.relativePath.parent?.components ?? []) + [filename]
            let relativePath: SafeRelativePath
            do {
                relativePath = try SafeRelativePath(path.joined(separator: "/"))
            } catch {
                throw ConversionError.conversionFailed(
                    underlying: "The planned output path was unsafe."
                )
            }
            return PlannedOutputArtifact(
                id: OutputArtifactID(sourceInputID: file.id, role: .converted),
                preferredRelativePath: relativePath
            )
        }
    }

    private static func outputExtension(for plan: ConversionPlan) -> String? {
        guard plan.steps.count == 1 else { return nil }
        return switch plan.steps[0] {
        case let .image(intent):
            intent.outputFormat?.filenameExtension
        case .video:
            "mp4"
        case let .audio(intent):
            intent.outputFormat.filenameExtension
        }
    }

    private static func uniqueSecurityScopeURLs(
        for request: BatchConversionRequest
    ) -> [URL] {
        var seen: Set<URL> = []
        return (request.selections.map(\.url) + [request.outputDirectory]).filter {
            seen.insert($0.standardizedFileURL).inserted
        }
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

}

private final class BatchCancellationRegistry: @unchecked Sendable {
    private enum Phase {
        case active
        case cancelled
        case publicationCommitted
    }

    private let lock = NSLock()
    private var phases: [UUID: Phase] = [:]

    func begin(_ requestID: UUID) {
        lock.withLock { phases[requestID] = .active }
    }

    func cancel(_ requestID: UUID) {
        lock.withLock {
            guard phases[requestID] == .active else { return }
            phases[requestID] = .cancelled
        }
    }

    func isCancelled(_ requestID: UUID) -> Bool {
        lock.withLock { phases[requestID] == .cancelled }
    }

    func commitPublication(_ requestID: UUID) {
        lock.withLock {
            guard phases[requestID] != nil else { return }
            phases[requestID] = .publicationCommitted
        }
    }

    func isPublicationCommitted(_ requestID: UUID) -> Bool {
        lock.withLock { phases[requestID] == .publicationCommitted }
    }

    func finish(_ requestID: UUID) {
        _ = lock.withLock { phases.removeValue(forKey: requestID) }
    }
}

private actor BatchProgressReporter {
    private let requestID: UUID
    private let totalFiles: Int
    private let callback: @Sendable (BatchProgress) -> Void
    private var lastFraction = 0.0
    private var lastCurrentFile = 0

    init(
        requestID: UUID,
        totalFiles: Int,
        callback: @Sendable @escaping (BatchProgress) -> Void
    ) {
        self.requestID = requestID
        self.totalFiles = totalFiles
        self.callback = callback
    }

    func reportConversion(
        completedBeforeGroup: Int,
        groupInputs: [InputFile],
        localProgress: Double
    ) {
        let local = min(max(localProgress, 0), 1)
        let completed = Double(completedBeforeGroup) + local * Double(groupInputs.count)
        let fraction = 0.9 * completed / Double(max(totalFiles, 1))
        let localIndex = local > 0
            ? min(groupInputs.count - 1, max(0, Int(ceil(local * Double(groupInputs.count))) - 1))
            : 0
        emit(
            fraction: fraction,
            currentFile: min(totalFiles, completedBeforeGroup + localIndex + 1),
            displayName: groupInputs.indices.contains(localIndex)
                ? groupInputs[localIndex].displayName
                : nil
        )
    }

    func completeConversionGroup(completedFiles: Int, displayName: String?) {
        emit(
            fraction: 0.9 * Double(completedFiles) / Double(max(totalFiles, 1)),
            currentFile: min(totalFiles, completedFiles),
            displayName: displayName
        )
    }

    func reportPublication(publishedFiles: Int, displayName: String?) {
        emit(
            fraction: 0.9 + 0.1 * Double(publishedFiles) / Double(max(totalFiles, 1)),
            currentFile: min(totalFiles, publishedFiles),
            displayName: displayName
        )
    }

    func finish(displayName: String?) {
        emit(fraction: 1, currentFile: totalFiles, displayName: displayName)
    }

    private func emit(fraction: Double, currentFile: Int, displayName: String?) {
        lastFraction = max(lastFraction, min(max(fraction, 0), 1))
        lastCurrentFile = max(lastCurrentFile, min(max(currentFile, 0), totalFiles))
        callback(
            BatchProgress(
                requestID: requestID,
                fraction: lastFraction,
                currentFile: lastCurrentFile,
                totalFiles: totalFiles,
                currentDisplayName: displayName
            )
        )
    }
}
