import Foundation
import Testing
@testable import FileIsland

@Suite("Output artifact publication")
struct OutputArtifactPublisherTests {
    @Test("Complete manifest publishes in plan order with collision-safe names")
    func publishesCompleteManifestWithCollisionNames() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let firstID = UUID()
        let secondID = UUID()
        let first = try staging.file("first.jpg")
        let second = try staging.file("second.jpg")
        try output.file("nested/first.jpg", bytes: [0xEE])
        let planned = [
            try planned(firstID, "nested/first.jpg"),
            try planned(secondID, "nested/second.jpg")
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(id: planned[1].id, fileURL: second),
                StagedOutputArtifact(id: planned[0].id, fileURL: first)
            ],
            root: staging.url
        )

        let published = try OutputArtifactPublisher().publish(manifest, to: output.url)

        #expect(published.map(\.id) == planned.map(\.id))
        #expect(published.map { $0.fileURL.lastPathComponent } == ["first-2.jpg", "second.jpg"])
        #expect(published.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    }

    @Test("Exact publication rejects a directory created after whole-folder reservation")
    func exactPublicationRejectsLateDirectoryRace() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let sourceID = UUID()
        let stagedFile = try staging.file("segment.mp4")
        try FileManager.default.createDirectory(
            at: output.url.appendingPathComponent("movie", isDirectory: true),
            withIntermediateDirectories: false
        )
        let plannedArtifact = PlannedOutputArtifact(
            id: OutputArtifactID(
                sourceInputID: sourceID,
                role: .videoSegment(ordinal: 1, total: 1)
            ),
            preferredRelativePath: try SafeRelativePath("movie/segment-001.mp4")
        )
        let manifest = try validated(
            planned: [plannedArtifact],
            staged: [StagedOutputArtifact(id: plannedArtifact.id, fileURL: stagedFile)],
            root: staging.url
        )

        #expect(throws: OutputArtifactPublisherError.destinationUnavailable) {
            _ = try OutputArtifactPublisher().publish(
                manifest,
                to: output.url,
                collisionPolicy: .failIfUnavailable
            )
        }
        // Exact directory publication may consume request-owned staging while
        // assembling the hidden unit. The safety contract is that nothing
        // becomes visible at the reserved destination.
        #expect(!FileManager.default.fileExists(atPath: stagedFile.path))
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: output.url,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent) == ["movie"]
        )
    }

    @Test("Exclusive directory commit rejects a destination created in the rename window")
    func exclusiveCommitRejectsDestinationRace() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let sourceID = UUID()
        let stagedFile = try staging.file("segment.mp4")
        let artifact = PlannedOutputArtifact(
            id: OutputArtifactID(
                sourceInputID: sourceID,
                role: .videoSegment(ordinal: 1, total: 1)
            ),
            preferredRelativePath: try SafeRelativePath("movie/segment-001.mp4")
        )
        let manifest = try validated(
            planned: [artifact],
            staged: [StagedOutputArtifact(id: artifact.id, fileURL: stagedFile)],
            root: staging.url
        )
        let committer = POSIXExactDirectoryCommitter { destination in
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
            try Data("user-owned".utf8).write(
                to: destination.appendingPathComponent("note.txt")
            )
        }

        #expect(throws: OutputArtifactPublisherError.destinationUnavailable) {
            _ = try OutputArtifactPublisher(
                exactDirectoryCommitter: committer
            ).publish(
                manifest,
                to: output.url,
                collisionPolicy: .failIfUnavailable
            )
        }

        let destination = output.url.appendingPathComponent("movie")
        #expect(
            try Data(contentsOf: destination.appendingPathComponent("note.txt"))
                == Data("user-owned".utf8)
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("segment-001.mp4").path
            )
        )
    }

    @Test("Descriptor traversal rejects an ancestor replaced by a symbolic link")
    func exactCommitRejectsAncestorSymlinkSwap() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        let outside = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
            outside.remove()
        }
        let sourceID = UUID()
        let stagedFile = try staging.file("segment.mp4")
        let artifact = PlannedOutputArtifact(
            id: OutputArtifactID(
                sourceInputID: sourceID,
                role: .videoSegment(ordinal: 1, total: 1)
            ),
            preferredRelativePath: try SafeRelativePath(
                "safe/movie/segment-001.mp4"
            )
        )
        let manifest = try validated(
            planned: [artifact],
            staged: [StagedOutputArtifact(id: artifact.id, fileURL: stagedFile)],
            root: staging.url
        )
        let swappedAncestor = output.url.appendingPathComponent("safe")
        let committer = POSIXExactDirectoryCommitter { _ in
            try FileManager.default.removeItem(at: swappedAncestor)
            try FileManager.default.createSymbolicLink(
                at: swappedAncestor,
                withDestinationURL: outside.url
            )
        }

        #expect(throws: OutputArtifactPublisherError.destinationUnavailable) {
            _ = try OutputArtifactPublisher(
                exactDirectoryCommitter: committer
            ).publish(
                manifest,
                to: output.url,
                collisionPolicy: .failIfUnavailable
            )
        }

        #expect(
            !FileManager.default.fileExists(
                atPath: outside.url.appendingPathComponent("movie").path
            )
        )
        let values = try swappedAncestor.resourceValues(
            forKeys: [.isSymbolicLinkKey]
        )
        #expect(values.isSymbolicLink == true)
    }

    @Test("Exact publication exposes a complete folder in one commit")
    func exactPublicationCommitsCompleteFolder() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let sourceID = UUID()
        let planned = [
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: sourceID,
                    role: .videoSegment(ordinal: 1, total: 2)
                ),
                preferredRelativePath: try SafeRelativePath("movie/segment-001.mp4")
            ),
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: sourceID,
                    role: .videoSegment(ordinal: 2, total: 2)
                ),
                preferredRelativePath: try SafeRelativePath("movie/segment-002.mp4")
            )
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(
                    id: planned[0].id,
                    fileURL: try staging.file("first.mp4")
                ),
                StagedOutputArtifact(
                    id: planned[1].id,
                    fileURL: try staging.file("second.mp4")
                )
            ],
            root: staging.url
        )

        let published = try OutputArtifactPublisher(
            exactDirectoryCommitter: InspectingExactDirectoryCommitter(
                expectedFileCount: 2
            )
        ).publish(
            manifest,
            to: output.url,
            collisionPolicy: .failIfUnavailable
        )

        #expect(published.count == 2)
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: output.url.appendingPathComponent("movie"),
                includingPropertiesForKeys: nil
            ).count == 2
        )
    }

    @Test("Exact publication removes the complete committed folder when identity verification fails")
    func exactPublicationRollsBackCompleteFolderAfterIdentityReadFailure() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let sourceID = UUID()
        let planned = [
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: sourceID,
                    role: .videoSegment(ordinal: 1, total: 2)
                ),
                preferredRelativePath: try SafeRelativePath("movie/segment-001.mp4")
            ),
            PlannedOutputArtifact(
                id: OutputArtifactID(
                    sourceInputID: sourceID,
                    role: .videoSegment(ordinal: 2, total: 2)
                ),
                preferredRelativePath: try SafeRelativePath("movie/segment-002.mp4")
            )
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(
                    id: planned[0].id,
                    fileURL: try staging.file("first.mp4")
                ),
                StagedOutputArtifact(
                    id: planned[1].id,
                    fileURL: try staging.file("second.mp4")
                )
            ],
            root: staging.url
        )
        let fileSystem = FailingPublishedIdentityOnceFileSystem(
            outputRoot: output.url
        )

        #expect(throws: OutputArtifactPublisherError.publicationFailed) {
            _ = try OutputArtifactPublisher(fileSystem: fileSystem).publish(
                manifest,
                to: output.url,
                collisionPolicy: .failIfUnavailable
            )
        }

        #expect(
            !FileManager.default.fileExists(
                atPath: output.url.appendingPathComponent("movie").path
            )
        )
    }

    @Test("A staged file replaced after validation is never published")
    func replacedStagedFileIsRejected() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let sourceID = UUID()
        let stagedFile = try staging.file("result.jpg", bytes: [0x01])
        let artifact = try planned(sourceID, "result.jpg")
        let manifest = try validated(
            planned: [artifact],
            staged: [StagedOutputArtifact(id: artifact.id, fileURL: stagedFile)],
            root: staging.url
        )
        try FileManager.default.removeItem(at: stagedFile)
        try Data([0x02, 0x03]).write(to: stagedFile)

        #expect(throws: OutputArtifactPublisherError.publicationFailed) {
            _ = try OutputArtifactPublisher().publish(manifest, to: output.url)
        }
        #expect(
            !FileManager.default.fileExists(
                atPath: output.url.appendingPathComponent("result.jpg").path
            )
        )
    }

    @Test("Regular publication removes a moved artifact when identity verification fails")
    func regularPublicationRollsBackAfterIdentityReadFailure() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let sourceID = UUID()
        let stagedFile = try staging.file("result.jpg")
        let artifact = try planned(sourceID, "result.jpg")
        let manifest = try validated(
            planned: [artifact],
            staged: [StagedOutputArtifact(id: artifact.id, fileURL: stagedFile)],
            root: staging.url
        )

        #expect(throws: OutputArtifactPublisherError.publicationFailed) {
            _ = try OutputArtifactPublisher(
                fileSystem: FailingPublishedIdentityOnceFileSystem(
                    outputRoot: output.url
                )
            ).publish(manifest, to: output.url)
        }

        #expect(
            !FileManager.default.fileExists(
                atPath: output.url.appendingPathComponent("result.jpg").path
            )
        )
    }

    @Test("A later move failure rolls back only journaled files and empty created directories")
    func moveFailureRollsBackJournal() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let firstID = UUID()
        let secondID = UUID()
        let first = try staging.file("first.jpg")
        let second = try staging.file("second.jpg")
        let planned = [
            try planned(firstID, "created/first.jpg"),
            try planned(secondID, "created/second.jpg")
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(id: planned[0].id, fileURL: first),
                StagedOutputArtifact(id: planned[1].id, fileURL: second)
            ],
            root: staging.url
        )
        let fileSystem = FailingMoveFileSystem(failingMove: 2)

        do {
            _ = try OutputArtifactPublisher(fileSystem: fileSystem).publish(manifest, to: output.url)
            Issue.record("Expected publication failure")
        } catch {
            #expect(error as? OutputArtifactPublisherError == .publicationFailed)
        }

        #expect(!FileManager.default.fileExists(atPath: output.url.appendingPathComponent("created/first.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: output.url.appendingPathComponent("created").path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Publisher never removes an unrelated file placed in a request-created directory")
    func rollbackPreservesUnrelatedFile() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let firstID = UUID()
        let secondID = UUID()
        let first = try staging.file("first.jpg")
        let second = try staging.file("second.jpg")
        let planned = [
            try planned(firstID, "created/first.jpg"),
            try planned(secondID, "created/second.jpg")
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(id: planned[0].id, fileURL: first),
                StagedOutputArtifact(id: planned[1].id, fileURL: second)
            ],
            root: staging.url
        )
        let unrelated = output.url.appendingPathComponent("created/user-note.txt")
        let fileSystem = FailingMoveFileSystem(failingMove: 2) {
            try Data("user".utf8).write(to: unrelated)
        }

        #expect(throws: (any Error).self) {
            try OutputArtifactPublisher(fileSystem: fileSystem).publish(manifest, to: output.url)
        }

        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(!FileManager.default.fileExists(atPath: output.url.appendingPathComponent("created/first.jpg").path))
    }

    @Test("Cancellation during publication rolls back every already moved artifact")
    func cancellationDuringPublicationRollsBackJournal() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let firstID = UUID()
        let secondID = UUID()
        let first = try staging.file("first.jpg")
        let second = try staging.file("second.jpg")
        let planned = [
            try planned(firstID, "created/first.jpg"),
            try planned(secondID, "created/second.jpg")
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(id: planned[0].id, fileURL: first),
                StagedOutputArtifact(id: planned[1].id, fileURL: second)
            ],
            root: staging.url
        )
        let firstDestination = output.url.appendingPathComponent("created/first.jpg")

        #expect(throws: CancellationError.self) {
            _ = try OutputArtifactPublisher().publish(
                manifest,
                to: output.url,
                cancellationCheck: {
                    if FileManager.default.fileExists(atPath: firstDestination.path) {
                        throw CancellationError()
                    }
                }
            )
        }

        #expect(!FileManager.default.fileExists(atPath: firstDestination.path))
        #expect(!FileManager.default.fileExists(atPath: output.url.appendingPathComponent("created").path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test("Blocked parent is rejected before any staged artifact is moved")
    func preflightRejectsBlockedParent() throws {
        let staging = try PublisherWorkspace()
        let output = try PublisherWorkspace()
        defer {
            staging.remove()
            output.remove()
        }
        let firstID = UUID()
        let secondID = UUID()
        let first = try staging.file("first.jpg")
        let second = try staging.file("second.jpg")
        try output.file("blocked", bytes: [0xFF])
        let planned = [
            try planned(firstID, "safe/first.jpg"),
            try planned(secondID, "blocked/second.jpg")
        ]
        let manifest = try validated(
            planned: planned,
            staged: [
                StagedOutputArtifact(id: planned[0].id, fileURL: first),
                StagedOutputArtifact(id: planned[1].id, fileURL: second)
            ],
            root: staging.url
        )

        #expect(throws: (any Error).self) {
            try OutputArtifactPublisher().publish(manifest, to: output.url)
        }

        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(!FileManager.default.fileExists(atPath: output.url.appendingPathComponent("safe/first.jpg").path))
    }

    private func planned(_ sourceID: UUID, _ path: String) throws -> PlannedOutputArtifact {
        PlannedOutputArtifact(
            id: OutputArtifactID(sourceInputID: sourceID, role: .converted),
            preferredRelativePath: try SafeRelativePath(path)
        )
    }

    private func validated(
        planned: [PlannedOutputArtifact],
        staged: [StagedOutputArtifact],
        root: URL
    ) throws -> ValidatedOutputArtifactManifest {
        try OutputArtifactManifestValidator().validate(
            plannedArtifacts: planned,
            stagedArtifacts: staged,
            allowedSourceInputIDs: Set(planned.map(\.id.sourceInputID)),
            stagingRoot: root
        )
    }
}

private struct PublisherWorkspace {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    @discardableResult
    func file(_ relativePath: String, bytes: [UInt8] = [0x01]) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(bytes).write(to: fileURL)
        return fileURL
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class FailingMoveFileSystem: OutputArtifactFileSystem, @unchecked Sendable {
    private let fileManager = FileManager.default
    private let failingMove: Int
    private let beforeFailure: (() throws -> Void)?
    private var moveCount = 0

    init(failingMove: Int, beforeFailure: (() throws -> Void)? = nil) {
        self.failingMove = failingMove
        self.beforeFailure = beforeFailure
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func resourceValues(at url: URL, forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
        try url.resourceValues(forKeys: keys)
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        moveCount += 1
        if moveCount == failingMove {
            try beforeFailure?()
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    func fileIdentity(at url: URL) throws -> OutputArtifactFileIdentity {
        try FoundationOutputArtifactFileSystem().fileIdentity(at: url)
    }
}

private final class FailingPublishedIdentityOnceFileSystem:
    OutputArtifactFileSystem,
    @unchecked Sendable
{
    private let outputRoot: URL
    private let lock = NSLock()
    private var hasFailed = false
    private let base = FoundationOutputArtifactFileSystem()

    init(outputRoot: URL) {
        self.outputRoot = outputRoot.standardizedFileURL
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    func resourceValues(
        at url: URL,
        forKeys keys: Set<URLResourceKey>
    ) throws -> URLResourceValues {
        try base.resourceValues(at: url, forKeys: keys)
    }

    func createDirectory(at url: URL) throws {
        try base.createDirectory(at: url)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try base.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try base.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try base.contentsOfDirectory(at: url)
    }

    func fileIdentity(at url: URL) throws -> OutputArtifactFileIdentity {
        let candidate = url.standardizedFileURL
        let isPublishedArtifact = candidate.path.hasPrefix(outputRoot.path + "/")
        let shouldFail = lock.withLock {
            guard isPublishedArtifact, !hasFailed else { return false }
            hasFailed = true
            return true
        }
        if shouldFail {
            throw CocoaError(.fileReadUnknown)
        }
        return try base.fileIdentity(at: url)
    }
}

private struct InspectingExactDirectoryCommitter: ExactDirectoryCommitting {
    let expectedFileCount: Int

    func commit(
        sourceDirectory: URL,
        destinationRelativePath: SafeRelativePath,
        outputRoot: URL
    ) throws -> ExactDirectoryCommitResult {
        let destination = try destinationRelativePath.resolvedURL(
            relativeTo: outputRoot
        )
        guard !FileManager.default.fileExists(atPath: destination.path),
              try FileManager.default.contentsOfDirectory(
                  at: sourceDirectory,
                  includingPropertiesForKeys: nil
              ).count == expectedFileCount else {
            throw ExactDirectoryCommitError.commitFailed
        }
        return try POSIXExactDirectoryCommitter().commit(
            sourceDirectory: sourceDirectory,
            destinationRelativePath: destinationRelativePath,
            outputRoot: outputRoot
        )
    }
}
