import AppKit
import Foundation

struct IslandInputSelectionPrompt: Equatable, Sendable {
    let title: String
    let message: String
    let actionTitle: String
}

@MainActor
protocol IslandInputSelecting {
    func selectInputs(prompt: IslandInputSelectionPrompt) async -> [URL]?
}

@MainActor
struct AppKitIslandInputSelector: IslandInputSelecting {
    func selectInputs(prompt: IslandInputSelectionPrompt) async -> [URL]? {
        let wasAppActive = NSApp.isActive
        defer {
            if !wasAppActive {
                NSApp.deactivate()
            }
        }

        let panel = NSOpenPanel()
        panel.title = prompt.title
        panel.message = prompt.message
        panel.prompt = prompt.actionTitle
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        let response: NSApplication.ModalResponse
        if let hostWindow = NSApp.keyWindow,
           !(hostWindow is NSPanel) {
            response = await panel.beginSheetModal(for: hostWindow)
        } else {
            NSApp.activate()
            response = await panel.begin()
        }

        guard response == .OK, !panel.urls.isEmpty else { return nil }
        return panel.urls
    }
}
