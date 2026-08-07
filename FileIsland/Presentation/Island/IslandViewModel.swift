import Foundation
import Observation

@MainActor
@Observable
final class IslandViewModel {
    private(set) var state: IslandState = .idle
    private(set) var presentationMode: IslandPresentationMode = .floatingPill
    private(set) var notchOcclusionHeight: CGFloat = 0

    @ObservationIgnored
    private let fileInspector: any FileInspecting

    @ObservationIgnored
    private var inspectionTask: Task<Void, Never>?

    @ObservationIgnored
    private var activeRequestID: UUID?

    @ObservationIgnored
    private var stateBeforeDrag: IslandState?

    @ObservationIgnored
    var onLayoutModeChange: ((IslandLayoutMode) -> Void)?

    init(fileInspector: any FileInspecting) {
        self.fileInspector = fileInspector
    }

    func dragEntered() {
        guard state != .dragHover else { return }
        stateBeforeDrag = state
        setState(.dragHover)
    }

    func dragExited() {
        guard state == .dragHover else { return }
        setState(stateBeforeDrag ?? .idle)
        stateBeforeDrag = nil
    }

    func receiveDrop(urls: [URL]) {
        stateBeforeDrag = nil
        inspectionTask?.cancel()

        let requestID = UUID()
        activeRequestID = requestID
        setState(.inspecting)

        inspectionTask = Task { [weak self, fileInspector] in
            do {
                let files = try await fileInspector.inspect(urls: urls)
                guard !Task.isCancelled else { return }
                self?.finishInspection(requestID: requestID, result: .success(files))
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishInspection(requestID: requestID, result: .failure(error))
            }
        }
    }

    func reset() {
        inspectionTask?.cancel()
        activeRequestID = nil
        stateBeforeDrag = nil
        setState(.idle)
    }

    func updatePresentation(
        mode: IslandPresentationMode,
        notchOcclusionHeight: CGFloat
    ) {
        presentationMode = mode
        self.notchOcclusionHeight = notchOcclusionHeight
    }

    private func finishInspection(
        requestID: UUID,
        result: Result<[InputFile], Error>
    ) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil

        switch result {
        case let .success(files):
            setState(.droppedSummary(files))
        case .failure:
            setState(
                .failure(
                    UserFacingError(
                        title: "Couldn’t read this item",
                        message: "File Island accepts readable, ordinary files in this technical preview."
                    )
                )
            )
        }
    }

    private func setState(_ newState: IslandState) {
        let previousLayout = state.layoutMode
        state = newState
        if previousLayout != newState.layoutMode {
            onLayoutModeChange?(newState.layoutMode)
        }
    }
}
