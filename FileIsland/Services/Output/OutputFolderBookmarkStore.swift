import Foundation
import Observation

struct ResolvedBookmark: Equatable, Sendable {
    let url: URL
    let isStale: Bool
}

protocol SecurityScopedBookmarkCoding: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark
}

struct FoundationSecurityScopedBookmarkCoder: SecurityScopedBookmarkCoding {
    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: [.isDirectoryKey, .nameKey],
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return ResolvedBookmark(url: url, isStale: stale)
    }
}

@MainActor
@Observable
final class OutputFolderBookmarkStore {
    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let coder: any SecurityScopedBookmarkCoding

    @ObservationIgnored
    private let bookmarkKey = "outputFolder.securityScopedBookmark"

    private(set) var displayURL: URL?

    init(
        defaults: UserDefaults = .standard,
        coder: any SecurityScopedBookmarkCoding = FoundationSecurityScopedBookmarkCoder()
    ) {
        self.defaults = defaults
        self.coder = coder
        self.displayURL = nil
        self.displayURL = try? resolve()?.url
    }

    func save(_ url: URL) throws {
        defaults.set(try coder.makeBookmark(for: url), forKey: bookmarkKey)
        displayURL = url
    }

    func resolve() throws -> ResolvedBookmark? {
        guard let data = defaults.data(forKey: bookmarkKey) else {
            displayURL = nil
            return nil
        }
        let resolved = try coder.resolveBookmark(data)
        displayURL = resolved.url
        if resolved.isStale {
            defaults.set(try coder.makeBookmark(for: resolved.url), forKey: bookmarkKey)
        }
        return resolved
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
        displayURL = nil
    }
}
