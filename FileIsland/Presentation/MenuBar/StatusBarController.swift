import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settingsWindowController: SettingsWindowController
    private let outputFolderStore: OutputFolderBookmarkStore
    private let localization: LocalizationController
    private let chooseInputsAction: @MainActor () -> Void
    private var latestState: IslandState = .idle
    private var isInputSelectionEnabled = true
    private var progressItem: NSMenuItem?
    private var chooseInputsItem: NSMenuItem?
    private lazy var statusAnimator = StatusItemAnimator { [weak self] image in
        self?.statusItem.button?.image = image
    }

    init(
        settingsWindowController: SettingsWindowController,
        outputFolderStore: OutputFolderBookmarkStore,
        localization: LocalizationController,
        chooseInputs: @MainActor @escaping () -> Void
    ) {
        self.settingsWindowController = settingsWindowController
        self.outputFolderStore = outputFolderStore
        self.localization = localization
        self.chooseInputsAction = chooseInputs
        super.init()
        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .fileIslandLanguageDidChange,
            object: localization
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(for state: IslandState) {
        latestState = state
        let symbol: String
        switch state {
        case .preparing:
            statusAnimator.start(progress: 0)
            updateAccessibilityDescription(localization.string("File Island, preparing conversion"))
            return
        case let .converting(snapshot):
            statusAnimator.start(progress: snapshot.progress)
            updateAccessibilityDescription(localization.string(
                "File Island, converting, %d percent",
                Int(min(max(snapshot.progress, 0), 1) * 100)
            ))
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

    func updateInputAvailability(_ isAvailable: Bool) {
        isInputSelectionEnabled = isAvailable
        chooseInputsItem?.isEnabled = isAvailable
    }

    private func idleStatusImage() -> NSImage? {
        guard let image = NSImage(named: "FileIslandMenuTemplate") else {
            return NSImage(
                systemSymbolName: "arrow.down.doc.fill",
                accessibilityDescription: localization.string("File Island")
            )
        }
        return StatusItemIconRenderer.normalizedTemplate(image)
    }

    func menuWillOpen(_ menu: NSMenu) {
        switch latestState {
        case let .converting(snapshot):
            progressItem?.title = localization.string(
                "Converting — %d%%",
                Int(snapshot.progress * 100)
            )
            progressItem?.isHidden = false
        case .preparing:
            progressItem?.title = localization.string("Preparing conversion…")
            progressItem?.isHidden = false
        default:
            progressItem?.isHidden = true
        }
    }

    @objc private func openSettings() { settingsWindowController.show() }

    @objc private func chooseInputs() { chooseInputsAction() }

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
        alert.messageText = localization.string("Third-party Licenses")
        alert.informativeText = localization.string("File Island's original code is proprietary and source-available. File Island includes FFmpeg 8.1.2 under the GNU LGPL v2.1 or later. The corresponding source archive, verified release signature, build recipe, license, and notices are included with the project and every binary Release. No GPL or nonfree components are enabled.")
        alert.addButton(withTitle: localization.string("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func reportIssue() {
        if let url = URL(string: "https://github.com/TREAFREE/FileIsland/issues") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func languageDidChange(_ notification: Notification) {
        configureStatusItem()
    }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = localization.string("File Island")

        let menu = NSMenu()
        menu.delegate = self
        let progress = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        progress.isHidden = true
        menu.addItem(progress)
        let chooseInputs = item(
            localization.string("Choose Files or Folder…"),
            symbol: "folder.badge.plus",
            action: #selector(chooseInputs),
            key: "o"
        )
        chooseInputs.isEnabled = isInputSelectionEnabled
        menu.addItem(chooseInputs)
        menu.addItem(.separator())
        menu.addItem(item(localization.string("Settings…"), symbol: "gearshape", action: #selector(openSettings), key: ","))
        menu.addItem(item(localization.string("Open Output Folder"), symbol: "folder", action: #selector(openOutputFolder)))
        menu.addItem(.separator())
        menu.addItem(item(localization.string("About File Island"), symbol: "info.circle", action: #selector(openAbout)))
        menu.addItem(item(localization.string("Third-party Licenses"), symbol: "shippingbox", action: #selector(showLicenses)))
        menu.addItem(item(localization.string("Report Issue"), symbol: "envelope", action: #selector(reportIssue)))
        menu.addItem(.separator())
        menu.addItem(item(localization.string("Quit File Island"), symbol: "xmark.square", action: #selector(quit), key: "q"))
        progressItem = progress
        chooseInputsItem = chooseInputs
        statusItem.menu = menu
        update(for: latestState)
    }

    private func updateAccessibilityDescription(_ description: String) {
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    private func statusDescription(for state: IslandState) -> String {
        switch state {
        case .success: localization.string("File Island, conversion completed")
        case .failure: localization.string("File Island, conversion failed")
        default: localization.string("File Island")
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
