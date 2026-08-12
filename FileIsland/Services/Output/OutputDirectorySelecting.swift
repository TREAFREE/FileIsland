import AppKit
import Foundation

@MainActor
protocol OutputDirectorySelecting: Sendable {
    func selectDirectory(suggestedDirectory: URL?) async -> OutputDirectorySelection?
}

@MainActor
final class OutputDirectoryAccessLease {
    let url: URL
    private(set) var isActive: Bool
    private let releaseAction: @MainActor (URL) -> Void

    init(
        url: URL,
        isActive: Bool,
        releaseAction: @escaping @MainActor (URL) -> Void = {
            $0.stopAccessingSecurityScopedResource()
        }
    ) {
        self.url = url
        self.isActive = isActive
        self.releaseAction = releaseAction
    }

    func release() {
        guard isActive else { return }
        isActive = false
        releaseAction(url)
    }
}

@MainActor
struct OutputDirectorySelection {
    let url: URL
    let accessLease: OutputDirectoryAccessLease

    var didStartAccessingSecurityScope: Bool {
        accessLease.isActive
    }

    init(
        url: URL,
        didStartAccessingSecurityScope: Bool,
        releaseAction: @escaping @MainActor (URL) -> Void = {
            $0.stopAccessingSecurityScopedResource()
        }
    ) {
        self.url = url
        self.accessLease = OutputDirectoryAccessLease(
            url: url,
            isActive: didStartAccessingSecurityScope,
            releaseAction: releaseAction
        )
    }

    func releaseAccess() {
        accessLease.release()
    }

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

        let response: NSApplication.ModalResponse
        if let hostWindow = NSApp.keyWindow,
           !(hostWindow is NSPanel) {
            response = await panel.beginSheetModal(for: hostWindow)
        } else {
            NSApp.activate()
            response = await panel.begin()
        }

        guard response == .OK, let url = panel.url else { return nil }
        return OutputDirectorySelection(
            url: url,
            didStartAccessingSecurityScope: url.startAccessingSecurityScopedResource()
        )
    }
}
