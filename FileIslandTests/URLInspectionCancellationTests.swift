import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("URL inspection cancellation")
struct URLInspectionCancellationTests {
    @Test("Cancelling inspection propagates into its detached worker")
    func inspectorPropagatesCancellationToWorker() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-inspection-\(UUID().uuidString).png")
        try Data([0x01]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = SynchronousInspectionGate()
        let inspector = URLFileInspector { _ in
            gate.enterAndWait()
            return UTType.png
        }
        let task = Task { try await inspector.inspect(urls: [url]) }
        await gate.waitUntilEntered()

        task.cancel()
        gate.release()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Cancelling a scan propagates into its active inspector")
    func scannerPropagatesCancellationToInspector() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-scan-\(UUID().uuidString).png")
        try Data([0x01]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let inspector = CancellableBlockingFileInspector()
        let scanner = URLInputScanner(fileInspector: inspector)
        let task = Task { try await scanner.scan(urls: [url]) }
        await inspector.waitUntilStarted()

        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await inspector.wasCancelled)
    }
}

private final class SynchronousInspectionGate: @unchecked Sendable {
    private let stateLock = NSLock()
    private let blockingCondition = NSCondition()
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() {
        let pending = stateLock.withLock { () -> [CheckedContinuation<Void, Never>] in
            entered = true
            let pending = waiters
            waiters.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }

        blockingCondition.lock()
        while !released { blockingCondition.wait() }
        blockingCondition.unlock()
    }

    func waitUntilEntered() async {
        if stateLock.withLock({ entered }) { return }
        await withCheckedContinuation { continuation in
            let resumeImmediately = stateLock.withLock {
                guard !entered else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    func release() {
        blockingCondition.lock()
        released = true
        blockingCondition.broadcast()
        blockingCondition.unlock()
    }
}

private actor CancellableBlockingFileInspector: FileInspecting {
    private var started = false
    private var cancelled = false
    private var cancellationRequested = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<[InputFile], any Error>?

    var wasCancelled: Bool { cancelled }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func inspect(urls _: [URL]) async throws -> [InputFile] {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if cancellationRequested || Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    resultContinuation = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelPendingInspection() }
        }
    }

    private func cancelPendingInspection() {
        cancellationRequested = true
        cancelled = true
        resultContinuation?.resume(throwing: CancellationError())
        resultContinuation = nil
    }
}
