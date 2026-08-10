import Foundation
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

        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("含 空格.png")
        try ImageFixtureFactory.writeImage(to: input, type: .png)
        let inspection = try run(["inspect", input.path, "--json"])
        XCTAssertEqual(inspection.status, 0)
        XCTAssertTrue(String(decoding: inspection.stdout, as: UTF8.self).contains("含 空格.png"))
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
            status: process.terminationStatus,
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile()
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
    let status: Int32
    let stdout: Data
    let stderr: Data
}
