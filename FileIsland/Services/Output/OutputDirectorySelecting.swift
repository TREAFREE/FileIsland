import AppKit
import Foundation

@MainActor
protocol OutputDirectorySelecting: Sendable {
    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection?
}

struct OutputDirectorySelection: Equatable, Sendable {
    let url: URL
    let didStartAccessingSecurityScope: Bool
}

@MainActor
struct AppKitOutputDirectorySelector: OutputDirectorySelecting {
    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection? {
        let panel = NSOpenPanel()
        panel.title = "Choose Output Folder"
        panel.message = "Converted files will be saved here. Existing files are never overwritten."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggestedDirectory

        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        return OutputDirectorySelection(
            url: url,
            didStartAccessingSecurityScope: url.startAccessingSecurityScopedResource()
        )
    }
}
