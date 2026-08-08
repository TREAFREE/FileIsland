import Foundation
import XCTest
@testable import FileIsland

@MainActor
final class OutputFolderBookmarkStoreTests: XCTestCase {
    func testSaveAndResolvePersistedFolder() throws {
        let defaults = makeDefaults()
        let coder = StubBookmarkCoder()
        let store = OutputFolderBookmarkStore(defaults: defaults, coder: coder)
        let folder = URL(fileURLWithPath: "/tmp/File Island Output", isDirectory: true)

        try store.save(folder)

        XCTAssertEqual(try store.resolve()?.url, folder)
        XCTAssertEqual(store.displayURL, folder)
    }

    func testStaleBookmarkIsRefreshed() throws {
        let defaults = makeDefaults()
        let coder = StubBookmarkCoder(isStale: true)
        let store = OutputFolderBookmarkStore(defaults: defaults, coder: coder)
        let folder = URL(fileURLWithPath: "/tmp/File Island Output", isDirectory: true)

        try store.save(folder)
        _ = try store.resolve()

        XCTAssertEqual(coder.makeBookmarkCallCount, 2)
    }

    func testClearRemovesFolder() throws {
        let defaults = makeDefaults()
        let store = OutputFolderBookmarkStore(defaults: defaults, coder: StubBookmarkCoder())
        try store.save(URL(fileURLWithPath: "/tmp/output", isDirectory: true))

        store.clear()

        XCTAssertNil(try store.resolve())
        XCTAssertNil(store.displayURL)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "OutputFolderBookmarkStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class StubBookmarkCoder: SecurityScopedBookmarkCoding, @unchecked Sendable {
    private let isStale: Bool
    private(set) var makeBookmarkCallCount = 0

    init(isStale: Bool = false) {
        self.isStale = isStale
    }

    func makeBookmark(for url: URL) throws -> Data {
        makeBookmarkCallCount += 1
        return Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(
            url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true),
            isStale: isStale
        )
    }
}
