import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

struct FFprobeVideoSplitProbeTests {
    @Test
    func productionProbeUsesTwoBoundedExplicitCommandsAndReturnsAuditedFacts() async throws {
        let fixture = try ProbeFixture()
        defer { fixture.remove() }
        let runner = ScriptedFFprobeRunner(responses: [
            .success(stdout: Self.metadataJSON),
            .success(stdout: Data(
                "pts_time=1.000000|flags=K__\npts_time=2.000000|flags=___\npts_time=5.000000|flags=K__\n".utf8
            ))
        ])
        let probe = FFprobeVideoSplitProbe(
            executableURL: fixture.executableURL,
            processRunner: runner
        )

        let facts = try await probe.probe(fixture.input)

        #expect(facts.inputID == fixture.input.id)
        #expect(facts.sourceURL == fixture.input.url)
        #expect(facts.durationMilliseconds == 10_000)
        #expect(facts.displayWidth == 1_080)
        #expect(facts.displayHeight == 1_920)
        #expect(facts.rotationDegrees == 90)
        #expect(facts.container == "mp4")
        #expect(facts.videoCodec == "h264")
        #expect(facts.audioCodec == "aac")
        #expect(facts.videoStartMilliseconds == 1_000)
        #expect(facts.audioStartMilliseconds == 1_010)
        #expect(facts.audioDurationMilliseconds == 9_990)
        #expect(facts.userMetadataKeys == ["title"])
        #expect(facts.keyframeMilliseconds == [0, 4_000])

        let calls = await runner.recordedCalls()
        #expect(calls.count == 2)
        #expect(calls.allSatisfy { $0.command.executableURL == fixture.executableURL })
        #expect(calls[0].command.arguments.contains("-show_streams"))
        #expect(calls[1].command.arguments.contains("-show_packets"))
        #expect(calls.allSatisfy { Array($0.command.arguments.suffix(2)) == ["--", fixture.input.url.path] })
        #expect(calls[0].limits.maximumStandardOutputBytes == 256 * 1_024)
        #expect(calls[1].limits.maximumStandardOutputBytes == 16 * 1_024 * 1_024)
    }

    @Test
    func productionProbeMapsTimeoutWithoutLeakingTheInputPath() async throws {
        let fixture = try ProbeFixture()
        defer { fixture.remove() }
        let runner = ScriptedFFprobeRunner(responses: [
            .failure(.timedOut)
        ])
        let probe = FFprobeVideoSplitProbe(
            executableURL: fixture.executableURL,
            processRunner: runner
        )

        do {
            _ = try await probe.probe(fixture.input)
            Issue.record("Expected the timeout to be mapped")
        } catch let error as VideoSplitProbeError {
            #expect(error == .probeTimedOut)
            #expect(String(describing: error).contains(fixture.input.url.path) == false)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private static let metadataJSON = Data(
        """
        {
          "streams": [
            {"codec_type":"video","codec_name":"h264","width":1920,"height":1080,"avg_frame_rate":"30/1","start_time":"1.0","side_data_list":[{"rotation":90}]},
            {"codec_type":"audio","codec_name":"aac","start_time":"1.01","duration":"9.99"}
          ],
          "format":{"format_name":"mov,mp4,m4a,3gp,3g2,mj2","duration":"10.0","start_time":"1.0","bit_rate":"8000000","tags":{"title":"Private title","encoder":"technical"}}
        }
        """.utf8
    )
}

private struct ProbeFixture: Sendable {
    let directory: URL
    let executableURL: URL
    let input: InputFile

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        executableURL = directory.appendingPathComponent("ffprobe")
        guard FileManager.default.createFile(atPath: executableURL.path, contents: Data()) else {
            throw ProbeFixtureError.creationFailed
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: executableURL.path
        )

        let inputURL = directory.appendingPathComponent("private-input.mp4")
        let data = Data(repeating: 0xA5, count: 32)
        try data.write(to: inputURL)
        input = InputFile(
            url: inputURL,
            type: .mpeg4Movie,
            fileSize: Int64(data.count),
            displayName: "private-input.mp4"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum ProbeFixtureError: Error {
    case creationFailed
}

private actor ScriptedFFprobeRunner: FFmpegProcessRunning {
    struct Call: Equatable, Sendable {
        let command: FFmpegCommand
        let limits: FFmpegProcessLimits
    }

    enum Response: Sendable {
        case success(stdout: Data, stderr: Data = Data(), exitCode: Int32 = 0)
        case failure(FFmpegProcessFailure)
    }

    private var responses: [Response]
    private var calls: [Call] = []

    init(responses: [Response]) {
        self.responses = responses
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
        calls.append(Call(command: command, limits: limits))
        guard !responses.isEmpty else { throw FFmpegProcessFailure.launchFailed }
        switch responses.removeFirst() {
        case let .success(stdout, stderr, exitCode):
            if !stdout.isEmpty { eventHandler(.standardOutput(stdout)) }
            if !stderr.isEmpty { eventHandler(.standardError(stderr)) }
            return FFmpegProcessResult(exitCode: exitCode)
        case let .failure(error):
            throw error
        }
    }

    func cancel(jobID _: UUID) async {}

    func recordedCalls() -> [Call] { calls }
}
