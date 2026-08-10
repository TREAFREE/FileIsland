import Foundation
import XCTest
@testable import FileIsland

final class CLIResourceLocatorTests: XCTestCase {
    func testResolvesOnlyResourcesAdjacentToExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fileisland")
        let preset = root.appendingPathComponent("built-in-presets.json")
        let ffmpeg = root.appendingPathComponent("ffmpeg")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        FileManager.default.createFile(atPath: preset.path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: ffmpeg.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ffmpeg.path
        )
        let locator = CLIResourceLocator(executableURL: executable)

        XCTAssertEqual(try locator.presetCatalogURL(), preset)
        XCTAssertEqual(try locator.ffmpegExecutableURL(), ffmpeg)
    }

    func testMissingResourcesFailClosed() {
        let locator = CLIResourceLocator(
            executableURL: URL(fileURLWithPath: "/missing/fileisland")
        )
        XCTAssertThrowsError(try locator.presetCatalogURL())
        XCTAssertThrowsError(try locator.ffmpegExecutableURL())
    }
}
