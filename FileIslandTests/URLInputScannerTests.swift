import Foundation
import XCTest
@testable import FileIsland

final class URLInputScannerTests: XCTestCase {
    func testRecursivelyScansFolderAndPreservesDeterministicRelativePaths() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("b.jpg", in: root)
        try write("nested/a.png", in: root)

        let result = try await URLInputScanner().scan(urls: [root])

        XCTAssertEqual(result.selections, [.folder(root)])
        XCTAssertEqual(result.inputs.map(\.relativePath.string), ["b.jpg", "nested/a.png"])
        XCTAssertEqual(result.inputs.map(\.file.displayName), ["b.jpg", "a.png"])
    }

    func testDistinguishesExplicitFileFromFolderRoot() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try write("photo.jpg", in: root)

        let result = try await URLInputScanner().scan(urls: [file])

        XCTAssertEqual(result.selections, [.file(file)])
        XCTAssertEqual(result.inputs.first?.selection, .file(file))
        XCTAssertEqual(result.inputs.first?.relativePath.string, "photo.jpg")
        XCTAssertFalse(result.containsFolderRoot)
    }

    func testSkipsHiddenPackagesAndSymbolicLinks() async throws {
        let manager = FileManager.default
        let root = try makeDirectory()
        defer { try? manager.removeItem(at: root) }
        try write("visible.jpg", in: root)
        try write(".hidden.png", in: root)
        try write(".secret/inside.jpg", in: root)
        try write("Demo.app/Contents/asset.png", in: root)
        let target = try write("target.png", in: root)
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("linked.png"),
            withDestinationURL: target
        )
        let targetDirectory = root.appendingPathComponent("real", isDirectory: true)
        try manager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try write("real/inside.png", in: root)
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("linked-folder", isDirectory: true),
            withDestinationURL: targetDirectory
        )

        let result = try await URLInputScanner().scan(urls: [root])

        XCTAssertEqual(
            result.inputs.map(\.relativePath.string),
            ["real/inside.png", "target.png", "visible.jpg"]
        )
    }

    func testRejectsEmptyOrNonLocalInput() async {
        await assertScanFails(urls: [], expected: .noFiles)
        await assertScanFails(
            urls: [URL(string: "https://example.com/file.jpg")!],
            expected: .notLocalFile
        )
    }

    func testLargeFolderUsesOneInspectorInvocation() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<250 {
            try write(String(format: "nested/%03d.jpg", index), in: root)
        }
        let inspector = RecordingInspector()

        let result = try await URLInputScanner(fileInspector: inspector).scan(urls: [root])

        XCTAssertEqual(result.inputs.count, 250)
        let metrics = await inspector.metrics
        XCTAssertEqual(metrics.invocationCount, 1)
        XCTAssertEqual(metrics.maximumBatchSize, 250)
    }

    private func assertScanFails(urls: [URL], expected: InputScanningError) async {
        do {
            _ = try await URLInputScanner().scan(urls: urls)
            XCTFail("Expected scan to fail")
        } catch let error as InputScanningError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ relativePath: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x01]).write(to: url)
        return url
    }
}

private actor RecordingInspector: FileInspecting {
    private(set) var invocationCount = 0
    private(set) var maximumBatchSize = 0

    var metrics: (invocationCount: Int, maximumBatchSize: Int) {
        (invocationCount, maximumBatchSize)
    }

    func inspect(urls: [URL]) async throws -> [InputFile] {
        invocationCount += 1
        maximumBatchSize = max(maximumBatchSize, urls.count)
        return try await URLFileInspector().inspect(urls: urls)
    }
}
