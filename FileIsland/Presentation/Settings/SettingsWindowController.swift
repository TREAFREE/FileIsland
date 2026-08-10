import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let viewModel: SettingsViewModel
    private let localization: LocalizationController
    private let navigation = SettingsNavigationModel()

    init(viewModel: SettingsViewModel, localization: LocalizationController) {
        self.viewModel = viewModel
        self.localization = localization
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = localization.string("File Island Settings")
        window.minSize = NSSize(width: 600, height: 410)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        installRootView()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: .fileIslandLanguageDidChange,
            object: localization
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func show(section: SettingsView.Pane = .general) {
        navigation.select(section)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func installRootView() {
        window?.contentView = NSHostingView(
            rootView: SettingsView(viewModel: viewModel, navigation: navigation)
                .environment(localization)
                .environment(\.locale, localization.locale)
        )
    }

    private func refreshLocalization() {
        window?.title = localization.string("File Island Settings")
    }

    @objc private func languageDidChange(_ notification: Notification) {
        refreshLocalization()
    }
}
