import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var islandWindowController: IslandWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let environment = AppEnvironment.live
        let settingsController = environment.makeSettingsWindowController()
        let statusController = StatusBarController(
            settingsWindowController: settingsController,
            outputFolderStore: environment.outputFolderStore
        )
        let islandController = environment.makeIslandWindowController()
        islandController.observeState { [weak statusController] state in
            statusController?.update(for: state)
        }

        settingsWindowController = settingsController
        statusBarController = statusController
        islandWindowController = islandController
        islandController.showIsland()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
