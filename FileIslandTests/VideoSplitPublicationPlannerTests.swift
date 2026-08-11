import Foundation
import Testing
@testable import FileIsland

@Suite("Whole-folder split publication reservation")
struct VideoSplitPublicationPlannerTests {
    @Test("All segments receive one shared collision suffix")
    func reservesWholeFolder() throws {
        let temporary = try PublicationTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: temporary.url.appendingPathComponent("Movie — Split"),
            withIntermediateDirectories: false
        )
        let source = UUID(uuidString: "00000000-0000-0000-0000-000000000164")!
        let artifacts = try (1...3).map { ordinal in
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: source,
                    role: .videoSegment(ordinal: ordinal, total: 3)
                ),
                preferredRelativePath: try SafeRelativePath(
                    "Movie — Split/Movie-part-0\(ordinal)-of-03.mp4"
                )
            )
        }

        let reserved = try VideoSplitPublicationPlanner().reserveSplitDirectories(
            for: artifacts,
            outputRoot: temporary.url
        )

        #expect(reserved.map { $0.preferredRelativePath.parent?.string } == [
            "Movie — Split-2", "Movie — Split-2", "Movie — Split-2"
        ])
    }

    @Test("Two same-name source groups reserve distinct directories")
    func reservesDistinctBatchFolders() throws {
        let temporary = try PublicationTemporaryDirectory()
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000165")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000166")!
        let artifacts = try [first, second].map { source in
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: source,
                    role: .videoSegment(ordinal: 1, total: 1)
                ),
                preferredRelativePath: try SafeRelativePath(
                    "Folder/Movie — Split/Movie-part-01-of-01.mp4"
                )
            )
        }

        let reserved = try VideoSplitPublicationPlanner().reserveSplitDirectories(
            for: artifacts,
            outputRoot: temporary.url
        )

        #expect(Set(reserved.compactMap { $0.preferredRelativePath.parent?.string }) == [
            "Folder/Movie — Split", "Folder/Movie — Split-2"
        ])
    }
}

private final class PublicationTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "FileIsland-PublicationPlanner-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
