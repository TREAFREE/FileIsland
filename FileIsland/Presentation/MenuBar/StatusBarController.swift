import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settingsWindowController: SettingsWindowController
    private let outputFolderStore: OutputFolderBookmarkStore
    private var latestState: IslandState = .idle
    private var progressItem: NSMenuItem?
    private lazy var statusAnimator = StatusItemAnimator { [weak self] image in
        self?.statusItem.button?.image = image
    }

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
        case .preparing:
            statusAnimator.start(progress: 0)
            updateAccessibilityDescription("File Island, preparing conversion")
            return
        case let .converting(snapshot):
            statusAnimator.start(progress: snapshot.progress)
            updateAccessibilityDescription(
                "File Island, converting, \(Int(min(max(snapshot.progress, 0), 1) * 100)) percent"
            )
            return
        case .success:
            symbol = "checkmark.circle.fill"
        case .failure:
            symbol = "exclamationmark.triangle.fill"
        default:
            statusAnimator.stop()
            statusItem.button?.image = idleStatusImage()
            updateAccessibilityDescription(statusDescription(for: state))
            return
        }
        statusAnimator.stop()
        statusItem.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: statusDescription(for: state)
        )
        updateAccessibilityDescription(statusDescription(for: state))
    }

    private func idleStatusImage() -> NSImage? {
        guard let image = NSImage(named: "FileIslandMenuTemplate")?.copy() as? NSImage else {
            return NSImage(
                systemSymbolName: "arrow.down.doc.fill",
                accessibilityDescription: "File Island"
            )
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "File Island"
        return image
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
        alert.messageText = "Third-party Licenses"
        alert.informativeText = "File Island's original code is proprietary and source-available. File Island includes FFmpeg 8.1.2 under the GNU LGPL v2.1 or later. The corresponding source archive, verified release signature, build recipe, license, and notices are included with the project and every binary Release. No GPL or nonfree components are enabled."
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
        menu.addItem(item("Third-party Licenses", symbol: "shippingbox", action: #selector(showLicenses)))
        menu.addItem(item("Report Issue", symbol: "envelope", action: #selector(reportIssue)))
        menu.addItem(.separator())
        menu.addItem(item("Quit File Island", symbol: "xmark.square", action: #selector(quit), key: "q"))
        progressItem = progress
        statusItem.menu = menu
    }

    private func updateAccessibilityDescription(_ description: String) {
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    private func statusDescription(for state: IslandState) -> String {
        switch state {
        case .success: "File Island, conversion completed"
        case .failure: "File Island, conversion failed"
        default: "File Island"
        }
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
