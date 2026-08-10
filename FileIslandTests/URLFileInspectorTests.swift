import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class URLFileInspectorTests: XCTestCase {
    func testInspectRecognizesMilestoneTwoFormatMatrix() async throws {
        let cases: [(String, InputFileFormat, MediaKind)] = [
            ("heic", .heic, .image),
            ("heif", .heif, .image),
            ("jpg", .jpeg, .image),
            ("png", .png, .image),
            ("webp", .webP, .image),
            ("tiff", .tiff, .image),
            ("mov", .mov, .video),
            ("mp4", .mp4, .video),
            ("m4v", .m4v, .video),
            ("mkv", .mkv, .video)
        ]

        for (extensionName, expectedFormat, expectedKind) in cases {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(extensionName)
            let bytes = Data([0x46, 0x49, 0x4C, 0x45])
            try bytes.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            let inspectedFiles = try await URLFileInspector().inspect(urls: [url])
            let file = try XCTUnwrap(inspectedFiles.first)

            XCTAssertEqual(file.displayName, url.lastPathComponent)
            XCTAssertEqual(file.fileSize, Int64(bytes.count))
            XCTAssertEqual(file.format, expectedFormat, extensionName)
            XCTAssertEqual(file.kind, expectedKind, extensionName)
        }
    }

    func testInspectReadsNameSizeAndUTTypeWithoutOpeningMedia() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let files = try await URLFileInspector().inspect(urls: [url])

        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(file.displayName, url.lastPathComponent)
        XCTAssertEqual(file.fileSize, Int64(bytes.count))
        XCTAssertEqual(file.kind, .image)
        XCTAssertTrue(file.type?.conforms(to: .jpeg) == true)
    }

    func testInspectRejectsDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            _ = try await URLFileInspector().inspect(urls: [directory])
            XCTFail("Expected a directory to be rejected")
        } catch let error as FileInspectionError {
            XCTAssertEqual(error, .notRegularFile(directory))
        }
    }

    func testInspectRejectsEmptyInput() async {
        do {
            _ = try await URLFileInspector().inspect(urls: [])
            XCTFail("Expected empty input to be rejected")
        } catch let error as FileInspectionError {
            XCTAssertEqual(error, .noFiles)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
