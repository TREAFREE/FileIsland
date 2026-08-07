import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

@MainActor
final class IslandViewModelTests: XCTestCase {
    func testDropBuildsExpandedSummaryFromInspectorResult() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.jpg"),
            type: .jpeg,
            fileSize: 42,
            displayName: "photo.jpg"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))

        viewModel.receiveDrop(urls: [file.url])
        XCTAssertEqual(viewModel.state, .inspecting)

        for _ in 0..<20 where viewModel.state == .inspecting {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.state, .droppedSummary([file]))
        XCTAssertEqual(viewModel.state.layoutMode, .expanded)
    }

    func testDragExitRestoresDroppedSummary() async {
        let file = InputFile(
            url: URL(fileURLWithPath: "/tmp/photo.jpg"),
            type: .jpeg,
            fileSize: 42,
            displayName: "photo.jpg"
        )
        let viewModel = IslandViewModel(fileInspector: StubFileInspector(files: [file]))

        viewModel.receiveDrop(urls: [file.url])
        for _ in 0..<20 where viewModel.state == .inspecting {
            await Task.yield()
        }

        viewModel.dragEntered()
        viewModel.dragExited()

        XCTAssertEqual(viewModel.state, .droppedSummary([file]))
    }
}

private struct StubFileInspector: FileInspecting {
    let files: [InputFile]

    func inspect(urls: [URL]) async throws -> [InputFile] {
        files
    }
}
