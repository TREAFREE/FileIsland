import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

@MainActor
final class IslandPanelTests: XCTestCase {
    func testPanelBecomesKeyEligibleOnlyDuringExplicitInteraction() {
        let panel = IslandPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        XCTAssertFalse(panel.canBecomeKey)

        panel.setKeyboardInteractionAllowed(true)
        XCTAssertTrue(panel.canBecomeKey)

        panel.setKeyboardInteractionAllowed(false)
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testChooseInputsRoutesSelectionThroughTheExistingInspectionFlow() async {
        let url = URL(fileURLWithPath: "/tmp/menu-selected.png")
        let file = InputFile(
            url: url,
            type: .png,
            fileSize: 42,
            displayName: url.lastPathComponent
        )
        let selector = StubIslandInputSelector(urls: [url])
        let viewModel = IslandViewModel(
            fileInspector: IslandPanelStubFileInspector(files: [file])
        )
        let defaults = UserDefaults(suiteName: "IslandPanelTests.InputSelection")!
        defaults.removePersistentDomain(forName: "IslandPanelTests.InputSelection")
        let controller = IslandWindowController(
            viewModel: viewModel,
            screenProvider: IslandScreenProvider(),
            localization: LocalizationController(
                preferences: AppPreferences(defaults: defaults),
                preferredLanguages: { ["en"] }
            ),
            inputSelector: selector
        )
        defer { controller.close() }
        XCTAssertEqual(
            controller.window?.contentView?.subviews.first?.needsPanelToBecomeKey,
            false
        )
        controller.chooseInputs()
        for _ in 0..<200 where viewModel.state == .idle || viewModel.state == .inspecting {
            try? await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(viewModel.state, .droppedSummary([file]))
        XCTAssertEqual(selector.selectionCount, 1)
        XCTAssertEqual(
            controller.window?.contentView?.subviews.first?.needsPanelToBecomeKey,
            true
        )
    }

    func testChooseInputsDoesNotOpenASecondPickerWhileOneIsActive() async {
        let selector = SuspendedIslandInputSelector()
        let viewModel = IslandViewModel(
            fileInspector: IslandPanelStubFileInspector(files: [])
        )
        let defaults = UserDefaults(suiteName: "IslandPanelTests.RepeatedSelection")!
        defaults.removePersistentDomain(forName: "IslandPanelTests.RepeatedSelection")
        let controller = IslandWindowController(
            viewModel: viewModel,
            screenProvider: IslandScreenProvider(),
            localization: LocalizationController(
                preferences: AppPreferences(defaults: defaults),
                preferredLanguages: { ["en"] }
            ),
            inputSelector: selector
        )
        defer { controller.close() }
        var inputAvailability: [Bool] = []
        controller.observeInputAvailability { inputAvailability.append($0) }

        controller.chooseInputs()
        for _ in 0..<20 where selector.selectionCount == 0 {
            await Task.yield()
        }
        controller.chooseInputs()
        await Task.yield()

        XCTAssertEqual(selector.selectionCount, 1)
        XCTAssertEqual(inputAvailability.last, false)
        selector.finish(with: nil)
        for _ in 0..<20 where inputAvailability.last != true {
            await Task.yield()
        }
        XCTAssertEqual(inputAvailability.last, true)
    }
}

@MainActor
private final class StubIslandInputSelector: IslandInputSelecting {
    let urls: [URL]
    private(set) var selectionCount = 0

    init(urls: [URL]) {
        self.urls = urls
    }

    func selectInputs(prompt: IslandInputSelectionPrompt) async -> [URL]? {
        selectionCount += 1
        return urls
    }
}

@MainActor
private final class SuspendedIslandInputSelector: IslandInputSelecting {
    private var continuation: CheckedContinuation<[URL]?, Never>?
    private(set) var selectionCount = 0

    func selectInputs(prompt: IslandInputSelectionPrompt) async -> [URL]? {
        selectionCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with urls: [URL]?) {
        continuation?.resume(returning: urls)
        continuation = nil
    }
}

private struct IslandPanelStubFileInspector: FileInspecting {
    let files: [InputFile]

    func inspect(urls: [URL]) async throws -> [InputFile] {
        files
    }
}
