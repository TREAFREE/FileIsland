import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("Video split job coordinator")
struct VideoSplitJobCoordinatorTests {
    @Test("Multiple videos publish as complete folders with monotonic weighted progress")
    func publishesMultipleVideosWithWeightedProgress() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let first = try workspace.makeInput(name: "Movie.mp4", byteCount: 100)
        let second = try workspace.makeInput(name: "Long Movie.mp4", byteCount: 100)
        let firstFacts = SplitProbeTemplate(durationMilliseconds: 4_000)
        let secondFacts = SplitProbeTemplate(durationMilliseconds: 8_000)
        await store.register(first.url, template: firstFacts)
        await store.register(second.url, template: secondFacts)

        let firstItem = try makeItem(
            input: first,
            facts: firstFacts,
            maximumDurationMilliseconds: 2_500
        )
        let secondItem = try makeItem(
            input: second,
            facts: secondFacts,
            maximumDurationMilliseconds: 5_000
        )
        try FileManager.default.createDirectory(
            at: workspace.output.appendingPathComponent("Movie — Split", isDirectory: true),
            withIntermediateDirectories: false
        )

        let engine = SplitCoordinatorFakeEngine(store: store, outputByteCount: { _ in 80 })
        let probe = SplitCoordinatorFakeProbe(store: store)
        let coordinator = makeCoordinator(probe: probe, engine: engine)
        let events = LockedSplitJobEvents()
        let request = VideoSplitBatchRequest(
            selections: [.file(first.url), .file(second.url)],
            outputDirectory: workspace.output,
            items: [firstItem, secondItem]
        )

        let result = try await coordinator.execute(request, event: events.append)

        #expect(result.segmentCount == firstItem.plan.segments.count + secondItem.plan.segments.count)
        #expect(result.outputURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(result.outputURLs.contains { $0.path.contains("Movie — Split-2") })
        #expect(result.outputURLs.contains { $0.path.contains("Long Movie — Split") })
        let fractions = events.values.compactMap { event -> Double? in
            guard case let .progress(progress) = event else { return nil }
            return progress.fraction
        }
        #expect(fractions.first == 0)
        #expect(fractions.last == 1)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        let lifecycle = events.values.filter {
            if case .validationCompleted = $0 { return true }
            if case .publicationCompleted = $0 { return true }
            return false
        }
        #expect(
            lifecycle == [
                .validationCompleted(
                    requestID: request.id,
                    segmentCount: result.segmentCount
                ),
                .publicationCompleted(
                    requestID: request.id,
                    outputURLs: result.outputURLs
                )
            ]
        )
    }

    @Test("Validation is observable before publication failure and publication is never emitted")
    func reportsRealValidationButNoPublicationWhenPublishingFails() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Publish Failure.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 4_000)
        await store.register(input.url, template: facts)
        let item = try makeItem(
            input: input,
            facts: facts,
            maximumDurationMilliseconds: 2_500
        )
        let engine = SplitCoordinatorFakeEngine(store: store, outputByteCount: { _ in 80 })
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine,
            publisher: OutputArtifactPublisher(
                fileSystem: AlwaysFailingSplitPublicationFileSystem()
            )
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [item]
        )
        let events = LockedSplitJobEvents()

        await expectJobError(.publicationFailed) {
            try await coordinator.execute(request, event: events.append)
        }

        #expect(events.values.contains {
            guard case let .validationCompleted(requestID, count) = $0 else { return false }
            return requestID == request.id && count == item.plan.segments.count
        })
        #expect(events.values.contains {
            if case .publicationCompleted = $0 { return true }
            return false
        } == false)
        #expect(try workspace.output.contents().isEmpty)
    }

    @Test("A stale preview is rejected before the engine starts")
    func rejectsStalePreview() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Stale.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 4_000)
        await store.register(input.url, template: facts)
        let current = try makeItem(
            input: input,
            facts: facts,
            maximumDurationMilliseconds: 2_500
        )
        let stalePlan = VideoSplitPlan(
            id: current.plan.id,
            input: current.plan.input,
            sourceFileIdentity: current.plan.sourceFileIdentity,
            intent: current.plan.intent,
            ruleSnapshot: nil,
            segments: current.plan.segments.enumerated().map { offset, segment in
                VideoSegmentPlan(
                    index: segment.index,
                    startMilliseconds: segment.startMilliseconds,
                    endMilliseconds: segment.endMilliseconds,
                    outputRelativePath: segment.outputRelativePath,
                    estimatedBytes: segment.estimatedBytes + (offset == 0 ? 1 : 0),
                    requiresReencoding: false
                )
            }
        )
        let engine = SplitCoordinatorFakeEngine(store: store, outputByteCount: { _ in 80 })
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [VideoSplitBatchItem(input: current.input, plan: stalePlan)]
        )

        await expectJobError(.stalePlan) {
            try await coordinator.execute(request, progress: { _ in })
        }
        #expect(await engine.executionCount == 0)
    }

    @Test("Replacing the source after planning invalidates the request")
    func rejectsSourceReplacementAfterPlanning() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Replaced.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 4_000)
        await store.register(input.url, template: facts)
        let item = try makeItem(
            input: input,
            facts: facts,
            maximumDurationMilliseconds: 2_500
        )
        try FileManager.default.removeItem(at: input.url)
        try Data(repeating: 0x43, count: 100).write(to: input.url)
        let engine = SplitCoordinatorFakeEngine(store: store, outputByteCount: { _ in 80 })
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [item]
        )

        await expectJobError(.stalePlan) {
            try await coordinator.execute(request, progress: { _ in })
        }
        #expect(await engine.executionCount == 0)
        #expect(try workspace.output.contents().isEmpty)
    }

    @Test("Oversized output is replanned on an earlier keyframe")
    func refinesOversizedOutput() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Refine.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 8_000)
        await store.register(input.url, template: facts)
        let item = try makeItem(
            input: input,
            facts: facts,
            maximumBytes: 300,
            maximumDurationMilliseconds: 5_000
        )
        let engine = SplitCoordinatorFakeEngine(
            store: store,
            outputByteCount: { attempt in attempt == 1 ? 301 : 80 }
        )
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [item]
        )
        let progress = LockedSplitBatchProgress()

        let result = try await coordinator.execute(
            request,
            progress: progress.append
        )

        #expect(await engine.executionCount == 2)
        #expect(result.segmentCount > item.plan.segments.count)
        #expect(result.outputURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let fractions = progress.values.map(\.fraction)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        let firstAttemptCeiling = 0.94 * 0.82
        let secondAttemptCeiling = 0.94 * 0.89
        #expect(fractions.contains { abs($0 - firstAttemptCeiling) < 0.000_001 })
        #expect(fractions.contains {
            $0 > firstAttemptCeiling && $0 <= secondAttemptCeiling
        })
        #expect(fractions.last == 1)
    }

    @Test("Four consecutive oversized attempts stop at the retry limit")
    func enforcesRetryLimit() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Retry.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 8_000)
        await store.register(input.url, template: facts)
        let item = try makeItem(
            input: input,
            facts: facts,
            maximumBytes: 300,
            maximumDurationMilliseconds: 5_000
        )
        let engine = SplitCoordinatorFakeEngine(store: store, outputByteCount: { _ in 301 })
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [item]
        )

        await expectJobError(.retryLimitReached) {
            try await coordinator.execute(request, progress: { _ in })
        }
        #expect(await engine.executionCount == 4)
        #expect(try workspace.output.contents().allSatisfy {
            !$0.lastPathComponent.hasPrefix(".fileisland-split-")
        })
    }

    @Test("Cancellation stops the active engine and removes request staging")
    func cancellationCleansStaging() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Cancel.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 4_000)
        await store.register(input.url, template: facts)
        let item = try makeItem(
            input: input,
            facts: facts,
            maximumDurationMilliseconds: 2_500
        )
        let engine = SplitCoordinatorFakeEngine(
            store: store,
            outputByteCount: { _ in 80 },
            blocksUntilCancelled: true
        )
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [item]
        )
        let execution = Task {
            try await coordinator.execute(request, progress: { _ in })
        }
        for _ in 0..<200 {
            if await engine.hasStarted { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await engine.hasStarted)

        await coordinator.cancel(requestID: request.id)
        await expectJobError(.cancelled) { try await execution.value }
        #expect(await engine.cancelCount == 1)
        #expect(try workspace.output.contents().allSatisfy {
            !$0.lastPathComponent.hasPrefix(".fileisland-split-")
        })
    }

    @Test("Cancellation during publication rolls back the complete visible segment set")
    func cancellationDuringPublicationRollsBackVisibleSegments() async throws {
        let workspace = try SplitCoordinatorWorkspace()
        let store = SplitProbeFactStore()
        let input = try workspace.makeInput(name: "Publish Cancel.mp4", byteCount: 100)
        let facts = SplitProbeTemplate(durationMilliseconds: 4_000)
        await store.register(input.url, template: facts)
        let item = try makeItem(
            input: input,
            facts: facts,
            maximumDurationMilliseconds: 2_500
        )
        let engine = SplitCoordinatorFakeEngine(store: store, outputByteCount: { _ in 80 })
        let publisher = OutputArtifactPublisher(
            fileSystem: CancellingPublicationFileSystem()
        )
        let coordinator = makeCoordinator(
            probe: SplitCoordinatorFakeProbe(store: store),
            engine: engine,
            publisher: publisher
        )
        let request = VideoSplitBatchRequest(
            selections: [.file(input.url)],
            outputDirectory: workspace.output,
            items: [item]
        )
        let execution = Task {
            try await coordinator.execute(request, progress: { _ in })
        }

        await expectJobError(.cancelled) { try await execution.value }
        #expect(try workspace.output.contents().isEmpty)
    }

    private func makeCoordinator(
        probe: SplitCoordinatorFakeProbe,
        engine: SplitCoordinatorFakeEngine,
        publisher: OutputArtifactPublisher = OutputArtifactPublisher()
    ) -> VideoSplitJobCoordinator {
        VideoSplitJobCoordinator(
            probe: probe,
            engine: engine,
            outputValidator: VideoSplitOutputValidator(
                probe: probe,
                decodabilityChecker: AlwaysDecodableSplitSegment()
            ),
            publisher: publisher
        )
    }

    private func makeItem(
        input: InputFile,
        facts: SplitProbeTemplate,
        maximumBytes: Int64? = nil,
        maximumDurationMilliseconds: Int64? = nil
    ) throws -> VideoSplitBatchItem {
        let batchInput = BatchInput(
            file: input,
            selection: .file(input.url),
            relativePath: try SafeRelativePath(input.displayName)
        )
        let source = facts.facts(for: input)
        let plan = try VideoSplitPlanBuilder().makePlan(
            input: input,
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: maximumBytes,
                    maxDurationMilliseconds: maximumDurationMilliseconds,
                    safetyRatio: 0.8,
                    requiredContainer: nil,
                    requiredVideoCodec: nil,
                    requiredAudioCodec: nil
                ),
                stripMetadata: true
            ),
            source: source,
            inputRelativePath: batchInput.relativePath
        )
        return VideoSplitBatchItem(input: batchInput, plan: plan)
    }

    private func expectJobError<T: Sendable>(
        _ expected: VideoSplitJobError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected video split job error \(expected)")
        } catch let error as VideoSplitJobError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct SplitProbeTemplate: Sendable {
    let durationMilliseconds: Int64
    var displayWidth = 1_920
    var displayHeight = 1_080
    var averageBitrateBitsPerSecond: Int64 = 100
    var keyframeMilliseconds: [Int64] {
        stride(from: Int64(0), to: durationMilliseconds, by: 1_000).map { $0 }
    }

    func facts(for input: InputFile) -> VideoSplitSourceFacts {
        VideoSplitSourceFacts(
            inputID: input.id,
            sourceURL: input.url,
            fileIdentity: (try? actualVideoSplitTestIdentity(
                at: input.url,
                expectedByteCount: input.fileSize
            )) ?? makeVideoSplitTestIdentity(byteCount: input.fileSize),
            durationMilliseconds: durationMilliseconds,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            averageBitrateBitsPerSecond: averageBitrateBitsPerSecond,
            container: "mp4",
            videoCodec: "h264",
            audioCodec: "aac",
            videoStartMilliseconds: 0,
            audioStartMilliseconds: 0,
            audioDurationMilliseconds: durationMilliseconds,
            userMetadataKeys: [],
            frameDurationMilliseconds: 40,
            keyframeMilliseconds: keyframeMilliseconds
        )
    }
}

private actor SplitProbeFactStore {
    private var factsByPath: [String: SplitProbeTemplate] = [:]

    func register(_ url: URL, template: SplitProbeTemplate) {
        factsByPath[url.standardizedFileURL.path] = template
        factsByPath[url.resolvingSymlinksInPath().standardizedFileURL.path] = template
    }

    func facts(for input: InputFile) throws -> VideoSplitSourceFacts {
        let direct = input.url.standardizedFileURL.path
        let resolved = input.url.resolvingSymlinksInPath().standardizedFileURL.path
        guard let template = factsByPath[direct] ?? factsByPath[resolved] else {
            throw VideoSplitProbeError.unsupportedMedia
        }
        return template.facts(for: input)
    }
}

private struct SplitCoordinatorFakeProbe: VideoSplitProbing {
    let store: SplitProbeFactStore

    func probe(_ input: InputFile) async throws -> VideoSplitSourceFacts {
        try await store.facts(for: input)
    }
}

private actor SplitCoordinatorFakeEngine: VideoSplitEngine {
    private let store: SplitProbeFactStore
    private let outputByteCount: @Sendable (Int) -> Int
    private let blocksUntilCancelled: Bool
    private(set) var executionCount = 0
    private(set) var cancelCount = 0
    private(set) var hasStarted = false

    init(
        store: SplitProbeFactStore,
        outputByteCount: @escaping @Sendable (Int) -> Int,
        blocksUntilCancelled: Bool = false
    ) {
        self.store = store
        self.outputByteCount = outputByteCount
        self.blocksUntilCancelled = blocksUntilCancelled
    }

    nonisolated func canHandle(_ plan: VideoSplitPlan) -> Bool {
        plan.intent.mode == .fastKeyframeCopy
    }

    func execute(
        _ plan: VideoSplitPlan,
        stagingDirectory: URL,
        progress: @Sendable @escaping (VideoSplitExecutionProgress) -> Void
    ) async throws -> EngineExecutionResult {
        executionCount += 1
        hasStarted = true
        if blocksUntilCancelled {
            do {
                while true { try await Task.sleep(for: .milliseconds(20)) }
            } catch {
                throw VideoSplitEngineError.cancelled
            }
        }
        let byteCount = outputByteCount(executionCount)
        var artifacts: [StagedOutputArtifact] = []
        for segment in plan.segments {
            let fileURL = stagingDirectory.appendingPathComponent(
                segment.outputRelativePath.components.last ?? "segment.mp4"
            )
            try Data(repeating: 0x41, count: byteCount).write(to: fileURL)
            await store.register(
                fileURL,
                template: SplitProbeTemplate(
                    durationMilliseconds: segment.endMilliseconds - segment.startMilliseconds
                )
            )
            artifacts.append(
                StagedOutputArtifact(
                    id: OutputArtifactID(
                        sourceInputID: plan.input.id,
                        role: .videoSegment(
                            ordinal: segment.index,
                            total: plan.segments.count
                        )
                    ),
                    fileURL: fileURL
                )
            )
        }
        progress(
            VideoSplitExecutionProgress(
                jobID: plan.id,
                fraction: 0.5,
                processedMilliseconds: (plan.segments.last?.endMilliseconds ?? 0) / 2
            )
        )
        progress(
            VideoSplitExecutionProgress(
                jobID: plan.id,
                fraction: 1,
                processedMilliseconds: plan.segments.last?.endMilliseconds ?? 0
            )
        )
        return EngineExecutionResult(artifacts: Array(artifacts.reversed()))
    }

    func cancel(jobID _: UUID) async {
        cancelCount += 1
    }
}

private struct AlwaysDecodableSplitSegment: VideoSplitSegmentDecodabilityChecking {
    func canDecodeFirstFrame(at _: URL) async throws -> Bool { true }
}

private final class LockedSplitBatchProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VideoSplitBatchProgress] = []

    func append(_ progress: VideoSplitBatchProgress) {
        lock.withLock { storage.append(progress) }
    }

    var values: [VideoSplitBatchProgress] {
        lock.withLock { storage }
    }
}

private final class LockedSplitJobEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VideoSplitJobEvent] = []

    func append(_ event: VideoSplitJobEvent) {
        lock.withLock { storage.append(event) }
    }

    var values: [VideoSplitJobEvent] {
        lock.withLock { storage }
    }
}

private final class AlwaysFailingSplitPublicationFileSystem:
    OutputArtifactFileSystem,
    @unchecked Sendable
{
    private let base = FoundationOutputArtifactFileSystem()

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }

    func resourceValues(
        at url: URL,
        forKeys keys: Set<URLResourceKey>
    ) throws -> URLResourceValues {
        try base.resourceValues(at: url, forKeys: keys)
    }

    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }

    func moveItem(at _: URL, to _: URL) throws {
        throw OutputArtifactPublisherError.publicationFailed
    }

    func removeItem(at url: URL) throws { try base.removeItem(at: url) }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try base.contentsOfDirectory(at: url)
    }

    func fileIdentity(at url: URL) throws -> OutputArtifactFileIdentity {
        try base.fileIdentity(at: url)
    }
}

private final class CancellingPublicationFileSystem:
    OutputArtifactFileSystem,
    @unchecked Sendable
{
    private let base = FoundationOutputArtifactFileSystem()
    private let lock = NSLock()
    private var didCancel = false

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func resourceValues(
        at url: URL,
        forKeys keys: Set<URLResourceKey>
    ) throws -> URLResourceValues {
        try base.resourceValues(at: url, forKeys: keys)
    }

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItem(at: sourceURL, to: destinationURL)
        let shouldCancel = lock.withLock {
            guard !didCancel else { return false }
            didCancel = true
            return true
        }
        if shouldCancel {
            withUnsafeCurrentTask { $0?.cancel() }
        }
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try base.contentsOfDirectory(at: url)
    }

    func fileIdentity(at url: URL) throws -> OutputArtifactFileIdentity {
        try base.fileIdentity(at: url)
    }
}

private final class SplitCoordinatorWorkspace {
    let root: URL
    let sources: URL
    let output: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-SplitCoordinator-\(UUID().uuidString)",
            isDirectory: true
        )
        sources = root.appendingPathComponent("Sources", isDirectory: true)
        output = root.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    func makeInput(name: String, byteCount: Int) throws -> InputFile {
        let url = sources.appendingPathComponent(name)
        try Data(repeating: 0x42, count: byteCount).write(to: url)
        return InputFile(
            url: url,
            type: .mpeg4Movie,
            fileSize: Int64(byteCount),
            displayName: name
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

private extension URL {
    func contents() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: self,
            includingPropertiesForKeys: nil
        )
    }
}
