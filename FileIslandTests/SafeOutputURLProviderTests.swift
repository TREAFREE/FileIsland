import Foundation
import XCTest
@testable import FileIsland

final class SafeOutputURLProviderTests: XCTestCase {
    func testAvoidsExistingAndReservedNames() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("photo.png")
        let existing = directory.appendingPathComponent("photo.jpg")
        try Data([0x01]).write(to: input)
        try Data([0x02]).write(to: existing)

        let second = try SafeOutputURLProvider().outputURL(
            for: input,
            format: .jpeg,
            policy: .chosenDirectory(directory, suffix: ""),
            reserved: []
        )
        let third = try SafeOutputURLProvider().outputURL(
            for: input,
            format: .jpeg,
            policy: .chosenDirectory(directory, suffix: ""),
            reserved: [second]
        )

        XCTAssertEqual(second.lastPathComponent, "photo-2.jpg")
        XCTAssertEqual(third.lastPathComponent, "photo-3.jpg")
    }

    func testPreservesUnicodeAndSpacesInChosenDirectory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = URL(fileURLWithPath: "/tmp/旅行 照片.png")

        let output = try SafeOutputURLProvider().outputURL(
            for: input,
            format: .jpeg,
            policy: .chosenDirectory(directory, suffix: "-converted"),
            reserved: []
        )

        XCTAssertEqual(output.deletingLastPathComponent(), directory)
        XCTAssertEqual(output.lastPathComponent, "旅行 照片-converted.jpg")
    }

    func testNeverReturnsInputURLForSameExtension() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("photo.jpg")
        try Data([0x01]).write(to: input)

        let output = try SafeOutputURLProvider().outputURL(
            for: input,
            format: .jpeg,
            policy: .sameDirectory(suffix: ""),
            reserved: []
        )

        XCTAssertEqual(output.lastPathComponent, "photo-2.jpg")
        XCTAssertNotEqual(output.standardizedFileURL, input.standardizedFileURL)
    }

    func testGenericMP4OutputNeverReturnsInputURL() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("clip.mp4")
        try Data([0x01]).write(to: input)

        let output = try SafeOutputURLProvider().outputURL(
            for: input,
            filenameExtension: "mp4",
            policy: .sameDirectory(suffix: ""),
            reserved: []
        )

        XCTAssertEqual(output.lastPathComponent, "clip-2.mp4")
        XCTAssertNotEqual(output.standardizedFileURL, input.standardizedFileURL)
    }

    func testRejectsMissingOutputDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let input = URL(fileURLWithPath: "/tmp/photo.png")

        XCTAssertThrowsError(
            try SafeOutputURLProvider().outputURL(
                for: input,
                format: .jpeg,
                policy: .chosenDirectory(directory, suffix: ""),
                reserved: []
            )
        ) { error in
            XCTAssertEqual(error as? ConversionError, .permissionDenied)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }
}
