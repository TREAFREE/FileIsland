import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FileIsland

@Suite("Bundled fast split runtime integration", .serialized)
struct VideoSplitRuntimeIntegrationTests {
    @Test("Bundled runtime preserves every media packet and removes requested metadata")
    func splitsAuditedFixtureEndToEnd() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixture = repositoryRoot.appendingPathComponent(
            "FileIslandTests/Fixtures/task016-keyframes.mp4"
        )
        let ffmpeg = repositoryRoot.appendingPathComponent("Vendor/FFmpeg/ffmpeg")
        let ffprobe = repositoryRoot.appendingPathComponent("Vendor/FFmpeg/ffprobe")
        let mediaValidator = try #require(
            Bundle.main.url(forAuxiliaryExecutable: "FileIslandMediaValidator")
        )
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-SplitRuntime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: staging) }

        let byteCount = try #require(
            fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        let input = InputFile(
            url: fixture,
            type: .mpeg4Movie,
            fileSize: Int64(byteCount),
            displayName: fixture.lastPathComponent
        )
        let probe = FFprobeVideoSplitProbe(executableURL: ffprobe)
        let source = try await probe.probe(input)
        #expect(source.userMetadataKeys == ["comment", "title"])
        let plan = try VideoSplitPlanBuilder().makePlan(
            input: input,
            intent: VideoSplitIntent(
                source: .custom,
                mode: .fastKeyframeCopy,
                constraints: VideoSegmentConstraints(
                    maxBytes: nil,
                    maxDurationMilliseconds: 2_500,
                    safetyRatio: 0.8,
                    requiredContainer: nil,
                    requiredVideoCodec: nil,
                    requiredAudioCodec: nil
                ),
                stripMetadata: true
            ),
            source: source
        )
        #expect(plan.segments.count > 1)

        let progress = LockedRuntimeIntegrationProgress()
        let execution = try await FFmpegVideoSplitEngine(
            executableURL: ffmpeg
        ).execute(
            plan,
            stagingDirectory: staging,
            progress: progress.append
        )
        let validated = try await VideoSplitOutputValidator(
            probe: probe,
            decodabilityChecker: AVFoundationVideoSplitSegmentDecodabilityChecker(
                helperExecutableURL: mediaValidator
            )
        ).validate(
            plan: plan,
            source: source,
            stagedArtifacts: execution.artifacts,
            stagingRoot: staging
        )

        #expect(validated.segments.count == plan.segments.count)
        #expect(validated.segments.allSatisfy { $0.actualBytes > 0 })
        #expect(validated.segments.allSatisfy {
            $0.actualFacts.videoCodec == "h264" && $0.actualFacts.audioCodec == "aac"
        })
        #expect(validated.segments.allSatisfy { $0.actualFacts.userMetadataKeys.isEmpty })

        let sourceVideoPackets = try await packetHashes(
            ffprobe: ffprobe,
            file: fixture,
            stream: "v:0"
        )
        let sourceAudioPackets = try await packetHashes(
            ffprobe: ffprobe,
            file: fixture,
            stream: "a:0"
        )
        var segmentVideoPackets: [[String]] = []
        var segmentAudioPackets: [[String]] = []
        for artifact in execution.artifacts {
            segmentVideoPackets.append(
                try await packetHashes(
                    ffprobe: ffprobe,
                    file: artifact.fileURL,
                    stream: "v:0"
                )
            )
            segmentAudioPackets.append(
                try await packetHashes(
                    ffprobe: ffprobe,
                    file: artifact.fileURL,
                    stream: "a:0"
                )
            )
        }
        #expect(segmentVideoPackets.allSatisfy { $0.isEmpty == false })
        #expect(segmentAudioPackets.allSatisfy { $0.isEmpty == false })
        #expect(segmentVideoPackets.flatMap { $0 } == sourceVideoPackets)
        #expect(segmentAudioPackets.flatMap { $0 } == sourceAudioPackets)

        let fractions = progress.values.map(\.fraction)
        #expect(fractions.first == 0)
        #expect(fractions.last == 1)
        #expect(zip(fractions, fractions.dropFirst()).allSatisfy { $0 <= $1 })
    }

    private func packetHashes(
        ffprobe: URL,
        file: URL,
        stream: String
    ) async throws -> [String] {
        let collector = LockedPacketHashOutput()
        let result = try await FoundationFFmpegProcessRunner().run(
            jobID: UUID(),
            command: FFmpegCommand(
                executableURL: ffprobe,
                arguments: [
                    "-hide_banner",
                    "-v", "error",
                    "-select_streams", stream,
                    "-show_packets",
                    "-show_data_hash", "sha256",
                    "-show_entries", "packet=data_hash",
                    "-of", "compact=p=0:nk=1",
                    "--", file.path
                ]
            ),
            limits: FFmpegProcessLimits(
                timeout: .seconds(30),
                terminationGracePeriod: .seconds(2),
                maximumStandardOutputBytes: 8 * 1_024 * 1_024,
                maximumStandardErrorBytes: 64 * 1_024
            )
        ) { event in
            if case let .standardOutput(data) = event {
                collector.append(data)
            }
        }
        guard result.exitCode == 0 else {
            throw PacketHashEvidenceError.probeFailed
        }

        let records = String(decoding: collector.data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
        guard records.isEmpty == false else {
            throw PacketHashEvidenceError.emptyStream
        }
        return try records.map { record in
            let hash = record
                .split(separator: "|", maxSplits: 1)
                .first
                .map(String.init) ?? ""
            let digest = hash.dropFirst("SHA256:".count)
            guard hash.hasPrefix("SHA256:"),
                  digest.count == 64,
                  digest.allSatisfy({ $0.isHexDigit }) else {
                throw PacketHashEvidenceError.malformedHash
            }
            return hash
        }
    }
}

private final class LockedRuntimeIntegrationProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [VideoSplitExecutionProgress] = []

    func append(_ value: VideoSplitExecutionProgress) {
        lock.withLock { storage.append(value) }
    }

    var values: [VideoSplitExecutionProgress] {
        lock.withLock { storage }
    }
}

private final class LockedPacketHashOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }

    var data: Data {
        lock.withLock { storage }
    }
}

private enum PacketHashEvidenceError: Error {
    case probeFailed
    case emptyStream
    case malformedHash
}
