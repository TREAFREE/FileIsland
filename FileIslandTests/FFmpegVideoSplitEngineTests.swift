import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("FFmpeg fast video split engine")
struct FFmpegVideoSplitEngineTests {
    @Test("Execution reports monotonic progress and returns typed segment artifacts")
    func executesWithMonotonicProgress() async throws {
        let temporary = try TemporarySplitDirectory()
        let plan = try makePlan(segmentCount: 2)
        let runner = FakeVideoSplitProcessRunner(
            events: [
                .standardOutput(Data("out_time_us=500000\n".utf8)),
                .standardOutput(Data("out_time_us=250000\nprogress=end\n".utf8))
            ],
            exitCode: 0
        )
        let progress = LockedSplitProgress()
        let engine = FFmpegVideoSplitEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner,
            fileValidator: StaticSplitFileValidator(
                identity: plan.sourceFileIdentity
            )
        )

        let result = try await engine.execute(
            plan,
            stagingDirectory: temporary.url,
            progress: progress.append
        )

        #expect(result.artifacts.map(\.id.role) == [
            .videoSegment(ordinal: 1, total: 2),
            .videoSegment(ordinal: 2, total: 2)
        ])
        let fractions = progress.values.map(\.fraction)
        #expect(fractions.first == 0)
        #expect(fractions.last == 1)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
        let limits = await runner.capturedLimits
        #expect(limits?.maximumStandardOutputBytes == 1_024 * 1_024)
        #expect(limits?.maximumStandardErrorBytes == 64 * 1_024)
    }

    @Test("Cancellation before launch fails without starting a child process")
    func cancellationBeforeLaunch() async throws {
        let temporary = try TemporarySplitDirectory()
        let plan = try makePlan(segmentCount: 1)
        let runner = FakeVideoSplitProcessRunner(events: [], exitCode: 0)
        let engine = FFmpegVideoSplitEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner,
            fileValidator: StaticSplitFileValidator(
                identity: plan.sourceFileIdentity
            )
        )

        await engine.cancel(jobID: plan.id)
        do {
            _ = try await engine.execute(
                plan,
                stagingDirectory: temporary.url,
                progress: { _ in }
            )
            Issue.record("A pre-cancelled job unexpectedly executed")
        } catch let error as VideoSplitEngineError {
            #expect(error == .cancelled)
        }
        #expect(await runner.runCount == 0)
    }

    @Test("A failed process removes only manifest-declared staging outputs")
    func failureCleansExpectedArtifacts() async throws {
        let temporary = try TemporarySplitDirectory()
        let plan = try makePlan(segmentCount: 2)
        let runner = FakeVideoSplitProcessRunner(
            events: [],
            exitCode: 7,
            materializedSegmentCount: 2
        )
        let unrelated = temporary.url.appendingPathComponent("keep-me.txt")
        try Data("user".utf8).write(to: unrelated)
        let engine = FFmpegVideoSplitEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: runner,
            fileValidator: StaticSplitFileValidator(
                identity: plan.sourceFileIdentity
            )
        )

        do {
            _ = try await engine.execute(
                plan,
                stagingDirectory: temporary.url,
                progress: { _ in }
            )
            Issue.record("A failed child process unexpectedly succeeded")
        } catch let error as VideoSplitEngineError {
            #expect(error == .processFailed)
        }
        let remaining = try FileManager.default.contentsOfDirectory(
            at: temporary.url,
            includingPropertiesForKeys: nil
        )
        #expect(remaining.map(\.lastPathComponent) == [unrelated.lastPathComponent])
    }

    @Test("Source identity changes before or during execution fail closed")
    func sourceIdentityChangesFailClosed() async throws {
        let beforeDirectory = try TemporarySplitDirectory()
        let beforePlan = try makePlan(segmentCount: 1)
        let beforeRunner = FakeVideoSplitProcessRunner(events: [], exitCode: 0)
        let changedIdentity = VideoSplitFileIdentity(
            device: beforePlan.sourceFileIdentity.device,
            inode: beforePlan.sourceFileIdentity.inode + 1,
            byteCount: beforePlan.sourceFileIdentity.byteCount,
            modificationSeconds: beforePlan.sourceFileIdentity.modificationSeconds,
            modificationNanoseconds: beforePlan.sourceFileIdentity.modificationNanoseconds
        )
        let beforeEngine = FFmpegVideoSplitEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: beforeRunner,
            fileValidator: SequencedSplitFileValidator(
                identities: [changedIdentity]
            )
        )

        do {
            _ = try await beforeEngine.execute(
                beforePlan,
                stagingDirectory: beforeDirectory.url,
                progress: { _ in }
            )
            Issue.record("A replaced source unexpectedly executed")
        } catch let error as VideoSplitEngineError {
            #expect(error == .sourceChanged)
        }
        #expect(await beforeRunner.runCount == 0)

        let duringDirectory = try TemporarySplitDirectory()
        let duringPlan = try makePlan(segmentCount: 1)
        let duringRunner = FakeVideoSplitProcessRunner(
            events: [],
            exitCode: 0,
            materializedSegmentCount: 1
        )
        let duringEngine = FFmpegVideoSplitEngine(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            processRunner: duringRunner,
            fileValidator: SequencedSplitFileValidator(
                identities: [duringPlan.sourceFileIdentity, changedIdentity]
            )
        )

        do {
            _ = try await duringEngine.execute(
                duringPlan,
                stagingDirectory: duringDirectory.url,
                progress: { _ in }
            )
            Issue.record("A source changed during execution unexpectedly succeeded")
        } catch let error as VideoSplitEngineError {
            #expect(error == .sourceChanged)
        }
        #expect(await duringRunner.runCount == 1)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: duringDirectory.url,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    private func makePlan(segmentCount: Int) throws -> VideoSplitPlan {
        let input = InputFile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000162")!,
            url: URL(fileURLWithPath: "/private/tmp/input.mp4"),
            type: .mpeg4Movie,
            fileSize: 400_000,
            displayName: "input.mp4"
        )
        var segments: [VideoSegmentPlan] = []
        for offset in 0..<segmentCount {
            let startMilliseconds = Int64(offset) * 1_000
            let endMilliseconds = Int64(offset + 1) * 1_000
            let outputPath = try SafeRelativePath(
                "input — Split/input-part-\(offset + 1)-of-\(segmentCount).mp4"
            )
            segments.append(VideoSegmentPlan(
                index: offset + 1,
                startMilliseconds: startMilliseconds,
                endMilliseconds: endMilliseconds,
                outputRelativePath: outputPath,
                estimatedBytes: 200_000,
                requiresReencoding: false
            ))
        }
        return VideoSplitPlan(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000016C")!,
            input: input,
            sourceFileIdentity: makeVideoSplitTestIdentity(byteCount: input.fileSize),
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: 300_000,
                    maxDurationMilliseconds: 1_200,
                    safetyRatio: 0.9,
                    requiredContainer: nil,
                    requiredVideoCodec: nil,
                    requiredAudioCodec: nil
                ),
                stripMetadata: true
            ),
            ruleSnapshot: nil,
            segments: segments
        )
    }
}

private struct StaticSplitFileValidator: LocalRegularMediaFileValidating {
    let identity: VideoSplitFileIdentity

    func validate(
        _ url: URL,
        expectedByteCount: Int64?
    ) throws -> LocalRegularMediaFileIdentity {
        _ = url
        guard expectedByteCount == nil || expectedByteCount == identity.byteCount else {
            throw LocalRegularMediaFileValidationError.fileSizeMismatch
        }
        return LocalRegularMediaFileIdentity(
            device: identity.device,
            inode: identity.inode,
            byteCount: identity.byteCount,
            modificationSeconds: identity.modificationSeconds,
            modificationNanoseconds: identity.modificationNanoseconds
        )
    }
}

private final class SequencedSplitFileValidator:
    LocalRegularMediaFileValidating,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let identities: [VideoSplitFileIdentity]
    private var offset = 0

    init(identities: [VideoSplitFileIdentity]) {
        self.identities = identities
    }

    func validate(
        _ url: URL,
        expectedByteCount: Int64?
    ) throws -> LocalRegularMediaFileIdentity {
        _ = url
        let identity = lock.withLock { () -> VideoSplitFileIdentity in
            let selected = identities[min(offset, identities.count - 1)]
            offset += 1
            return selected
        }
        guard expectedByteCount == nil || expectedByteCount == identity.byteCount else {
            throw LocalRegularMediaFileValidationError.fileSizeMismatch
        }
        return LocalRegularMediaFileIdentity(
            device: identity.device,
            inode: identity.inode,
            byteCount: identity.byteCount,
            modificationSeconds: identity.modificationSeconds,
            modificationNanoseconds: identity.modificationNanoseconds
        )
    }
}

private actor FakeVideoSplitProcessRunner: FFmpegProcessRunning {
    private let events: [FFmpegProcessEvent]
    private let exitCode: Int32
    private let materializedSegmentCount: Int
    private(set) var runCount = 0
    private(set) var capturedLimits: FFmpegProcessLimits?

    init(
        events: [FFmpegProcessEvent],
        exitCode: Int32,
        materializedSegmentCount: Int = 0
    ) {
        self.events = events
        self.exitCode = exitCode
        self.materializedSegmentCount = materializedSegmentCount
    }

    func run(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        try await run(
            jobID: jobID,
            command: command,
            limits: .legacy,
            eventHandler: eventHandler
        )
    }

    func run(
        jobID _: UUID,
        command: FFmpegCommand,
        limits: FFmpegProcessLimits,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        runCount += 1
        capturedLimits = limits
        if materializedSegmentCount > 0, let pattern = command.arguments.last {
            for ordinal in 1...materializedSegmentCount {
                let path = pattern.replacingOccurrences(
                    of: "%02d",
                    with: String(format: "%02d", ordinal)
                )
                try Data("segment".utf8).write(to: URL(fileURLWithPath: path))
            }
        }
        events.forEach(eventHandler)
        return FFmpegProcessResult(exitCode: exitCode)
    }

    func cancel(jobID _: UUID) async {}
}

private final class LockedSplitProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VideoSplitExecutionProgress] = []

    func append(_ value: VideoSplitExecutionProgress) {
        lock.withLock { storage.append(value) }
    }

    var values: [VideoSplitExecutionProgress] {
        lock.withLock { storage }
    }
}

private final class TemporarySplitDirectory {
    let url: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-SplitEngine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false
        )
        url = base
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
