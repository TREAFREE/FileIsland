import Darwin
import Foundation

actor FoundationFFmpegProcessRunner: FFmpegProcessRunning {
    private struct ActiveProcess {
        let process: Process
        let outputState: FFmpegProcessOutputState
        let continuation: CheckedContinuation<FFmpegProcessResult, any Error>
        var timeoutTask: Task<Void, Never>?
        var inactivityTask: Task<Void, Never>?
        var escalationTask: Task<Void, Never>?
        var terminationRequested = false
    }

    private var activeProcesses: [UUID: ActiveProcess] = [:]
    private var cancelledJobIDs: Set<UUID> = []
    private var cancellationWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]
    private let terminationObserver: @Sendable (UUID) -> Void
    private let finalizationObserver: @Sendable (UUID) -> Void

    init(
        terminationObserver: @Sendable @escaping (UUID) -> Void = { _ in },
        finalizationObserver: @Sendable @escaping (UUID) -> Void = { _ in }
    ) {
        self.terminationObserver = terminationObserver
        self.finalizationObserver = finalizationObserver
    }

    func run(
        jobID: UUID,
        command: FFmpegCommand,
        limits: FFmpegProcessLimits,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        guard !Task.isCancelled else { throw FFmpegProcessFailure.cancelled }
        guard cancelledJobIDs.remove(jobID) == nil else {
            throw FFmpegProcessFailure.cancelled
        }
        guard activeProcesses[jobID] == nil else {
            throw FFmpegProcessFailure.duplicateJobID
        }

        return try await withTaskCancellationHandler {
            try await launch(
                jobID: jobID,
                command: command,
                limits: limits,
                eventHandler: eventHandler
            )
        } onCancel: {
            Task { await self.cancel(jobID: jobID) }
        }
    }

    func cancel(jobID: UUID) async {
        guard activeProcesses[jobID] != nil else {
            cancelledJobIDs.insert(jobID)
            return
        }

        requestTermination(jobID: jobID, failure: .cancelled)
        await withCheckedContinuation { continuation in
            cancellationWaiters[jobID, default: []].append(continuation)
        }
    }

    /// An observation seam for deterministic process lifecycle tests.
    func isRunning(jobID: UUID) -> Bool {
        activeProcesses[jobID]?.process.isRunning == true
    }

    /// An observation seam for deterministic read-drain lifecycle tests.
    func hasActiveProcess(jobID: UUID) -> Bool {
        activeProcesses[jobID] != nil
    }

    private func launch(
        jobID: UUID,
        command: FFmpegCommand,
        limits: FFmpegProcessLimits,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            let outputState = FFmpegProcessOutputState(limits: limits)
            let readDrainGate = FFmpegProcessReadDrainGate()
            let terminationObserver = self.terminationObserver
            let finalizationObserver = self.finalizationObserver

            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = standardOutput
            process.standardError = standardError

            standardOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard readDrainGate.beginRead() else { return }
                defer { readDrainGate.endRead() }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let failure = outputState.consume(
                    stream: .standardOutput,
                    data: data,
                    eventHandler: eventHandler
                ) {
                    Task { await self?.requestTermination(jobID: jobID, failure: failure) }
                }
            }
            standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard readDrainGate.beginRead() else { return }
                defer { readDrainGate.endRead() }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let failure = outputState.consume(
                    stream: .standardError,
                    data: data,
                    eventHandler: eventHandler
                ) {
                    Task { await self?.requestTermination(jobID: jobID, failure: failure) }
                }
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                let runner = self
                readDrainGate.beginClosing()
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                let exitCode = terminatedProcess.terminationStatus
                readDrainGate.finalizeWhenDrained {
                    finalizationObserver(jobID)
                    let outputTail = standardOutput.fileHandleForReading.readDataToEndOfFile()
                    let errorTail = standardError.fileHandleForReading.readDataToEndOfFile()
                    _ = outputState.consume(
                        stream: .standardOutput,
                        data: outputTail,
                        eventHandler: eventHandler
                    )
                    _ = outputState.consume(
                        stream: .standardError,
                        data: errorTail,
                        eventHandler: eventHandler
                    )
                    Task { await runner?.finish(jobID: jobID, exitCode: exitCode) }
                }
                terminationObserver(jobID)
            }

            activeProcesses[jobID] = ActiveProcess(
                process: process,
                outputState: outputState,
                continuation: continuation
            )

            do {
                try process.run()
            } catch {
                readDrainGate.beginClosing()
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                activeProcesses[jobID] = nil
                outputState.record(failure: .launchFailed)
                continuation.resume(throwing: FFmpegProcessFailure.launchFailed)
                return
            }

            if let timeout = limits.timeout {
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.requestTermination(jobID: jobID, failure: .timedOut)
                }
                activeProcesses[jobID]?.timeoutTask = timeoutTask
            }

            if let inactivityTimeout = limits.inactivityTimeout {
                let inactivityTask = Task { [weak self, outputState] in
                    guard let self else { return }
                    await self.monitorInactivity(
                        jobID: jobID,
                        timeout: inactivityTimeout,
                        outputState: outputState
                    )
                }
                activeProcesses[jobID]?.inactivityTask = inactivityTask
            }
        }
    }

    private func monitorInactivity(
        jobID: UUID,
        timeout: Duration,
        outputState: FFmpegProcessOutputState
    ) async {
        var observed = outputState.activitySnapshot
        let clock = ContinuousClock()

        while !Task.isCancelled {
            let elapsed = observed.instant.duration(to: clock.now)
            let remaining = max(.zero, timeout - elapsed)
            if remaining > .zero {
                do {
                    try await Task.sleep(for: remaining)
                } catch {
                    return
                }
            }

            guard let active = activeProcesses[jobID],
                  active.outputState === outputState,
                  !active.terminationRequested else { return }

            let latest = outputState.activitySnapshot
            if latest.generation != observed.generation {
                observed = latest
                continue
            }
            if latest.instant.duration(to: clock.now) >= timeout {
                requestTermination(jobID: jobID, failure: .timedOut)
                return
            }

            observed = latest
        }
    }

    private func requestTermination(
        jobID: UUID,
        failure: FFmpegProcessFailure
    ) {
        guard var active = activeProcesses[jobID],
              active.process.isRunning else { return }
        active.outputState.record(failure: failure)
        guard !active.terminationRequested else { return }

        active.terminationRequested = true
        let processID = active.process.processIdentifier
        let gracePeriod = active.outputState.limits.terminationGracePeriod
        let escalationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: gracePeriod)
            } catch {
                return
            }
            await self?.forceKillIfRunning(jobID: jobID, processID: processID)
        }
        active.escalationTask = escalationTask
        activeProcesses[jobID] = active

        if active.process.isRunning {
            active.process.terminate()
        }
    }

    private func forceKillIfRunning(jobID: UUID, processID: Int32) {
        guard let active = activeProcesses[jobID],
              active.process.processIdentifier == processID,
              active.process.isRunning else { return }
        _ = Darwin.kill(processID, SIGKILL)
    }

    private func finish(jobID: UUID, exitCode: Int32) {
        guard let active = activeProcesses.removeValue(forKey: jobID) else { return }
        active.timeoutTask?.cancel()
        active.inactivityTask?.cancel()
        active.escalationTask?.cancel()

        let waiters = cancellationWaiters.removeValue(forKey: jobID) ?? []
        waiters.forEach { $0.resume() }

        if let failure = active.outputState.failure {
            active.continuation.resume(throwing: failure)
        } else {
            active.continuation.resume(
                returning: FFmpegProcessResult(exitCode: exitCode)
            )
        }
    }

}

/// Serializes process termination with any stdout/stderr callback that has
/// already entered. Closing rejects future reads; finalization runs once after
/// every accepted callback has returned, so tail draining cannot race a read.
private final class FFmpegProcessReadDrainGate: @unchecked Sendable {
    private typealias Finalizer = @Sendable () -> Void

    private let lock = NSLock()
    private var isClosing = false
    private var inFlightReadCount = 0
    private var pendingFinalizer: Finalizer?
    private var didFinalize = false

    func beginRead() -> Bool {
        lock.withLock {
            guard !isClosing else { return false }
            inFlightReadCount += 1
            return true
        }
    }

    func endRead() {
        let finalizer: Finalizer? = lock.withLock {
            precondition(inFlightReadCount > 0)
            inFlightReadCount -= 1
            return takeFinalizerIfReady()
        }
        finalizer?()
    }

    func beginClosing() {
        lock.withLock {
            isClosing = true
        }
    }

    func finalizeWhenDrained(_ finalizer: @escaping @Sendable () -> Void) {
        let readyFinalizer: Finalizer? = lock.withLock {
            guard !didFinalize, pendingFinalizer == nil else { return nil }
            pendingFinalizer = finalizer
            return takeFinalizerIfReady()
        }
        readyFinalizer?()
    }

    private func takeFinalizerIfReady() -> Finalizer? {
        guard isClosing,
              inFlightReadCount == 0,
              !didFinalize,
              let finalizer = pendingFinalizer else { return nil }
        didFinalize = true
        pendingFinalizer = nil
        return finalizer
    }
}

private final class FFmpegProcessOutputState: @unchecked Sendable {
    struct ActivitySnapshot: Sendable {
        let generation: UInt64
        let instant: ContinuousClock.Instant
    }

    let limits: FFmpegProcessLimits

    private let lock = NSLock()
    private var standardOutputBytes = 0
    private var standardErrorBytes = 0
    private var terminalFailure: FFmpegProcessFailure?
    private var activityGeneration: UInt64 = 0
    private var lastActivityInstant = ContinuousClock().now

    init(limits: FFmpegProcessLimits) {
        self.limits = limits
    }

    @discardableResult
    func record(failure: FFmpegProcessFailure) -> Bool {
        lock.withLock {
            guard terminalFailure == nil else { return false }
            terminalFailure = failure
            return true
        }
    }

    func consume(
        stream: FFmpegProcessStream,
        data: Data,
        eventHandler: @Sendable (FFmpegProcessEvent) -> Void
    ) -> FFmpegProcessFailure? {
        guard !data.isEmpty else { return nil }

        let outcome: (delivery: Data, failure: FFmpegProcessFailure?) = lock.withLock {
            guard terminalFailure == nil else { return (Data(), nil) }
            activityGeneration &+= 1
            lastActivityInstant = ContinuousClock().now

            let maximum: Int
            let consumed: Int
            switch stream {
            case .standardOutput:
                maximum = limits.maximumStandardOutputBytes
                consumed = standardOutputBytes
            case .standardError:
                maximum = limits.maximumStandardErrorBytes
                consumed = standardErrorBytes
            }
            let remaining = max(0, maximum - consumed)
            let delivery = Data(data.prefix(remaining))

            switch stream {
            case .standardOutput:
                standardOutputBytes += delivery.count
            case .standardError:
                standardErrorBytes += delivery.count
            }

            guard data.count > remaining else { return (delivery, nil) }
            let failure = FFmpegProcessFailure.outputLimitExceeded(stream)
            terminalFailure = failure
            return (delivery, failure)
        }

        if !outcome.delivery.isEmpty {
            switch stream {
            case .standardOutput:
                eventHandler(.standardOutput(outcome.delivery))
            case .standardError:
                eventHandler(.standardError(outcome.delivery))
            }
        }
        return outcome.failure
    }

    var failure: FFmpegProcessFailure? {
        lock.withLock { terminalFailure }
    }

    var activitySnapshot: ActivitySnapshot {
        lock.withLock {
            ActivitySnapshot(
                generation: activityGeneration,
                instant: lastActivityInstant
            )
        }
    }
}
