import Foundation
import Testing
@testable import FileIsland

struct FoundationFFmpegProcessRunnerBoundedTests {
    @Test
    func productionProfilesHaveDocumentedFiniteBounds() {
        let version = FFmpegProcessLimits.versionValidation
        #expect(version.timeout == .seconds(10))
        #expect(version.inactivityTimeout == nil)
        #expect(version.terminationGracePeriod == .seconds(2))
        #expect(version.maximumStandardOutputBytes == 256 * 1_024)
        #expect(version.maximumStandardErrorBytes == 256 * 1_024)

        let conversion = FFmpegProcessLimits.conversion
        #expect(conversion.timeout == nil)
        #expect(conversion.inactivityTimeout == .seconds(5 * 60))
        #expect(conversion.terminationGracePeriod == .seconds(2))
        #expect(conversion.maximumStandardOutputBytes == 256 * 1_024 * 1_024)
        #expect(conversion.maximumStandardErrorBytes == 8 * 1_024 * 1_024)
    }

    @Test(.timeLimit(.minutes(1)))
    func processResultWaitsForAnInFlightOutputHandlerAfterTermination() async throws {
        let handlerEntered = AsyncTestLatch()
        let releaseHandler = DispatchSemaphore(value: 0)
        let terminationObserved = AsyncTestLatch()
        let lifecycleRecorder = ProcessLifecycleRecorder()
        let recorder = ProcessByteRecorder()
        let runner = FoundationFFmpegProcessRunner(
            terminationObserver: { _ in terminationObserved.signal() },
            finalizationObserver: { _ in lifecycleRecorder.recordFinalization() }
        )
        let jobID = UUID()
        let task = Task {
            try await runner.run(
                jobID: jobID,
                command: FFmpegCommand(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "printf delayed-output; exec /bin/sleep 30"]
                ),
                limits: .test
            ) { event in
                handlerEntered.signal()
                releaseHandler.wait()
                recorder.record(event)
            }
        }
        defer { releaseHandler.signal() }

        await handlerEntered.wait()
        let cancellation = Task {
            await runner.cancel(jobID: jobID)
        }
        await terminationObserved.wait()

        #expect(lifecycleRecorder.finalizationCount == 0)
        #expect(await runner.hasActiveProcess(jobID: jobID))
        #expect(recorder.standardOutputCount == 0)

        releaseHandler.signal()
        await cancellation.value
        await expectFailure(.cancelled) { try await task.value }
        #expect(lifecycleRecorder.finalizationCount == 1)
        #expect(recorder.standardOutputCount == "delayed-output".utf8.count)
        #expect(await runner.hasActiveProcess(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelBeforeLaunchFailsWithoutStartingAProcess() async {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()
        await runner.cancel(jobID: jobID)

        await expectFailure(.cancelled) {
            try await runner.run(
                jobID: jobID,
                command: Self.sleepCommand,
                limits: .test
            ) { _ in }
        }
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func duplicateJobIDFailsWhileOriginalProcessKeepsRunning() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()
        let original = Task {
            try await runner.run(
                jobID: jobID,
                command: Self.sleepCommand,
                limits: .test
            ) { _ in }
        }
        try await waitUntilRunning(runner, jobID: jobID)

        await expectFailure(.duplicateJobID) {
            try await runner.run(
                jobID: jobID,
                command: Self.sleepCommand,
                limits: .test
            ) { _ in }
        }
        #expect(await runner.isRunning(jobID: jobID))

        await runner.cancel(jobID: jobID)
        await expectFailure(.cancelled) { try await original.value }
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitCancellationWaitsForCooperativeChildExit() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()
        let task = Task {
            try await runner.run(
                jobID: jobID,
                command: Self.sleepCommand,
                limits: .test
            ) { _ in }
        }
        try await waitUntilRunning(runner, jobID: jobID)

        await runner.cancel(jobID: jobID)

        await expectFailure(.cancelled) { try await task.value }
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationEscalatesWhenChildIgnoresSIGTERM() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()
        let task = Task {
            try await runner.run(
                jobID: jobID,
                command: FFmpegCommand(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "trap '' TERM; exec /bin/sleep 30"]
                ),
                limits: FFmpegProcessLimits(
                    timeout: nil,
                    terminationGracePeriod: .milliseconds(40),
                    maximumStandardOutputBytes: 1_024,
                    maximumStandardErrorBytes: 1_024
                )
            ) { _ in }
        }
        try await waitUntilRunning(runner, jobID: jobID)

        let elapsed = await ContinuousClock().measure {
            await runner.cancel(jobID: jobID)
        }

        await expectFailure(.cancelled) { try await task.value }
        #expect(elapsed < .seconds(2))
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutHasASeparateFailureAndCleansUpTheProcess() async {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()

        await expectFailure(.timedOut) {
            try await runner.run(
                jobID: jobID,
                command: Self.sleepCommand,
                limits: FFmpegProcessLimits(
                    timeout: .milliseconds(40),
                    terminationGracePeriod: .milliseconds(40),
                    maximumStandardOutputBytes: 1_024,
                    maximumStandardErrorBytes: 1_024
                )
            ) { _ in }
        }
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func inactivityTimeoutTerminatesAChildThatNeverProducesOutput() async {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()

        await expectFailure(.timedOut) {
            try await runner.run(
                jobID: jobID,
                command: Self.sleepCommand,
                limits: FFmpegProcessLimits(
                    timeout: nil,
                    inactivityTimeout: .milliseconds(80),
                    terminationGracePeriod: .milliseconds(40),
                    maximumStandardOutputBytes: 1_024,
                    maximumStandardErrorBytes: 1_024
                )
            ) { _ in }
        }
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicOutputKeepsTheChildAlivePastOneInactivityInterval() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let result = try await runner.run(
            jobID: UUID(),
            command: FFmpegCommand(
                executableURL: URL(fileURLWithPath: "/bin/sh"),
                arguments: [
                    "-c",
                    "i=0; while [ \"$i\" -lt 20 ]; do printf x; /bin/sleep 0.02; i=$((i+1)); done"
                ]
            ),
            limits: FFmpegProcessLimits(
                timeout: .seconds(2),
                inactivityTimeout: .milliseconds(150),
                terminationGracePeriod: .milliseconds(40),
                maximumStandardOutputBytes: 1_024,
                maximumStandardErrorBytes: 1_024
            )
        ) { _ in }

        #expect(result.exitCode == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func inactivityTimeoutStartsAgainAfterTheLastOutputChunk() async {
        let runner = FoundationFFmpegProcessRunner()

        await expectFailure(.timedOut) {
            try await runner.run(
                jobID: UUID(),
                command: FFmpegCommand(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "printf active; exec /bin/sleep 30"]
                ),
                limits: FFmpegProcessLimits(
                    timeout: nil,
                    inactivityTimeout: .milliseconds(80),
                    terminationGracePeriod: .milliseconds(40),
                    maximumStandardOutputBytes: 1_024,
                    maximumStandardErrorBytes: 1_024
                )
            ) { _ in }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func standardOutputLimitTerminatesAChattyChildWithoutOverDelivery() async {
        let runner = FoundationFFmpegProcessRunner()
        let recorder = ProcessByteRecorder()
        let limit = 64

        await expectFailure(.outputLimitExceeded(.standardOutput)) {
            try await runner.run(
                jobID: UUID(),
                command: FFmpegCommand(
                    executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
                    arguments: []
                ),
                limits: FFmpegProcessLimits(
                    timeout: .seconds(2),
                    terminationGracePeriod: .milliseconds(40),
                    maximumStandardOutputBytes: limit,
                    maximumStandardErrorBytes: 1_024
                )
            ) { event in
                recorder.record(event)
            }
        }
        #expect(recorder.standardOutputCount == limit)
    }

    @Test(.timeLimit(.minutes(1)))
    func standardErrorLimitTerminatesAChattyChildWithoutOverDelivery() async {
        let runner = FoundationFFmpegProcessRunner()
        let recorder = ProcessByteRecorder()
        let limit = 64

        await expectFailure(.outputLimitExceeded(.standardError)) {
            try await runner.run(
                jobID: UUID(),
                command: FFmpegCommand(
                    executableURL: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "exec /usr/bin/yes error >&2"]
                ),
                limits: FFmpegProcessLimits(
                    timeout: .seconds(2),
                    terminationGracePeriod: .milliseconds(40),
                    maximumStandardOutputBytes: 1_024,
                    maximumStandardErrorBytes: limit
                )
            ) { event in
                recorder.record(event)
            }
        }
        #expect(recorder.standardErrorCount == limit)
    }

    @Test
    func launchFailureIsTypedAndLeavesNoActiveProcess() async {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()

        await expectFailure(.launchFailed) {
            try await runner.run(
                jobID: jobID,
                command: FFmpegCommand(
                    executableURL: URL(fileURLWithPath: "/path/that/does/not/exist"),
                    arguments: []
                ),
                limits: .test
            ) { _ in }
        }
        #expect(await runner.isRunning(jobID: jobID) == false)
    }

    private static let sleepCommand = FFmpegCommand(
        executableURL: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["30"]
    )

    private func waitUntilRunning(
        _ runner: FoundationFFmpegProcessRunner,
        jobID: UUID
    ) async throws {
        for _ in 0..<1_000 {
            if await runner.isRunning(jobID: jobID) { return }
            await Task.yield()
        }
        Issue.record("The child process did not enter the running state.")
        throw WaitError.processDidNotStart
    }

    private func expectFailure<T: Sendable>(
        _ expected: FFmpegProcessFailure,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected process failure: \(expected)")
        } catch let failure as FFmpegProcessFailure {
            #expect(failure == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private extension FFmpegProcessLimits {
    static let test = FFmpegProcessLimits(
        timeout: .seconds(2),
        terminationGracePeriod: .milliseconds(40),
        maximumStandardOutputBytes: 1_024,
        maximumStandardErrorBytes: 1_024
    )
}

private enum WaitError: Error {
    case processDidNotStart
}

private final class AsyncTestLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
            guard !isSignalled else { return [] }
            isSignalled = true
            defer { waiters.removeAll() }
            return waiters
        }
        continuations.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = lock.withLock {
                if isSignalled {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }
}

private final class ProcessLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func recordFinalization() {
        lock.withLock {
            count += 1
        }
    }

    var finalizationCount: Int { lock.withLock { count } }
}

private final class ProcessByteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var outputCount = 0
    private var errorCount = 0

    func record(_ event: FFmpegProcessEvent) {
        lock.withLock {
            switch event {
            case let .standardOutput(data):
                outputCount += data.count
            case let .standardError(data):
                errorCount += data.count
            }
        }
    }

    var standardOutputCount: Int { lock.withLock { outputCount } }
    var standardErrorCount: Int { lock.withLock { errorCount } }
}
