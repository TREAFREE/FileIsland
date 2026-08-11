import Foundation
import XCTest
@testable import FileIsland

final class CLIResourceLocatorTests: XCTestCase {
    func testKernelExecutableResolverReturnsCanonicalExecutable() throws {
        let executable = try CLIExecutableURLResolver().resolve()
        XCTAssertTrue(executable.path.hasPrefix("/"))
        let canonicalExecutable = try CLIExecutableURLResolver {
            executable.path
        }.resolve()
        XCTAssertEqual(executable, canonicalExecutable)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path))
    }

    func testExecutableResolverRejectsRelativeKernelPath() {
        let resolver = CLIExecutableURLResolver {
            "fileisland"
        }

        XCTAssertThrowsError(try resolver.resolve()) { error in
            XCTAssertEqual(
                error as? CLIResourceError,
                .executablePathUnavailable
            )
        }
    }

    func testExecutableResolverCanonicalizesAnAbsoluteSymlink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("real-fileisland")
        let link = root.appendingPathComponent("fileisland")
        FileManager.default.createFile(atPath: target.path, contents: Data())
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: target.path
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )

        let executable = try CLIExecutableURLResolver {
            link.path
        }.resolve()

        let canonicalTarget = try CLIExecutableURLResolver {
            target.path
        }.resolve()
        XCTAssertEqual(executable, canonicalTarget)
    }

    func testResolvesOnlyResourcesAdjacentToExecutable() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fileisland")
        let preset = root.appendingPathComponent("built-in-presets.json")
        let ffmpeg = root.appendingPathComponent("ffmpeg")
        let ffprobe = root.appendingPathComponent("ffprobe")
        let mediaValidator = root.appendingPathComponent("FileIslandMediaValidator")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        FileManager.default.createFile(atPath: preset.path, contents: Data("{}".utf8))
        FileManager.default.createFile(atPath: ffmpeg.path, contents: Data())
        FileManager.default.createFile(atPath: ffprobe.path, contents: Data())
        FileManager.default.createFile(atPath: mediaValidator.path, contents: Data())
        for tool in [ffmpeg, ffprobe, mediaValidator] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tool.path
            )
        }
        let locator = CLIResourceLocator(executableURL: executable)

        XCTAssertEqual(try locator.presetCatalogURL(), preset)
        XCTAssertEqual(try locator.ffmpegExecutableURL(), ffmpeg)
        XCTAssertEqual(try locator.ffprobeExecutableURL(), ffprobe)
        XCTAssertEqual(try locator.mediaValidatorExecutableURL(), mediaValidator)
    }

    func testMissingResourcesFailClosed() {
        let locator = CLIResourceLocator(
            executableURL: URL(fileURLWithPath: "/missing/fileisland")
        )
        XCTAssertThrowsError(try locator.presetCatalogURL())
        XCTAssertThrowsError(try locator.ffmpegExecutableURL())
        XCTAssertThrowsError(try locator.ffprobeExecutableURL())
        XCTAssertThrowsError(try locator.mediaValidatorExecutableURL())
    }

    func testSplitToolsRejectSymlinksAndNonExecutableFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("fileisland")
        let target = root.appendingPathComponent("real-tool")
        let ffmpeg = root.appendingPathComponent("ffmpeg")
        let ffprobe = root.appendingPathComponent("ffprobe")
        let mediaValidator = root.appendingPathComponent("FileIslandMediaValidator")
        FileManager.default.createFile(atPath: executable.path, contents: Data())
        FileManager.default.createFile(atPath: target.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: ffmpeg, withDestinationURL: target)
        FileManager.default.createFile(atPath: ffprobe.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ffprobe.path)
        try FileManager.default.createSymbolicLink(
            at: mediaValidator,
            withDestinationURL: target
        )

        let locator = CLIResourceLocator(executableURL: executable)
        XCTAssertThrowsError(try locator.ffmpegExecutableURL())
        XCTAssertThrowsError(try locator.ffprobeExecutableURL())
        XCTAssertThrowsError(try locator.mediaValidatorExecutableURL())
    }
}
