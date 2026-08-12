import Foundation
import XCTest

@testable import FileIsland

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testOutputFolderUnderHomeUsesTildeInsteadOfExposingTheUserDirectory() throws {
        let store = makeOutputFolderStore()
        try store.save(URL(fileURLWithPath: "/Users/tester/Movies/Exports", isDirectory: true))
        let viewModel = makeViewModel(
            store: store,
            homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        )

        XCTAssertEqual(viewModel.outputFolderLabel, "~/Movies/Exports")
    }

    func testOutputFolderOutsideHomeKeepsItsVolumePath() throws {
        let store = makeOutputFolderStore()
        try store.save(URL(fileURLWithPath: "/Volumes/Media/Exports", isDirectory: true))
        let viewModel = makeViewModel(
            store: store,
            homeDirectoryURL: URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        )

        XCTAssertEqual(viewModel.outputFolderLabel, "/Volumes/Media/Exports")
    }

    func testSettingsDestinationsAreSecureAndPointAtTheOfficialProject() {
        XCTAssertEqual(
            SettingsDestination.website.url.absoluteString,
            "https://treafree.github.io/FileIsland/"
        )
        XCTAssertEqual(
            SettingsDestination.releases.url.absoluteString,
            "https://github.com/TREAFREE/FileIsland/releases/latest"
        )
        XCTAssertEqual(
            SettingsDestination.issues.url.absoluteString,
            "https://github.com/TREAFREE/FileIsland/issues"
        )
        XCTAssertTrue(SettingsDestination.allCases.allSatisfy { $0.url.scheme == "https" })
    }

    func testResetIslandOpacityRestoresFullOpacity() {
        let viewModel = makeViewModel(store: makeOutputFolderStore())
        viewModel.preferences.islandOpacity = 0.72

        viewModel.resetIslandOpacity()

        XCTAssertEqual(viewModel.preferences.islandOpacity, 1, accuracy: 0.001)
    }

    private func makeViewModel(
        store: OutputFolderBookmarkStore,
        homeDirectoryURL: URL = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
    ) -> SettingsViewModel {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests-\(UUID().uuidString)")!
        return SettingsViewModel(
            preferences: AppPreferences(defaults: defaults),
            outputFolderStore: store,
            outputDirectorySelector: SettingsStubOutputDirectorySelector(),
            loginItemController: SettingsStubLoginItemController(),
            homeDirectoryURL: homeDirectoryURL
        )
    }

    private func makeOutputFolderStore() -> OutputFolderBookmarkStore {
        let defaults = UserDefaults(suiteName: "SettingsViewModelTests.Store-\(UUID().uuidString)")!
        return OutputFolderBookmarkStore(
            defaults: defaults,
            coder: SettingsStubBookmarkCoder()
        )
    }
}

private struct SettingsStubOutputDirectorySelector: OutputDirectorySelecting {
    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection? { nil }
}

@MainActor
private final class SettingsStubLoginItemController: LoginItemControlling {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

private struct SettingsStubBookmarkCoder: SecurityScopedBookmarkCoding {
    func makeBookmark(for url: URL) throws -> Data {
        Data(url.path(percentEncoded: false).utf8)
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
        ResolvedBookmark(
            url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)),
            isStale: false
        )
    }
}
