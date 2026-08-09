import Foundation

actor FoundationFFmpegProcessRunner: FFmpegProcessRunning {
    private var activeProcesses: [UUID: Process] = [:]
    private var cancelledJobIDs: Set<UUID> = []
    private var cancellationWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func run(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        try Task.checkCancellation()
        guard cancelledJobIDs.remove(jobID) == nil else {
            throw ConversionError.cancelled
        }
        guard activeProcesses[jobID] == nil else {
            throw ConversionError.conversionFailed(underlying: "A conversion process is already running.")
        }

        return try await withTaskCancellationHandler {
            try await launch(
                jobID: jobID,
                command: command,
                eventHandler: eventHandler
            )
        } onCancel: {
            Task { await self.cancel(jobID: jobID) }
        }
    }

    func cancel(jobID: UUID) async {
        guard let process = activeProcesses[jobID] else {
            cancelledJobIDs.insert(jobID)
            return
        }
        cancelledJobIDs.insert(jobID)

        await withCheckedContinuation { continuation in
            cancellationWaiters[jobID, default: []].append(continuation)
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func launch(
        jobID: UUID,
        command: FFmpegCommand,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.executableURL = command.executableURL
            process.arguments = command.arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = standardOutput
            process.standardError = standardError

            standardOutput.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    eventHandler(.standardOutput(data))
                }
            }
            standardError.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    eventHandler(.standardError(data))
                }
            }

            process.terminationHandler = { [weak self] terminatedProcess in
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                let outputTail = standardOutput.fileHandleForReading.readDataToEndOfFile()
                let errorTail = standardError.fileHandleForReading.readDataToEndOfFile()
                if !outputTail.isEmpty { eventHandler(.standardOutput(outputTail)) }
                if !errorTail.isEmpty { eventHandler(.standardError(errorTail)) }
                let exitCode = terminatedProcess.terminationStatus
                Task {
                    await self?.finish(
                        jobID: jobID,
                        exitCode: exitCode,
                        continuation: continuation
                    )
                }
            }

            activeProcesses[jobID] = process
            do {
                try process.run()
            } catch {
                standardOutput.fileHandleForReading.readabilityHandler = nil
                standardError.fileHandleForReading.readabilityHandler = nil
                activeProcesses[jobID] = nil
                continuation.resume(throwing: ConversionError.engineUnavailable)
            }
        }
    }

    private func finish(
        jobID: UUID,
        exitCode: Int32,
        continuation: CheckedContinuation<FFmpegProcessResult, Error>
    ) {
        activeProcesses[jobID] = nil
        let wasCancelled = cancelledJobIDs.remove(jobID) != nil
        let waiters = cancellationWaiters.removeValue(forKey: jobID) ?? []
        waiters.forEach { $0.resume() }

        if wasCancelled {
            continuation.resume(throwing: ConversionError.cancelled)
        } else {
            continuation.resume(returning: FFmpegProcessResult(exitCode: exitCode))
        }
    }
}
