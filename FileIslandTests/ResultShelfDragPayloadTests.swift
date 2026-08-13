import AppKit
import Foundation
import XCTest
@testable import FileIsland

final class ResultShelfDragPayloadTests: XCTestCase {
    func testDraggingSelectedCardIncludesSelectionInVisualOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try makeFiles(named: ["one.png", "two.mp4", "three.txt"], in: directory)

        let payload = ResultShelfDragPayload.urls(
            clickedIndex: 2,
            selectedIndexes: IndexSet([0, 2]),
            outputURLs: urls
        )

        XCTAssertEqual(payload, [urls[0], urls[2]])
    }

    func testDraggingUnselectedCardIncludesOnlyClickedFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try makeFiles(named: ["one.png", "two.png", "three.png"], in: directory)

        let payload = ResultShelfDragPayload.urls(
            clickedIndex: 1,
            selectedIndexes: IndexSet([0, 2]),
            outputURLs: urls
        )

        XCTAssertEqual(payload, [urls[1]])
    }

    func testPayloadKeepsPublishedFileURLsEvenWhenTheAppCannotReadThemAgain() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try makeFiles(named: ["kept.png"], in: directory)[0]
        let missing = directory.appendingPathComponent("missing.png")
        let remote = URL(string: "https://example.com/output.png")!
        let urls = [file, missing, directory, remote]

        let payload = ResultShelfDragPayload.urls(
            clickedIndex: 0,
            selectedIndexes: IndexSet(integersIn: 0..<urls.count),
            outputURLs: urls
        )

        XCTAssertEqual(payload, [file, missing])
    }

    func testThirteenPublishedURLsRemainTransferableAfterVirtualizedItemsAreReused() {
        let directory = URL(fileURLWithPath: "/private/output", isDirectory: true)
        let urls = (1...13).map {
            directory.appendingPathComponent("image-\($0).jpg")
        }

        let payload = ResultShelfDragPayload.urls(
            clickedIndex: 12,
            selectedIndexes: IndexSet(integersIn: 0..<urls.count),
            outputURLs: urls
        )

        XCTAssertEqual(payload, urls)
    }

    @MainActor
    func testIslandDropTargetRejectsDragOriginatingFromItsOwnResultShelf() {
        let resultShelf = ResultShelfCollectionView()

        XCTAssertFalse(IslandDropSourcePolicy.accepts(resultShelf))
        XCTAssertTrue(IslandDropSourcePolicy.accepts(nil))
        XCTAssertTrue(IslandDropSourcePolicy.accepts(NSView()))
    }

    func testInvalidClickedIndexProducesNoPayload() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try makeFiles(named: ["one.png"], in: directory)

        XCTAssertTrue(
            ResultShelfDragPayload.urls(
                clickedIndex: 4,
                selectedIndexes: [],
                outputURLs: urls
            ).isEmpty
        )
    }

    @MainActor
    func testResultShelfReceivesTheFirstDragGestureWithoutOrderingItsPanel() throws {
        let view = ResultShelfCollectionView()
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            )
        )

        XCTAssertTrue(view.acceptsFirstMouse(for: event))
        XCTAssertTrue(view.shouldDelayWindowOrdering(for: event))
    }

    @MainActor
    func testCollectionDelegateAlwaysProducesAFileURLWriterForPublishedResults() {
        let output = URL(fileURLWithPath: "/private/output/image-13.jpg")
        let shelf = ResultShelfView(
            outputURLs: [output],
            copyTitle: "Copy",
            revealTitle: "Reveal",
            selectAllTitle: "Select All",
            dragHelp: "Drag",
            missingHelp: "Missing",
            onReveal: { _ in }
        )
        let coordinator = shelf.makeCoordinator()
        let collectionView = ResultShelfCollectionView()
        coordinator.collectionView = collectionView
        coordinator.reloadIfNeeded(force: true)

        let writer = coordinator.collectionView(
            collectionView,
            pasteboardWriterForItemAt: IndexPath(item: 0, section: 0)
        )

        XCTAssertEqual(writer as? NSURL, output as NSURL)
    }

    @MainActor
    func testResultShelfRequestsTwoSequentialAppKitDraggingSessions() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = try makeFiles(named: ["drag-me.jpg"], in: directory)[0]
        let collectionView = ResultShelfCollectionView(
            frame: NSRect(x: 0, y: 0, width: 320, height: 100)
        )
        collectionView.dragURLProvider = { clickedIndex, selectedIndexes in
            ResultShelfDragPayload.urls(
                clickedIndex: clickedIndex,
                selectedIndexes: selectedIndexes,
                outputURLs: [output]
            )
        }
        collectionView.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        var dragSessionCount = 0
        var draggedURLs: [URL] = []
        collectionView.draggingSessionStarter = { items, _ in
            dragSessionCount += 1
            draggedURLs.append(contentsOf: items.compactMap {
                ($0.item as? NSURL) as URL?
            })
            return nil
        }

        func performDrag(eventNumber: Int) throws -> Bool {
            let event = try makeMouseEvent(
                type: .leftMouseDragged,
                location: NSPoint(x: 80, y: 40),
                windowNumber: 0,
                eventNumber: eventNumber
            )
            return collectionView.beginResultDrag(clickedIndex: 0, event: event)
        }

        XCTAssertTrue(try performDrag(eventNumber: 10))
        XCTAssertTrue(try performDrag(eventNumber: 20))

        XCTAssertEqual(dragSessionCount, 2)
        XCTAssertEqual(draggedURLs, [output, output])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFiles(named names: [String], in directory: URL) throws -> [URL] {
        try names.map { name in
            let url = directory.appendingPathComponent(name)
            try Data([0x01]).write(to: url)
            return url
        }
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint,
        windowNumber: Int,
        eventNumber: Int
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: [],
                timestamp: TimeInterval(eventNumber) / 100,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: eventNumber,
                clickCount: type == .leftMouseDown ? 1 : 0,
                pressure: type == .leftMouseUp ? 0 : 1
            )
        )
    }
}
