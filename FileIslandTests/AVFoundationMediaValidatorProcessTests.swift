import Foundation
import Testing
@testable import FileIsland

@Suite("Isolated AVFoundation first-frame validation")
struct AVFoundationMediaValidatorProcessTests {
    @Test("The embedded helper decodes the audited video fixture")
    func embeddedHelperDecodesAuditedFixture() async throws {
        let helperURL = try #require(Self.embeddedHelperURL())
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/task016-keyframes.mp4")

        let accepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: helperURL
        ).canDecodeFirstFrame(at: fixtureURL)

        #expect(accepted)
    }

    @Test("The embedded helper rejects arbitrary bytes without exposing their path")
    func embeddedHelperRejectsInvalidMedia() async throws {
        let helperURL = try #require(Self.embeddedHelperURL())
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateName = "private-personal-movie.mp4"
        let invalidURL = directory.appendingPathComponent(privateName)
        try Data([0x00, 0x01, 0x02]).write(to: invalidURL)

        let accepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: helperURL
        ).canDecodeFirstFrame(at: invalidURL)

        #expect(accepted == false)
    }

    @Test("Helper protocol output is fixed, bounded, and path-free")
    func helperProtocolIsPathFree() throws {
        let helperURL = try #require(Self.embeddedHelperURL())
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let privateName = "private-personal-movie.mp4"
        let invalidURL = directory.appendingPathComponent(privateName)
        try Data([0x00, 0x01, 0x02]).write(to: invalidURL)

        let result = try Self.runHelper(helperURL, inputURL: invalidURL)

        #expect(result.exitCode == 2)
        #expect(
            result.standardOutput
                == Data("{\"decodable\":false,\"schemaVersion\":1}\n".utf8)
        )
        // AVFoundation/VideoToolbox may emit a short machine diagnostic on
        // stderr on restricted CI hosts. The protocol never reflects it back
        // to callers and, critically, it must not disclose the media path.
        #expect(result.standardError.count <= 64 * 1_024)
        let standardError = String(decoding: result.standardError, as: UTF8.self)
        #expect(standardError.contains(privateName) == false)
        #expect(standardError.contains(directory.path) == false)
        #expect(String(decoding: result.standardOutput, as: UTF8.self).contains(privateName) == false)
    }

    @Test("The helper itself rejects symbolic-link inputs")
    func helperRejectsSymbolicLinkInput() throws {
        let helperURL = try #require(Self.embeddedHelperURL())
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("private-target.mp4")
        let linkURL = directory.appendingPathComponent("private-link.mp4")
        try Data([0x00]).write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: linkURL,
            withDestinationURL: targetURL
        )

        let result = try Self.runHelper(helperURL, inputURL: linkURL)

        #expect(result.exitCode == 2)
        #expect(
            result.standardOutput
                == Data("{\"decodable\":false,\"schemaVersion\":1}\n".utf8)
        )
        let diagnostic = String(decoding: result.standardError, as: UTF8.self)
        #expect(diagnostic.contains(directory.path) == false)
    }

    @Test("The parent uses a fixed bounded process profile and a literal helper URL")
    func usesBoundedProcessProfile() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let helperURL = directory.appendingPathComponent("FileIslandMediaValidator")
        let inputURL = directory.appendingPathComponent("input.mp4")
        try Data([0x00]).write(to: helperURL)
        try Data([0x00]).write(to: inputURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )
        let runner = RecordingMediaValidatorProcessRunner(
            outcome: .success(
                exitCode: 0,
                standardOutput: Data(
                    "{\"decodable\":true,\"schemaVersion\":1}\n".utf8
                ),
                standardError: Data()
            )
        )

        let accepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: helperURL,
            processRunner: runner
        ).canDecodeFirstFrame(at: inputURL)

        #expect(accepted)
        let invocation = try #require(await runner.invocation())
        #expect(invocation.command.executableURL == helperURL)
        #expect(invocation.command.arguments == ["--first-frame", inputURL.path])
        #expect(invocation.limits == .avFoundationMediaValidation)
    }

    @Test("Timeout and malformed output fail closed")
    func timeoutAndMalformedOutputFailClosed() async throws {
        let fixture = try ProcessFixture()
        defer { fixture.remove() }

        let timeout = RecordingMediaValidatorProcessRunner(outcome: .failure(.timedOut))
        let timedOutAccepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: fixture.helperURL,
            processRunner: timeout
        ).canDecodeFirstFrame(at: fixture.inputURL)
        #expect(timedOutAccepted == false)

        let malformed = RecordingMediaValidatorProcessRunner(
            outcome: .success(
                exitCode: 0,
                standardOutput: Data("not-json".utf8),
                standardError: Data()
            )
        )
        let malformedAccepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: fixture.helperURL,
            processRunner: malformed
        ).canDecodeFirstFrame(at: fixture.inputURL)
        #expect(malformedAccepted == false)
    }

    @Test("Parent task cancellation terminates validation instead of becoming a decode failure")
    func cancellationPropagates() async throws {
        let fixture = try ProcessFixture()
        defer { fixture.remove() }
        let runner = RecordingMediaValidatorProcessRunner(outcome: .failure(.cancelled))
        let checker = AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: fixture.helperURL,
            processRunner: runner
        )

        await #expect(throws: CancellationError.self) {
            try await checker.canDecodeFirstFrame(at: fixture.inputURL)
        }
    }

    @Test("Symbolic-link media and helper paths are rejected before launch")
    func rejectsSymbolicLinksBeforeLaunch() async throws {
        let fixture = try ProcessFixture()
        defer { fixture.remove() }
        let inputLink = fixture.directory.appendingPathComponent("input-link.mp4")
        let helperLinkDirectory = fixture.directory.appendingPathComponent(
            "linked-helper",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: helperLinkDirectory,
            withIntermediateDirectories: false
        )
        let helperLink = helperLinkDirectory.appendingPathComponent(
            "FileIslandMediaValidator"
        )
        try FileManager.default.createSymbolicLink(
            at: inputLink,
            withDestinationURL: fixture.inputURL
        )
        try FileManager.default.createSymbolicLink(
            at: helperLink,
            withDestinationURL: fixture.helperURL
        )
        let runner = RecordingMediaValidatorProcessRunner(
            outcome: .success(
                exitCode: 0,
                standardOutput: Data(
                    "{\"decodable\":true,\"schemaVersion\":1}\n".utf8
                ),
                standardError: Data()
            )
        )

        let linkedInputAccepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: fixture.helperURL,
            processRunner: runner
        ).canDecodeFirstFrame(at: inputLink)
        let linkedHelperAccepted = try await AVFoundationVideoSplitSegmentDecodabilityChecker(
            helperExecutableURL: helperLink,
            processRunner: runner
        ).canDecodeFirstFrame(at: fixture.inputURL)

        #expect(linkedInputAccepted == false)
        #expect(linkedHelperAccepted == false)
        #expect(await runner.invocation() == nil)
    }

    private static func embeddedHelperURL() -> URL? {
        Bundle.main.url(forAuxiliaryExecutable: "FileIslandMediaValidator")
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-MediaValidatorTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false
        )
        return url
    }

    private static func runHelper(
        _ helperURL: URL,
        inputURL: URL
    ) throws -> HelperProcessResult {
        let standardOutput = Pipe()
        let standardError = Pipe()
        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["--first-frame", inputURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return HelperProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            standardError: standardError.fileHandleForReading.readDataToEndOfFile()
        )
    }
}

private struct HelperProcessResult {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

private struct ProcessFixture {
    let directory: URL
    let helperURL: URL
    let inputURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-MediaValidatorProcess-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        helperURL = directory.appendingPathComponent("FileIslandMediaValidator")
        inputURL = directory.appendingPathComponent("input.mp4")
        try Data([0x00]).write(to: helperURL)
        try Data([0x00]).write(to: inputURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor RecordingMediaValidatorProcessRunner: FFmpegProcessRunning {
    enum Outcome: Sendable {
        case success(exitCode: Int32, standardOutput: Data, standardError: Data)
        case failure(FFmpegProcessFailure)
    }

    struct Invocation: Equatable, Sendable {
        let command: FFmpegCommand
        let limits: FFmpegProcessLimits
    }

    private let outcome: Outcome
    private var capturedInvocation: Invocation?

    init(outcome: Outcome) {
        self.outcome = outcome
    }

    func run(
        jobID _: UUID,
        command: FFmpegCommand,
        limits: FFmpegProcessLimits,
        eventHandler: @Sendable @escaping (FFmpegProcessEvent) -> Void
    ) async throws -> FFmpegProcessResult {
        capturedInvocation = Invocation(command: command, limits: limits)
        switch outcome {
        case let .success(exitCode, standardOutput, standardError):
            if standardOutput.isEmpty == false {
                eventHandler(.standardOutput(standardOutput))
            }
            if standardError.isEmpty == false {
                eventHandler(.standardError(standardError))
            }
            return FFmpegProcessResult(exitCode: exitCode)
        case let .failure(error):
            throw error
        }
    }

    func cancel(jobID _: UUID) async {}

    func invocation() -> Invocation? {
        capturedInvocation
    }
}
