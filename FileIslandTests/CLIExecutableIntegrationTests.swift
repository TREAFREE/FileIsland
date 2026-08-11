import Foundation
import Darwin
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class CLIExecutableIntegrationTests: XCTestCase {
    func testCapabilitiesAndUnicodeInspectionRunWithoutGUI() throws {
        let capabilities = try run(["capabilities", "--json"])
        XCTAssertEqual(capabilities.status, 0)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: capabilities.stdout) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["kind"] as? String, "capabilities")
        let audio = try XCTUnwrap(object["audio"] as? [String: Any])
        XCTAssertEqual(audio["outputFormats"] as? [String], ["m4a", "wav", "flac", "aiff"])

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("含 空格.png")
        try ImageFixtureFactory.writeImage(to: input, type: .png)
        let inspection = try run(["inspect", input.path, "--json"])
        XCTAssertEqual(inspection.status, 0)
        XCTAssertTrue(String(decoding: inspection.stdout, as: UTF8.self).contains("含 空格.png"))
    }

    func testBarePATHLaunchIgnoresWorkingDirectoryRuntimeLures() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let untrustedWorkingDirectory = root.appendingPathComponent(
            "untrusted-cwd",
            isDirectory: true
        )
        let output = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(
            at: untrustedWorkingDirectory,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: false
        )
        try Data("not a preset catalog".utf8).write(
            to: untrustedWorkingDirectory.appendingPathComponent(
                "built-in-presets.json"
            )
        )

        let marker = root.appendingPathComponent("cwd-runtime-was-executed")
        let lureScript = Data(
            "#!/bin/sh\nprintf triggered > \"$FILEISLAND_DECOY_MARKER\"\nexit 91\n".utf8
        )
        for name in ["ffmpeg", "ffprobe", "FileIslandMediaValidator"] {
            let lure = untrustedWorkingDirectory.appendingPathComponent(name)
            try lureScript.write(to: lure)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: lure.path
            )
        }

        let capabilities = try runViaBarePATH(
            ["capabilities", "--json"],
            currentDirectory: untrustedWorkingDirectory,
            markerURL: marker
        )
        XCTAssertEqual(
            capabilities.status,
            0,
            String(decoding: capabilities.stderr, as: UTF8.self)
        )
        XCTAssertNoThrow(
            try JSONSerialization.jsonObject(with: capabilities.stdout)
        )

        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "task016-keyframes.mp4",
                withExtension: nil
            )
        )
        let input = root.appendingPathComponent("input.mp4")
        try FileManager.default.copyItem(at: source, to: input)
        let split = try runViaBarePATH(
            [
                "split", input.path, "--output", output.path,
                "--max-duration-seconds", "2", "--mode", "fast-keyframe-copy",
                "--json"
            ],
            currentDirectory: untrustedWorkingDirectory,
            markerURL: marker
        )

        XCTAssertEqual(split.status, 0, String(decoding: split.stderr, as: UTF8.self))
        XCTAssertTrue(
            String(decoding: split.stdout, as: UTF8.self)
                .contains("\"state\":\"completed\"")
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testRealAudioConversionUsesSharedCLIEngine() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("Audio Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "tone.mp3", withExtension: nil)
        )
        let input = root.appendingPathComponent("声音 输入.mp3")
        try FileManager.default.copyItem(at: source, to: input)

        let result = try run([
            "convert", input.path, "--output", output.path,
            "--audio-format", "m4a", "--audio-quality", "balanced", "--json"
        ])

        XCTAssertEqual(result.status, 0, String(decoding: result.stderr, as: UTF8.self))
        let outputs = try FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        XCTAssertEqual(outputs.map(\.pathExtension), ["m4a"])
        XCTAssertGreaterThan(try outputs[0].resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
    }

    func testEveryExpandedFallbackVideoFormatRunsThroughCLI() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        for fileExtension in ["avi", "mpeg", "mts", "flv", "3gp", "wmv"] {
            let source = try XCTUnwrap(
                Bundle(for: Self.self).url(
                    forResource: "task014-sample.\(fileExtension)",
                    withExtension: nil
                )
            )
            let input = root.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: input)
            let output = root.appendingPathComponent("out-\(fileExtension)", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

            let result = try run([
                "convert", input.path, "--output", output.path,
                "--video-resolution", "720p", "--json"
            ])

            XCTAssertEqual(
                result.status,
                0,
                "\(fileExtension): \(String(decoding: result.stderr, as: UTF8.self))"
            )
            let outputs = try FileManager.default.contentsOfDirectory(
                at: output,
                includingPropertiesForKeys: nil
            )
            XCTAssertEqual(outputs.map(\.pathExtension), ["mp4"])
        }
    }

    func testRealImageConversionAndMetacharacterPathDoNotInvokeShell() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("输出 文件", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let input = root.appendingPathComponent("$(touch fileisland-pwned).png")
        try ImageFixtureFactory.writeImage(to: input, type: .png)
        let sideEffect = root.appendingPathComponent("fileisland-pwned")

        let result = try run([
            "convert", input.path, "--output", output.path,
            "--image-format", "jpeg", "--json"
        ])

        XCTAssertEqual(result.status, 0, String(decoding: result.stderr, as: UTF8.self))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sideEffect.path))
        let outputs = try FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(outputs.count, 1)
        XCTAssertTrue(try ImageFixtureFactory.imageType(at: outputs[0]).conforms(to: .jpeg))
        XCTAssertFalse(String(decoding: result.stdout, as: UTF8.self).contains(output.path))
    }

    func testUnknownInputUsesUnsupportedExitCode() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("unknown.xyz")
        try Data("unknown".utf8).write(to: input)
        let result = try run([
            "convert", input.path, "--output", root.path,
            "--image-format", "jpeg", "--json"
        ])
        XCTAssertEqual(result.status, CLIExitCode.unsupported.rawValue)
    }

    func testRecursiveFolderInspectionRequiresOptInAndPreservesRelativePath() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("子 目录", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let input = nested.appendingPathComponent("图 片.png")
        try ImageFixtureFactory.writeImage(to: input, type: .png)

        let rejected = try run(["inspect", root.path, "--json"])
        XCTAssertEqual(rejected.status, CLIExitCode.argumentError.rawValue)

        let accepted = try run(["inspect", root.path, "--recursive", "--json"])
        XCTAssertEqual(accepted.status, CLIExitCode.success.rawValue)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: accepted.stdout) as? [String: Any]
        )
        let files = try XCTUnwrap(object["files"] as? [[String: Any]])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0]["relativePath"] as? String, "子 目录/图 片.png")
    }

    func testRealFastSplitUsesBundledAdjacentToolsAndPathSafeJSONL() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("Split Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "task016-keyframes.mp4",
                withExtension: nil
            )
        )
        let input = root.appendingPathComponent("含 空格电影.mp4")
        try FileManager.default.copyItem(at: source, to: input)

        let result = try run([
            "split", input.path, "--output", output.path,
            "--max-duration-seconds", "2", "--mode", "fast-keyframe-copy", "--json"
        ])

        XCTAssertEqual(result.status, 0, String(decoding: result.stderr, as: UTF8.self))
        let outputText = String(decoding: result.stdout, as: UTF8.self)
        let events = try outputText.split(separator: "\n").map { line in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
        }
        XCTAssertEqual(events.last?["state"] as? String, "completed")
        XCTAssertTrue(events.contains { $0["state"] as? String == "plan" })
        XCTAssertTrue(events.contains { $0["state"] as? String == "validation" })
        XCTAssertTrue(events.contains { $0["state"] as? String == "publication" })
        XCTAssertFalse(outputText.contains(root.path))
        XCTAssertFalse(outputText.contains(input.path))

        let splitDirectory = output.appendingPathComponent("含 空格电影 — Split")
        let segments = try FileManager.default.contentsOfDirectory(
            at: splitDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        XCTAssertGreaterThan(segments.count, 1)
        XCTAssertTrue(segments.allSatisfy { $0.pathExtension == "mp4" })
        for segment in segments {
            XCTAssertGreaterThan(
                try segment.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0,
                0
            )
            let metadata = try probeSegment(segment)
            let streams = try XCTUnwrap(metadata["streams"] as? [[String: Any]])
            XCTAssertTrue(streams.contains {
                $0["codec_type"] as? String == "video"
                    && $0["codec_name"] as? String == "h264"
            })
            XCTAssertTrue(streams.contains {
                $0["codec_type"] as? String == "audio"
                    && $0["codec_name"] as? String == "aac"
            })
            let format = try XCTUnwrap(metadata["format"] as? [String: Any])
            let duration = try XCTUnwrap(
                Double(format["duration"] as? String ?? "")
            )
            XCTAssertLessThanOrEqual(duration, 2.11)
        }

        let collision = try run([
            "split", input.path, "--output", output.path,
            "--max-duration-seconds", "2", "--mode", "fast-keyframe-copy", "--json"
        ])
        XCTAssertEqual(
            collision.status,
            0,
            String(decoding: collision.stderr, as: UTF8.self)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: output.appendingPathComponent("含 空格电影 — Split-2").path
            )
        )
        XCTAssertFalse(String(decoding: collision.stdout, as: UTF8.self).contains(root.path))
        XCTAssertFalse(String(decoding: collision.stderr, as: UTF8.self).contains(root.path))
    }

    func testSplitRejectsInvalidLimitsAndUnsupportedMediaWithoutPathLeakage() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "task016-keyframes.mp4",
                withExtension: nil
            )
        )
        let input = root.appendingPathComponent("private-name.mp4")
        try FileManager.default.copyItem(at: source, to: input)

        for arguments in [
            [
                "split", input.path, "--output", output.path,
                "--mode", "fast-keyframe-copy", "--json"
            ],
            [
                "split", input.path, "--output", output.path,
                "--max-bytes", "0", "--mode", "fast-keyframe-copy", "--json"
            ]
        ] {
            let result = try run(arguments)
            XCTAssertEqual(result.status, CLIExitCode.argumentError.rawValue)
            XCTAssertFalse(String(decoding: result.stdout, as: UTF8.self).contains(root.path))
            XCTAssertFalse(String(decoding: result.stderr, as: UTF8.self).contains(root.path))
        }

        let unsupported = root.appendingPathComponent("private-document.xyz")
        try Data("not media".utf8).write(to: unsupported)
        let result = try run([
            "split", unsupported.path, "--output", output.path,
            "--max-duration-seconds", "2", "--mode", "fast-keyframe-copy", "--json"
        ])
        XCTAssertEqual(result.status, CLIExitCode.unsupported.rawValue)
        XCTAssertFalse(String(decoding: result.stdout, as: UTF8.self).contains(root.path))
        XCTAssertFalse(String(decoding: result.stderr, as: UTF8.self).contains(root.path))
        XCTAssertTrue(String(decoding: result.stdout, as: UTF8.self).contains("\"state\":\"failed\""))

        let mixed = try run([
            "split", input.path, unsupported.path, "--output", output.path,
            "--max-duration-seconds", "2", "--mode", "fast-keyframe-copy", "--json"
        ])
        XCTAssertEqual(mixed.status, CLIExitCode.unsupported.rawValue)
        XCTAssertFalse(String(decoding: mixed.stdout, as: UTF8.self).contains(root.path))
        XCTAssertFalse(String(decoding: mixed.stderr, as: UTF8.self).contains(root.path))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: output,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testSIGINTCancelsSplitAndLeavesNoVisibleOrStagingOutput() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("Interrupted Output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "task016-keyframes.mp4",
                withExtension: nil
            )
        )
        let input = root.appendingPathComponent("interrupt-private.mp4")
        try FileManager.default.copyItem(at: source, to: input)

        let result = try runAndInterruptAfterPlan([
            "split", input.path, "--output", output.path,
            "--max-duration-seconds", "2", "--mode", "fast-keyframe-copy", "--json"
        ])

        XCTAssertEqual(result.reason, .exit)
        XCTAssertEqual(result.status, CLIExitCode.cancelled.rawValue)
        let outputText = String(decoding: result.stdout, as: UTF8.self)
        XCTAssertTrue(outputText.contains("\"state\":\"plan\""))
        XCTAssertTrue(outputText.contains("\"state\":\"rollback\""))
        XCTAssertTrue(outputText.contains("\"state\":\"cancelled\""))
        XCTAssertFalse(outputText.contains(root.path))
        XCTAssertFalse(String(decoding: result.stderr, as: UTF8.self).contains(root.path))
        let remaining = try FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remaining.isEmpty)
    }

    private func run(_ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = try executableURL()
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            reason: process.terminationReason,
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private func runViaBarePATH(
        _ arguments: [String],
        currentDirectory: URL,
        markerURL: URL
    ) throws -> ProcessResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let productDirectory = try executableURL().deletingLastPathComponent()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "-i",
            "PATH=\(productDirectory.path):/usr/bin:/bin",
            "FILEISLAND_DECOY_MARKER=\(markerURL.path)",
            "fileisland"
        ] + arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            reason: process.terminationReason,
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private func runAndInterruptAfterPlan(_ arguments: [String]) throws -> ProcessResult {
        let capture = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: capture) }
        let stdoutURL = capture.appendingPathComponent("stdout")
        let stderrURL = capture.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: Data())
        FileManager.default.createFile(atPath: stderrURL.path, contents: Data())
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = try executableURL()
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        var observedPlan = false
        for _ in 0..<1_000 {
            let data = (try? Data(contentsOf: stdoutURL)) ?? Data()
            if String(decoding: data, as: UTF8.self).contains("\"state\":\"plan\"") {
                observedPlan = true
                break
            }
            if !process.isRunning { break }
            usleep(5_000)
        }
        XCTAssertTrue(observedPlan, "Expected a plan event before interrupting the CLI")
        if process.isRunning {
            XCTAssertEqual(Darwin.kill(process.processIdentifier, SIGINT), 0)
        }
        process.waitUntilExit()
        try stdout.synchronize()
        try stderr.synchronize()
        return ProcessResult(
            reason: process.terminationReason,
            status: process.terminationStatus,
            stdout: try Data(contentsOf: stdoutURL),
            stderr: try Data(contentsOf: stderrURL)
        )
    }

    private func probeSegment(_ url: URL) throws -> [String: Any] {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let probe = try executableURL().deletingLastPathComponent()
            .appendingPathComponent("ffprobe")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: probe.path))
        process.executableURL = probe
        process.arguments = [
            "-hide_banner", "-v", "error", "-show_streams", "-show_format",
            "-show_entries", "stream=codec_type,codec_name:format=duration,format_name",
            "-of", "json=c=1", "--", url.path
        ]
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let diagnostic = stderr.fileHandleForReading.readDataToEndOfFile()
        XCTAssertEqual(
            process.terminationStatus,
            0,
            String(decoding: diagnostic, as: UTF8.self)
        )
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: output) as? [String: Any]
        )
    }

    private func executableURL() throws -> URL {
        if let products = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            let url = URL(fileURLWithPath: products).appendingPathComponent("fileisland")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        var cursor = Bundle(for: Self.self).bundleURL
        for _ in 0..<4 { cursor.deleteLastPathComponent() }
        let url = cursor.appendingPathComponent("fileisland")
        return try XCTUnwrap(
            FileManager.default.isExecutableFile(atPath: url.path) ? url : nil,
            "Expected freshly built fileisland at \(url.lastPathComponent)"
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct ProcessResult {
    let reason: Process.TerminationReason
    let status: Int32
    let stdout: Data
    let stderr: Data
}
