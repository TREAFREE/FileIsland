import AppKit

@MainActor
final class IslandWindowController: NSWindowController {
    private let viewModel: IslandViewModel
    private let screenProvider: IslandScreenProvider
    private var targetScreen: NSScreen?

    init(
        viewModel: IslandViewModel,
        screenProvider: IslandScreenProvider
    ) {
        self.viewModel = viewModel
        self.screenProvider = screenProvider

        let panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        configure(panel)
        panel.contentView = IslandDropContainerView(viewModel: viewModel)
        viewModel.onLayoutModeChange = { [weak self] mode in
            self?.updateLayout(for: mode)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func showIsland() {
        targetScreen = screenProvider.targetScreen()
        updateLayout(for: viewModel.state.layoutMode)
        window?.orderFrontRegardless()
    }

    private func configure(_ panel: IslandPanel) {
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    private func updateLayout(for mode: IslandLayoutMode) {
        guard let screen = targetScreen
            ?? window?.screen
            ?? screenProvider.targetScreen() else { return }

        targetScreen = screen
        let geometry = screenProvider.geometry(for: screen)
        let presentationMode = screenProvider.presentationMode(for: screen)
        viewModel.updatePresentation(
            mode: presentationMode,
            notchOcclusionHeight: geometry.physicalNotchFrame?.height ?? 0
        )
        window?.hasShadow = presentationMode == .floatingPill
        let frame = IslandLayout.frame(in: geometry, mode: mode)
        window?.setFrame(frame, display: true)
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        targetScreen = screenProvider.targetScreen()
        updateLayout(for: viewModel.state.layoutMode)
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
