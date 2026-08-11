import SwiftUI

@main
struct FileIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(AppEnvironment.live.localization.string("Choose Files or Folder…")) {
                    appDelegate.chooseInputs()
                }
                .keyboardShortcut("o")
                .disabled(!appDelegate.canChooseInputs)
            }
            CommandGroup(replacing: .appSettings) {
                Button(AppEnvironment.live.localization.string("Settings…")) {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",")
            }
        }
    }
}
