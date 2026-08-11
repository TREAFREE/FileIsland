import Foundation
import XCTest
@testable import FileIsland

final class FoundationFFmpegProcessRunnerTests: XCTestCase {
    func testReturnsExitStatusAndDrainsStdout() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let recorder = ProcessEventRecorder()
        let command = FFmpegCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["progress=end\\n"]
        )

        let result = try await runner.run(jobID: UUID(), command: command) { event in
            Task { await recorder.record(event) }
        }

        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(result.exitCode, 0)
        let stdout = await recorder.stdout
        XCTAssertEqual(String(decoding: stdout, as: UTF8.self), "progress=end\n")
    }

    func testReturnsNonzeroExitAndDrainsStderr() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let recorder = ProcessEventRecorder()
        let command = FFmpegCommand(
            executableURL: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/path-that-does-not-exist-fileisland"]
        )

        let result = try await runner.run(jobID: UUID(), command: command) { event in
            Task { await recorder.record(event) }
        }

        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNotEqual(result.exitCode, 0)
        let stderr = await recorder.stderr
        XCTAssertTrue(String(decoding: stderr, as: UTF8.self).contains("path-that-does-not-exist"))
    }

    func testCancelTerminatesRunningChildAndWaitsForExit() async throws {
        let runner = FoundationFFmpegProcessRunner()
        let jobID = UUID()
        let command = FFmpegCommand(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"]
        )
        let task = Task {
            try await runner.run(jobID: jobID, command: command) { _ in }
        }

        try await Task.sleep(for: .milliseconds(50))
        await runner.cancel(jobID: jobID)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? FFmpegProcessFailure, .cancelled)
        }
    }
}

private actor ProcessEventRecorder {
    private(set) var stdout = Data()
    private(set) var stderr = Data()

    func record(_ event: FFmpegProcessEvent) {
        switch event {
        case let .standardOutput(data): stdout.append(data)
        case let .standardError(data): stderr.append(data)
        }
    }
}
