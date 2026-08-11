import Foundation

actor VideoSplitJobCoordinator: VideoSplitJobCoordinating {
    private let probe: any VideoSplitProbing
    private let engine: any VideoSplitEngine
    private let outputValidator: VideoSplitOutputValidator
    private let planBuilder: VideoSplitPlanBuilder
    private let planRefiner: VideoSplitPlanRefiner
    private let manifestValidator: OutputArtifactManifestValidator
    private let publicationPlanner: VideoSplitPublicationPlanner
    private let publisher: OutputArtifactPublisher
    private nonisolated let cancellationRegistry = VideoSplitCancellationRegistry()

    private var activeRequestID: UUID?
    private var activePlanID: UUID?
    private var activeExecutionTask: Task<VideoSplitBatchResult, any Error>?
    private var cancelledRequestIDs: Set<UUID> = []

    init(
        probe: any VideoSplitProbing,
        engine: any VideoSplitEngine,
        outputValidator: VideoSplitOutputValidator? = nil,
        planBuilder: VideoSplitPlanBuilder = VideoSplitPlanBuilder(),
        planRefiner: VideoSplitPlanRefiner = VideoSplitPlanRefiner(),
        manifestValidator: OutputArtifactManifestValidator = OutputArtifactManifestValidator(),
        publicationPlanner: VideoSplitPublicationPlanner = VideoSplitPublicationPlanner(),
        publisher: OutputArtifactPublisher = OutputArtifactPublisher()
    ) {
        self.probe = probe
        self.engine = engine
        self.outputValidator = outputValidator ?? VideoSplitOutputValidator(probe: probe)
        self.planBuilder = planBuilder
        self.planRefiner = planRefiner
        self.manifestValidator = manifestValidator
        self.publicationPlanner = publicationPlanner
        self.publisher = publisher
    }

    func execute(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        guard activeRequestID == nil else {
            throw VideoSplitJobError.anotherRequestIsRunning
        }
        try Self.validateRequest(request)
        activeRequestID = request.id
        cancelledRequestIDs.remove(request.id)
        cancellationRegistry.begin(request.id)

        let execution = Task {
            try await perform(request, event: event)
        }
        activeExecutionTask = execution
        defer {
            activeExecutionTask = nil
            activeRequestID = nil
            activePlanID = nil
            cancelledRequestIDs.remove(request.id)
            cancellationRegistry.finish(request.id)
        }

        do {
            return try await withTaskCancellationHandler {
                try await execution.value
            } onCancel: {
                execution.cancel()
                Task { await self.cancel(requestID: request.id) }
            }
        } catch is CancellationError {
            throw VideoSplitJobError.cancelled
        } catch let error as VideoSplitJobError {
            throw error
        } catch {
            if cancelledRequestIDs.contains(request.id) || execution.isCancelled {
                throw VideoSplitJobError.cancelled
            }
            throw error
        }
    }

    nonisolated func cancel(requestID: UUID) async {
        cancellationRegistry.cancel(requestID)
        await cancelActiveExecution(requestID: requestID)
    }

    private func cancelActiveExecution(requestID: UUID) async {
        guard activeRequestID == requestID else { return }
        cancelledRequestIDs.insert(requestID)
        activeExecutionTask?.cancel()
        if let activePlanID {
            await engine.cancel(jobID: activePlanID)
        }
    }

    private func perform(
        _ request: VideoSplitBatchRequest,
        event: @Sendable @escaping (VideoSplitJobEvent) -> Void
    ) async throws -> VideoSplitBatchResult {
        let scopedURLs = Self.uniqueSecurityScopeURLs(for: request)
        let acquiredScopes = scopedURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer { acquiredScopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        let stagingRoot = request.outputDirectory.appendingPathComponent(
            ".fileisland-split-\(request.id.uuidString.lowercased())",
            isDirectory: true
        )
        guard !FileManager.default.fileExists(atPath: stagingRoot.path) else {
            throw VideoSplitJobError.invalidOutputDirectory
        }
        do {
            try FileManager.default.createDirectory(
                at: stagingRoot,
                withIntermediateDirectories: false
            )
        } catch {
            throw VideoSplitJobError.invalidOutputDirectory
        }
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        let reporter = VideoSplitBatchProgressReporter(
            requestID: request.id,
            durations: request.items.map {
                $0.plan.segments.last?.endMilliseconds ?? 1
            },
            callback: { event(.progress($0)) }
        )
        await reporter.begin(
            displayName: request.items.first?.input.file.displayName
        )

        var allPlannedArtifacts: [PlannedOutputArtifact] = []
        var allValidatedArtifacts: [ValidatedOutputArtifact] = []
        var validatedTotalBytes: Int64 = 0

        for (itemOffset, item) in request.items.enumerated() {
            try checkCancellation(request.id)
            let source: VideoSplitSourceFacts
            do {
                source = try await probe.probe(item.input.file)
            } catch is CancellationError {
                throw VideoSplitJobError.cancelled
            } catch let error as VideoSplitProbeError where error == .probeCancelled {
                throw VideoSplitJobError.cancelled
            } catch {
                throw VideoSplitJobError.validationFailed
            }
            guard Self.isAuditedFastSource(source) else {
                throw VideoSplitJobError.validationFailed
            }

            let currentPlan: VideoSplitPlan
            do {
                currentPlan = try planBuilder.makePlan(
                    id: item.plan.id,
                    input: item.input.file,
                    intent: item.plan.intent,
                    source: source,
                    inputRelativePath: item.input.relativePath
                )
            } catch {
                throw VideoSplitJobError.stalePlan
            }
            guard currentPlan == item.plan else {
                throw VideoSplitJobError.stalePlan
            }
            guard engine.canHandle(currentPlan) else {
                throw VideoSplitJobError.engineUnavailable
            }

            var executablePlan = currentPlan
            var completed: ValidatedVideoSplitOutput?
            for attempt in 0...3 {
                try checkCancellation(request.id)
                let attemptDirectory = stagingRoot.appendingPathComponent(
                    "item-\(itemOffset + 1)-attempt-\(attempt + 1)",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: attemptDirectory,
                    withIntermediateDirectories: false
                )

                do {
                    await reporter.beginAttempt(
                        itemOffset: itemOffset,
                        attempt: attempt
                    )
                    activePlanID = executablePlan.id
                    guard engine.canHandle(executablePlan) else {
                        throw VideoSplitJobError.engineUnavailable
                    }
                    let executionSegmentCount = executablePlan.segments.count
                    let progressDelivery = VideoSplitProgressDelivery()
                    let result: EngineExecutionResult
                    do {
                        result = try await engine.execute(
                            executablePlan,
                            stagingDirectory: attemptDirectory
                        ) { localProgress in
                            progressDelivery.submit {
                                await reporter.reportExecution(
                                    itemOffset: itemOffset,
                                    attempt: attempt,
                                    displayName: item.input.file.displayName,
                                    localFraction: localProgress.fraction,
                                    segmentCount: executionSegmentCount
                                )
                            }
                        }
                    } catch {
                        await progressDelivery.flush()
                        throw error
                    }
                    await progressDelivery.flush()
                    activePlanID = nil
                    try checkCancellation(request.id)
                    let validated = try await outputValidator.validate(
                        plan: executablePlan,
                        source: source,
                        stagedArtifacts: result.artifacts,
                        stagingRoot: attemptDirectory
                    )
                    completed = validated
                    break
                } catch let validationError as VideoSplitOutputValidationError {
                    activePlanID = nil
                    let failedIndex = Self.retryableSegmentIndex(validationError)
                    guard let failedIndex else {
                        throw VideoSplitJobError.validationFailed
                    }
                    guard attempt < 3 else {
                        throw VideoSplitJobError.retryLimitReached
                    }
                    try? FileManager.default.removeItem(at: attemptDirectory)
                    do {
                        executablePlan = try planRefiner.refine(
                            executablePlan,
                            source: source,
                            failedSegmentIndex: failedIndex
                        )
                    } catch VideoSplitRefinementError.noEarlierKeyframe {
                        throw VideoSplitJobError.keyframeSpacingUnreachable
                    } catch {
                        throw VideoSplitJobError.validationFailed
                    }
                } catch let engineError as VideoSplitEngineError {
                    activePlanID = nil
                    if engineError == .cancelled {
                        throw VideoSplitJobError.cancelled
                    }
                    if engineError == .sourceChanged {
                        throw VideoSplitJobError.stalePlan
                    }
                    throw VideoSplitJobError.engineUnavailable
                } catch is CancellationError {
                    activePlanID = nil
                    throw VideoSplitJobError.cancelled
                }
            }

            guard let completed else {
                throw VideoSplitJobError.retryLimitReached
            }
            let bytes = completed.totalBytes
            let (newTotal, overflow) = validatedTotalBytes.addingReportingOverflow(bytes)
            guard !overflow else { throw VideoSplitJobError.validationFailed }
            validatedTotalBytes = newTotal
            allPlannedArtifacts.append(contentsOf: completed.manifest.entries.map {
                PlannedOutputArtifact(
                    id: $0.id,
                    preferredRelativePath: $0.preferredRelativePath
                )
            })
            allValidatedArtifacts.append(contentsOf: completed.manifest.entries)
            await reporter.completeItem(
                itemOffset: itemOffset,
                displayName: item.input.file.displayName,
                segmentCount: executablePlan.segments.count
            )
        }

        try checkCancellation(request.id)
        let reservedArtifacts: [PlannedOutputArtifact]
        let completeManifest: ValidatedOutputArtifactManifest
        do {
            reservedArtifacts = try publicationPlanner.reserveSplitDirectories(
                for: allPlannedArtifacts,
                outputRoot: request.outputDirectory
            )
            completeManifest = try manifestValidator.revalidate(
                plannedArtifacts: reservedArtifacts,
                previouslyValidatedArtifacts: allValidatedArtifacts,
                allowedSourceInputIDs: Set(request.items.map(\.input.file.id)),
                stagingRoot: stagingRoot
            )
        } catch {
            throw VideoSplitJobError.validationFailed
        }
        try checkCancellation(request.id)
        event(
            .validationCompleted(
                requestID: request.id,
                segmentCount: completeManifest.entries.count
            )
        )

        let published: [PublishedOutputArtifact]
        do {
            published = try publisher.publish(
                completeManifest,
                to: request.outputDirectory,
                protectedURLs: Set(request.items.map(\.input.file.url)),
                collisionPolicy: .failIfUnavailable,
                cancellationCheck: { [cancellationRegistry] in
                    try Task.checkCancellation()
                    guard !cancellationRegistry.isCancelled(request.id) else {
                        throw CancellationError()
                    }
                }
            )
        } catch is CancellationError {
            throw VideoSplitJobError.cancelled
        } catch {
            throw VideoSplitJobError.publicationFailed
        }
        await reporter.finish(
            displayName: request.items.last?.input.file.displayName,
            segmentCount: published.count
        )
        event(
            .publicationCompleted(
                requestID: request.id,
                outputURLs: published.map(\.fileURL)
            )
        )
        return VideoSplitBatchResult(
            requestID: request.id,
            outputURLs: published.map(\.fileURL),
            segmentCount: published.count,
            totalBytes: validatedTotalBytes
        )
    }

    private func checkCancellation(_ requestID: UUID) throws {
        guard !Task.isCancelled,
              !cancelledRequestIDs.contains(requestID),
              !cancellationRegistry.isCancelled(requestID) else {
            throw VideoSplitJobError.cancelled
        }
    }

    private static func validateRequest(_ request: VideoSplitBatchRequest) throws {
        guard !request.items.isEmpty else { throw VideoSplitJobError.emptyRequest }
        guard request.outputDirectory.isFileURL,
              let values = try? request.outputDirectory.resourceValues(
                  forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw VideoSplitJobError.invalidOutputDirectory
        }
        var identities: Set<UUID> = []
        for item in request.items {
            guard identities.insert(item.input.file.id).inserted else {
                throw VideoSplitJobError.duplicateInputIdentity
            }
            guard item.plan.input == item.input.file,
                  item.plan.intent.mode == .fastKeyframeCopy,
                  item.plan.intent.source == .custom,
                  item.plan.ruleSnapshot == nil else {
                throw VideoSplitJobError.stalePlan
            }
        }
    }

    private static func isAuditedFastSource(_ source: VideoSplitSourceFacts) -> Bool {
        let container = source.container.lowercased()
        return ["mp4", "mov", "quicktime"].contains(container)
            && source.videoCodec == "h264"
            && (source.audioCodec == nil || source.audioCodec == "aac")
    }

    private static func retryableSegmentIndex(
        _ error: VideoSplitOutputValidationError
    ) -> Int? {
        switch error {
        case let .exceedsMaximumBytes(segmentIndex, _, _),
             let .exceedsMaximumDuration(segmentIndex, _, _, _):
            segmentIndex
        default:
            nil
        }
    }

    private static func uniqueSecurityScopeURLs(
        for request: VideoSplitBatchRequest
    ) -> [URL] {
        var seen: Set<URL> = []
        return (request.selections.map(\.url) + [request.outputDirectory]).filter {
            seen.insert($0.standardizedFileURL).inserted
        }
    }
}

private final class VideoSplitCancellationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequestIDs: Set<UUID> = []
    private var cancelledRequestIDs: Set<UUID> = []

    func begin(_ requestID: UUID) {
        lock.withLock {
            activeRequestIDs.insert(requestID)
            cancelledRequestIDs.remove(requestID)
        }
    }

    func cancel(_ requestID: UUID) {
        lock.withLock {
            guard activeRequestIDs.contains(requestID) else { return }
            cancelledRequestIDs.insert(requestID)
        }
    }

    func isCancelled(_ requestID: UUID) -> Bool {
        lock.withLock { cancelledRequestIDs.contains(requestID) }
    }

    func finish(_ requestID: UUID) {
        lock.withLock {
            activeRequestIDs.remove(requestID)
            cancelledRequestIDs.remove(requestID)
        }
    }
}

/// Preserves the order of synchronous engine progress callbacks while still
/// delivering them to the actor-backed aggregate reporter. `flush()` is used
/// at every attempt boundary so a retry can never overtake the final progress
/// event from the attempt it replaces.
private final class VideoSplitProgressDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func submit(_ operation: @Sendable @escaping () async -> Void) {
        lock.withLock {
            let previous = tail
            tail = Task {
                if let previous { await previous.value }
                await operation()
            }
        }
    }

    func flush() async {
        let pending = lock.withLock { tail }
        await pending?.value
    }
}

private actor VideoSplitBatchProgressReporter {
    private static let attemptProgressCeilings = [0.82, 0.89, 0.93, 0.97]
    private let requestID: UUID
    private let durations: [Int64]
    private let totalDuration: Double
    private let callback: @Sendable (VideoSplitBatchProgress) -> Void
    private var lastFraction = 0.0
    private var finished = false
    private var currentAttemptByItem: [Int: Int] = [:]

    init(
        requestID: UUID,
        durations: [Int64],
        callback: @Sendable @escaping (VideoSplitBatchProgress) -> Void
    ) {
        self.requestID = requestID
        self.durations = durations.map { max($0, 1) }
        totalDuration = self.durations.reduce(0.0) { partial, duration in
            partial + Double(duration)
        }
        self.callback = callback
    }

    func begin(displayName: String?) {
        emit(
            fraction: 0,
            currentFile: durations.isEmpty ? 0 : 1,
            displayName: displayName,
            currentSegment: nil,
            totalSegments: nil
        )
    }

    func beginAttempt(itemOffset: Int, attempt: Int) {
        guard durations.indices.contains(itemOffset), !finished else { return }
        currentAttemptByItem[itemOffset] = attempt
    }

    func reportExecution(
        itemOffset: Int,
        attempt: Int,
        displayName: String,
        localFraction: Double,
        segmentCount: Int
    ) {
        guard durations.indices.contains(itemOffset),
              currentAttemptByItem[itemOffset] == attempt,
              Self.attemptProgressCeilings.indices.contains(attempt),
              !finished else { return }
        let completed = durations.prefix(itemOffset).reduce(0.0) { partial, duration in
            partial + Double(duration)
        }
        let local = min(max(localFraction, 0), 1)
        let attemptStart = attempt == 0
            ? 0
            : Self.attemptProgressCeilings[attempt - 1]
        let attemptEnd = Self.attemptProgressCeilings[attempt]
        let attemptProgress = attemptStart + (attemptEnd - attemptStart) * local
        let weighted = completed + Double(durations[itemOffset]) * attemptProgress
        let segment = local > 0
            ? min(segmentCount, max(1, Int(ceil(local * Double(segmentCount)))))
            : 1
        emit(
            fraction: 0.94 * weighted / max(totalDuration, 1),
            currentFile: itemOffset + 1,
            displayName: displayName,
            currentSegment: segment,
            totalSegments: segmentCount
        )
    }

    func completeItem(
        itemOffset: Int,
        displayName: String,
        segmentCount: Int
    ) {
        let completed = durations.prefix(itemOffset + 1).reduce(0.0) { partial, duration in
            partial + Double(duration)
        }
        emit(
            fraction: 0.94 * completed / max(totalDuration, 1),
            currentFile: itemOffset + 1,
            displayName: displayName,
            currentSegment: segmentCount,
            totalSegments: segmentCount
        )
    }

    func finish(displayName: String?, segmentCount: Int) {
        guard !finished else { return }
        emit(
            fraction: 1,
            currentFile: durations.count,
            displayName: displayName,
            currentSegment: segmentCount,
            totalSegments: segmentCount
        )
        finished = true
    }

    private func emit(
        fraction: Double,
        currentFile: Int,
        displayName: String?,
        currentSegment: Int?,
        totalSegments: Int?
    ) {
        let clamped = max(lastFraction, min(max(fraction, 0), 1))
        guard clamped > lastFraction || (lastFraction == 0 && clamped == 0) else { return }
        lastFraction = clamped
        callback(
            VideoSplitBatchProgress(
                requestID: requestID,
                fraction: clamped,
                currentFile: currentFile,
                totalFiles: durations.count,
                currentDisplayName: displayName,
                currentSegment: currentSegment,
                totalSegments: totalSegments
            )
        )
    }
}
