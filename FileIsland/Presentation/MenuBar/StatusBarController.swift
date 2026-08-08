import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settingsWindowController: SettingsWindowController
    private let outputFolderStore: OutputFolderBookmarkStore
    private var latestState: IslandState = .idle
    private var progressItem: NSMenuItem?

    init(
        settingsWindowController: SettingsWindowController,
        outputFolderStore: OutputFolderBookmarkStore
    ) {
        self.settingsWindowController = settingsWindowController
        self.outputFolderStore = outputFolderStore
        super.init()
        configureStatusItem()
    }

    func update(for state: IslandState) {
        latestState = state
        let symbol: String
        switch state {
        case .preparing, .converting:
            symbol = "arrow.triangle.2.circlepath"
        case .success:
            symbol = "checkmark.circle.fill"
        case .failure:
            symbol = "exclamationmark.triangle.fill"
        default:
            symbol = "arrow.down.doc.fill"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "File Island")
    }

    func menuWillOpen(_ menu: NSMenu) {
        switch latestState {
        case let .converting(snapshot):
            progressItem?.title = "Converting — \(Int(snapshot.progress * 100))%"
            progressItem?.isHidden = false
        case .preparing:
            progressItem?.title = "Preparing conversion…"
            progressItem?.isHidden = false
        default:
            progressItem?.isHidden = true
        }
    }

    @objc private func openSettings() { settingsWindowController.show() }

    @objc private func openOutputFolder() {
        guard let url = outputFolderStore.displayURL else {
            settingsWindowController.show()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openAbout() { settingsWindowController.show(section: .about) }

    @objc private func showLicenses() {
        let alert = NSAlert()
        alert.messageText = "Open-source Licenses"
        alert.informativeText = "File Island currently contains no third-party runtime dependencies. The project license will be listed here before public distribution."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func reportIssue() {
        if let url = URL(string: "https://github.com/TREAFREE/FileIsland/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "File Island"
        update(for: .idle)

        let menu = NSMenu()
        menu.delegate = self
        let progress = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        progress.isHidden = true
        menu.addItem(progress)
        menu.addItem(item("Settings…", symbol: "gearshape", action: #selector(openSettings), key: ","))
        menu.addItem(item("Open Output Folder", symbol: "folder", action: #selector(openOutputFolder)))
        menu.addItem(.separator())
        menu.addItem(item("About File Island", symbol: "info.circle", action: #selector(openAbout)))
        menu.addItem(item("Open-source Licenses", symbol: "shippingbox", action: #selector(showLicenses)))
        menu.addItem(item("Report Issue", symbol: "envelope", action: #selector(reportIssue)))
        menu.addItem(.separator())
        menu.addItem(item("Quit File Island", symbol: "xmark.square", action: #selector(quit), key: "q"))
        progressItem = progress
        statusItem.menu = menu
    }

    private func item(
        _ title: String,
        symbol: String,
        action: Selector,
        key: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}
