import AppKit
import QuartzCore

@MainActor
final class IslandWindowController: NSWindowController {
    private let viewModel: IslandViewModel
    private let screenProvider: IslandScreenProvider
    private var targetScreen: NSScreen?
    private var currentLayoutMode: IslandLayoutMode?

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
            self?.updateLayout(for: mode, animated: true)
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
        updateLayout(for: viewModel.state.layoutMode, animated: false)
        window?.orderFrontRegardless()
    }

    func observeState(_ observer: @escaping (IslandState) -> Void) {
        viewModel.onStateChange = observer
        observer(viewModel.state)
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

    private func updateLayout(for mode: IslandLayoutMode, animated: Bool) {
        guard let screen = targetScreen
            ?? window?.screen
            ?? screenProvider.targetScreen() else { return }

        targetScreen = screen
        let geometry = screenProvider.geometry(for: screen)
        let presentationMode = screenProvider.presentationMode(for: screen)
        let frame = IslandLayout.frame(in: geometry, mode: mode)
        viewModel.updatePresentation(
            mode: presentationMode,
            notchOcclusionHeight: geometry.physicalNotchFrame?.height ?? 0,
            notchOcclusionWidth: geometry.physicalNotchFrame?.width ?? 0,
            islandWidth: frame.width
        )
        window?.hasShadow = presentationMode == .floatingPill
        let previousMode = currentLayoutMode ?? mode
        currentLayoutMode = mode
        let duration = animated
            ? IslandMotionPolicy.windowDuration(
                from: previousMode,
                to: mode,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
            : 0
        guard duration > 0, window?.frame != frame else {
            window?.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            let curve = IslandMotionPolicy.easeOutControlPoints
            context.duration = duration
            context.allowsImplicitAnimation = true
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(curve.x1),
                Float(curve.y1),
                Float(curve.x2),
                Float(curve.y2)
            )
            window?.animator().setFrame(frame, display: true)
        }
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        targetScreen = screenProvider.targetScreen()
        updateLayout(for: viewModel.state.layoutMode, animated: false)
    }
}

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
