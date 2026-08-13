import AppKit
import SwiftUI

enum IslandDropSourcePolicy {
    static func accepts(_ source: Any?) -> Bool {
        !(source is ResultShelfCollectionView)
    }
}

@MainActor
final class IslandDropContainerView: NSView {
    private let viewModel: IslandViewModel
    private let hostingView: KeyboardAwareHostingView
    private var exitResolutionTask: Task<Void, Never>?

    init(viewModel: IslandViewModel, localization: LocalizationController) {
        self.viewModel = viewModel
        self.hostingView = KeyboardAwareHostingView(
            rootView: AnyView(
                IslandView(viewModel: viewModel)
                    .environment(localization)
                    .environment(\.locale, localization.locale)
            ),
            allowsKeyboardInteraction: { [weak viewModel] in
                viewModel?.state.allowsKeyboardInteraction == true
            }
        )
        super.init(frame: .zero)

        registerForDraggedTypes([.fileURL])
        installHostingView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard IslandDropSourcePolicy.accepts(sender.draggingSource),
              viewModel.acceptsFileDrops,
              canReadFileURLs(from: sender.draggingPasteboard) else { return [] }
        exitResolutionTask?.cancel()
        viewModel.dragEntered()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        guard IslandDropSourcePolicy.accepts(sender?.draggingSource) else { return }
        resolveDragExitAfterTopEdgeTolerance()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        IslandDropSourcePolicy.accepts(sender.draggingSource)
            && viewModel.acceptsFileDrops
            && canReadFileURLs(from: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        exitResolutionTask?.cancel()
        guard IslandDropSourcePolicy.accepts(sender.draggingSource),
              viewModel.acceptsFileDrops else { return false }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL], !urls.isEmpty else {
            viewModel.dragExited()
            return false
        }

        viewModel.receiveDrop(urls: urls)
        return true
    }

    private func canReadFileURLs(from pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func resolveDragExitAfterTopEdgeTolerance() {
        exitResolutionTask?.cancel()
        exitResolutionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }

            while let self, self.shouldHoldExpandedAtPhysicalTopEdge {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
            }

            self?.viewModel.dragExited()
        }
    }

    private var shouldHoldExpandedAtPhysicalTopEdge: Bool {
        guard viewModel.presentationMode == .physicalNotch,
              let window,
              let screen = window.screen else { return false }

        return IslandDragExitPolicy.shouldKeepExpanded(
            pointer: NSEvent.mouseLocation,
            primaryButtonPressed: NSEvent.pressedMouseButtons & 1 == 1,
            screenFrame: screen.frame,
            islandFrame: window.frame
        )
    }

    private func installHostingView() {
        // IslandWindowController is the sole owner of panel geometry. Publishing
        // SwiftUI's content-driven intrinsic size here lets a wider pane resize
        // the borderless panel behind the controller's back.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

@MainActor
private final class KeyboardAwareHostingView: NSHostingView<AnyView> {
    private let allowsKeyboardInteraction: () -> Bool

    required init(rootView: AnyView) {
        self.allowsKeyboardInteraction = { false }
        super.init(rootView: rootView)
    }

    init(
        rootView: AnyView,
        allowsKeyboardInteraction: @escaping () -> Bool
    ) {
        self.allowsKeyboardInteraction = allowsKeyboardInteraction
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var needsPanelToBecomeKey: Bool {
        allowsKeyboardInteraction()
    }

    override var acceptsFirstResponder: Bool {
        allowsKeyboardInteraction()
    }
}
