import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    let preferences: AppPreferences
    let outputFolderStore: OutputFolderBookmarkStore

    private(set) var launchAtLogin: Bool
    private(set) var errorMessage: String?
    private(set) var outputFolderLabel: String

    @ObservationIgnored
    private let outputDirectorySelector: any OutputDirectorySelecting

    @ObservationIgnored
    private let loginItemController: any LoginItemControlling

    init(
        preferences: AppPreferences,
        outputFolderStore: OutputFolderBookmarkStore,
        outputDirectorySelector: any OutputDirectorySelecting,
        loginItemController: any LoginItemControlling
    ) {
        self.preferences = preferences
        self.outputFolderStore = outputFolderStore
        self.outputDirectorySelector = outputDirectorySelector
        self.loginItemController = loginItemController
        launchAtLogin = loginItemController.isEnabled
        outputFolderLabel = outputFolderStore.displayURL?.path(percentEncoded: false) ?? "Not selected"
    }

    func chooseOutputFolder() {
        Task { [weak self] in
            guard let self else { return }
            let selection = await outputDirectorySelector.selectDirectory(
                suggestedDirectory: outputFolderStore.displayURL
            )
            guard let selection else { return }
            defer {
                if selection.didStartAccessingSecurityScope {
                    selection.url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try outputFolderStore.save(selection.url)
                outputFolderLabel = selection.url.path(percentEncoded: false)
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
}
