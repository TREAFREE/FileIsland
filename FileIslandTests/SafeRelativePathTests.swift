import Foundation
import XCTest
@testable import FileIsland

final class SafeRelativePathTests: XCTestCase {
    func testResolvesNestedRelativePathInsideRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/output", isDirectory: true)
        let path = try SafeRelativePath("旅行/夏天/photo.jpg")

        XCTAssertEqual(path.string, "旅行/夏天/photo.jpg")
        XCTAssertEqual(
            try path.resolvedURL(relativeTo: root),
            root.appendingPathComponent("旅行/夏天/photo.jpg")
        )
        XCTAssertEqual(path.parent?.string, "旅行/夏天")
    }

    func testRejectsAbsoluteParentAndEmptyComponents() {
        for unsafe in ["/photo.jpg", "../photo.jpg", "a/../photo.jpg", "a//photo.jpg", "./photo.jpg", ""] {
            XCTAssertThrowsError(try SafeRelativePath(unsafe), unsafe)
        }
    }

    func testRejectsResolvingThroughSymlinkOutsideRoot() throws {
        let manager = FileManager.default
        let base = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("root", isDirectory: true)
        let outside = base.appendingPathComponent("outside", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: true)
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )
        defer { try? manager.removeItem(at: base) }

        let path = try SafeRelativePath("escape/file.jpg")
        XCTAssertThrowsError(try path.resolvedURL(relativeTo: root)) { error in
            XCTAssertEqual(error as? SafeRelativePathError, .escapesRoot)
        }
    }
}
