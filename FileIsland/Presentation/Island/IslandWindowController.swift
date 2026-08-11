import AppKit
import QuartzCore

@MainActor
final class IslandWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: IslandViewModel
    private let screenProvider: IslandScreenProvider
    private let localization: LocalizationController
    private let inputSelector: any IslandInputSelecting
    private var targetScreen: NSScreen?
    private var currentLayoutMode: IslandLayoutMode?
    private var stateObserver: ((IslandState) -> Void)?
    private var inputAvailabilityObserver: ((Bool) -> Void)?
    private var inputSelectionTask: Task<Void, Never>?
    private var focusWhenInteractionBecomesAvailable = false

    init(
        viewModel: IslandViewModel,
        screenProvider: IslandScreenProvider,
        localization: LocalizationController,
        inputSelector: any IslandInputSelecting = AppKitIslandInputSelector()
    ) {
        self.viewModel = viewModel
        self.screenProvider = screenProvider
        self.localization = localization
        self.inputSelector = inputSelector

        let panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)

        configure(panel)
        panel.delegate = self
        panel.contentView = IslandDropContainerView(
            viewModel: viewModel,
            localization: localization
        )
        viewModel.onLayoutModeChange = { [weak self] mode in
            self?.updateLayout(for: mode, animated: true)
        }
        viewModel.onStateChange = { [weak self] state in
            self?.stateDidChange(state)
        }
        viewModel.onInputAvailabilityChange = { [weak self] isAvailable in
            guard let self else { return }
            inputAvailabilityObserver?(isAvailable && inputSelectionTask == nil)
        }
        updateKeyboardInteraction(for: viewModel.state)

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
        inputSelectionTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func showIsland() {
        targetScreen = screenProvider.targetScreen()
        updateLayout(for: viewModel.state.layoutMode, animated: false)
        window?.orderFrontRegardless()
    }

    func observeState(_ observer: @escaping (IslandState) -> Void) {
        stateObserver = observer
        observer(viewModel.state)
    }

    func observeInputAvailability(_ observer: @escaping (Bool) -> Void) {
        inputAvailabilityObserver = observer
        observer(canChooseInputs)
    }

    func chooseInputs() {
        guard canChooseInputs else { return }

        let prompt = IslandInputSelectionPrompt(
            title: localization.string("Choose Files or Folder…"),
            message: localization.string(
                "Select one or more files, or an ordinary folder. Sources stay untouched."
            ),
            actionTitle: localization.string("Choose")
        )
        let inputSelector = inputSelector
        inputSelectionTask = Task { [weak self, inputSelector] in
            let urls = await inputSelector.selectInputs(prompt: prompt)
            guard let self else { return }
            inputSelectionTask = nil
            inputAvailabilityObserver?(canChooseInputs)
            guard !Task.isCancelled,
                  let urls,
                  !urls.isEmpty else { return }

            focusWhenInteractionBecomesAvailable = true
            viewModel.receiveDrop(urls: urls)
        }
        inputAvailabilityObserver?(false)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setKeyboardInteractionActive(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setKeyboardInteractionActive(false)
    }

    private func configure(_ panel: IslandPanel) {
        panel.title = localization.string("File Island")
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

    private func stateDidChange(_ state: IslandState) {
        updateKeyboardInteraction(for: state)
        stateObserver?(state)

        if state == .idle || state == .dragHover {
            focusWhenInteractionBecomesAvailable = false
        }

        guard focusWhenInteractionBecomesAvailable,
              state.allowsKeyboardInteraction else { return }
        focusWhenInteractionBecomesAvailable = false
        focusKeyboardInteraction()
    }

    private func updateKeyboardInteraction(for state: IslandState) {
        (window as? IslandPanel)?.setKeyboardInteractionAllowed(
            state.allowsKeyboardInteraction
        )
    }

    private var canChooseInputs: Bool {
        viewModel.acceptsFileDrops && inputSelectionTask == nil
    }

    private func focusKeyboardInteraction() {
        guard viewModel.state.allowsKeyboardInteraction,
              let panel = window as? IslandPanel else { return }
        panel.setKeyboardInteractionAllowed(true)
        panel.orderFrontRegardless()
        panel.makeKey()
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

final class IslandPanel: NSPanel {
    private(set) var isKeyboardInteractionAllowed = false

    override var canBecomeKey: Bool { isKeyboardInteractionAllowed }
    override var canBecomeMain: Bool { false }

    func setKeyboardInteractionAllowed(_ isAllowed: Bool) {
        guard isKeyboardInteractionAllowed != isAllowed else { return }
        isKeyboardInteractionAllowed = isAllowed
        if !isAllowed, isKeyWindow {
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isKeyboardInteractionAllowed,
                      self.isKeyWindow else { return }
                self.resignKey()
            }
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           isKeyboardInteractionAllowed,
           !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}
