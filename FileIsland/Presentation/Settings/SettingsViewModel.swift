import Foundation
import Observation

enum SettingsDestination: CaseIterable, Equatable, Sendable {
    case website
    case releases
    case issues
    case privacy
    case thirdPartyNotices

    var url: URL {
        switch self {
        case .website:
            URL(string: "https://treafree.github.io/FileIsland/")!
        case .releases:
            URL(string: "https://github.com/TREAFREE/FileIsland/releases/latest")!
        case .issues:
            URL(string: "https://github.com/TREAFREE/FileIsland/issues")!
        case .privacy:
            URL(string: "https://github.com/TREAFREE/FileIsland/blob/main/PRIVACY.md")!
        case .thirdPartyNotices:
            URL(
                string: "https://github.com/TREAFREE/FileIsland/blob/main/Legal/THIRD_PARTY_NOTICES.md"
            )!
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    let preferences: AppPreferences
    let outputFolderStore: OutputFolderBookmarkStore

    private(set) var launchAtLogin: Bool
    private(set) var errorMessage: String?
    private(set) var isChoosingOutputFolder = false

    var outputFolderLabel: String {
        guard let url = outputFolderStore.displayURL else { return "Not selected" }
        return Self.abbreviatedPath(url, homeDirectoryURL: homeDirectoryURL)
    }

    @ObservationIgnored
    private let outputDirectorySelector: any OutputDirectorySelecting

    @ObservationIgnored
    private let loginItemController: any LoginItemControlling

    @ObservationIgnored
    private let homeDirectoryURL: URL

    init(
        preferences: AppPreferences,
        outputFolderStore: OutputFolderBookmarkStore,
        outputDirectorySelector: any OutputDirectorySelecting,
        loginItemController: any LoginItemControlling,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.preferences = preferences
        self.outputFolderStore = outputFolderStore
        self.outputDirectorySelector = outputDirectorySelector
        self.loginItemController = loginItemController
        self.homeDirectoryURL = homeDirectoryURL
        launchAtLogin = loginItemController.isEnabled
    }

    func chooseOutputFolder() {
        guard !isChoosingOutputFolder else { return }
        isChoosingOutputFolder = true
        Task { [weak self] in
            guard let self else { return }
            let selection = await outputDirectorySelector.selectDirectory(
                suggestedDirectory: outputFolderStore.displayURL
            )
            isChoosingOutputFolder = false
            guard let selection else { return }
            defer {
                selection.releaseAccess()
            }
            do {
                try outputFolderStore.save(selection.url)
                errorMessage = nil
            } catch {
                errorMessage = "File Island couldn’t remember this folder. Please choose another folder."
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemController.setEnabled(enabled)
            launchAtLogin = loginItemController.isEnabled
            errorMessage = nil
        } catch {
            launchAtLogin = loginItemController.isEnabled
            errorMessage = "The login item couldn’t be changed. Check Login Items in System Settings."
        }
    }

    func resetIslandOpacity() {
        preferences.islandOpacity = 1
    }

    private static func abbreviatedPath(_ url: URL, homeDirectoryURL: URL) -> String {
        let path = trimmingDirectorySeparator(
            url.standardizedFileURL.path(percentEncoded: false)
        )
        let homePath = trimmingDirectorySeparator(
            homeDirectoryURL.standardizedFileURL.path(percentEncoded: false)
        )
        guard path != homePath else { return "~" }

        let homePrefix = homePath.hasSuffix("/") ? homePath : homePath + "/"
        guard path.hasPrefix(homePrefix) else { return path }
        return "~/" + path.dropFirst(homePrefix.count)
    }

    private static func trimmingDirectorySeparator(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.dropLast())
    }
}
