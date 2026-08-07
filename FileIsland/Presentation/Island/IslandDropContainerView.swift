import AppKit
import SwiftUI

@MainActor
final class IslandDropContainerView: NSView {
    private let viewModel: IslandViewModel
    private let hostingView: NSHostingView<IslandView>
    private var exitResolutionTask: Task<Void, Never>?

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        self.hostingView = NSHostingView(rootView: IslandView(viewModel: viewModel))
        super.init(frame: .zero)

        registerForDraggedTypes([.fileURL])
        installHostingView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard canReadFileURLs(from: sender.draggingPasteboard) else { return [] }
        exitResolutionTask?.cancel()
        viewModel.dragEntered()
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        resolveDragExitAfterTopEdgeTolerance()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        canReadFileURLs(from: sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        exitResolutionTask?.cancel()
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
