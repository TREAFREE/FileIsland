import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var canChooseInputs = true

    private var islandWindowController: IslandWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let environment = AppEnvironment.live
        let settingsController = environment.makeSettingsWindowController()
        let islandController = environment.makeIslandWindowController()
        let statusController = StatusBarController(
            settingsWindowController: settingsController,
            outputFolderStore: environment.outputFolderStore,
            localization: environment.localization,
            chooseInputs: { [weak islandController] in
                islandController?.chooseInputs()
            }
        )
        islandController.observeState { [weak statusController] state in
            statusController?.update(for: state)
        }
        islandController.observeInputAvailability { [weak self, weak statusController] isAvailable in
            self?.canChooseInputs = isAvailable
            statusController?.updateInputAvailability(isAvailable)
        }

        settingsWindowController = settingsController
        statusBarController = statusController
        islandWindowController = islandController
        islandController.showIsland()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showSettings() {
        settingsWindowController?.show()
    }

    func chooseInputs() {
        islandWindowController?.chooseInputs()
    }
}
