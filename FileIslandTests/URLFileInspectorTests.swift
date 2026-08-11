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

    func testInspectFallsBackToExtensionWhenContentTypeLookupIsUnavailable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        let bytes = Data([0x46, 0x49, 0x4C, 0x45])
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let inspector = URLFileInspector(contentTypeResolver: { _ in nil })
        let files = try await inspector.inspect(urls: [url])

        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.fileSize, Int64(bytes.count))
        XCTAssertEqual(file.format, .mp4)
        XCTAssertEqual(file.kind, .video)
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

    func testInspectRejectsSymbolicLinkWithoutFollowingIt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("source.mp4")
        let link = directory.appendingPathComponent("linked.mp4")
        try Data([0]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        do {
            _ = try await URLFileInspector().inspect(urls: [link])
            XCTFail("Expected a symbolic link to be rejected")
        } catch let error as FileInspectionError {
            XCTAssertEqual(error, .notRegularFile(link))
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
