import SwiftUI

@main
struct FileIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(AppEnvironment.live.localization.string("Settings…")) {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
