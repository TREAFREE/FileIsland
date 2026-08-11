import Foundation
import Testing
@testable import FileIsland

@Suite("Output artifact manifest validation")
struct OutputArtifactManifestValidatorTests {
    @Test("Reordered engine artifacts are matched by stable identity")
    func reorderedArtifactsMapByIdentity() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let firstID = UUID()
        let secondID = UUID()
        let firstURL = try workspace.file("first.jpg")
        let secondURL = try workspace.file("second.jpg")
        let planned = [
            try planned(firstID, "nested/first.jpg"),
            try planned(secondID, "nested/second.jpg")
        ]

        let validated = try OutputArtifactManifestValidator().validate(
            plannedArtifacts: planned,
            stagedArtifacts: [
                StagedOutputArtifact(id: planned[1].id, fileURL: secondURL),
                StagedOutputArtifact(id: planned[0].id, fileURL: firstURL)
            ],
            allowedSourceInputIDs: [firstID, secondID],
            stagingRoot: workspace.url
        )

        #expect(validated.entries.map(\.id) == planned.map(\.id))
        #expect(validated.entries.map(\.stagedFileURL) == [firstURL, secondURL])
    }

    @Test("Missing, extra, duplicate, and foreign identities fail closed")
    func invalidIdentitySetsFailClosed() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sourceID = UUID()
        let foreignID = UUID()
        let expected = try planned(sourceID, "result.jpg")
        let file = try workspace.file("result.jpg")
        let extraFile = try workspace.file("extra.jpg")
        let validator = OutputArtifactManifestValidator()

        try expectFailure(.artifactIdentityMismatch) {
            try validator.validate(
                plannedArtifacts: [expected],
                stagedArtifacts: [],
                allowedSourceInputIDs: [sourceID],
                stagingRoot: workspace.url
            )
        }
        try expectFailure(.artifactIdentityMismatch) {
            try validator.validate(
                plannedArtifacts: [expected],
                stagedArtifacts: [
                    StagedOutputArtifact(id: expected.id, fileURL: file),
                    StagedOutputArtifact(
                        id: OutputArtifactID(sourceInputID: sourceID, role: .videoSegment(ordinal: 1, total: 1)),
                        fileURL: extraFile
                    )
                ],
                allowedSourceInputIDs: [sourceID],
                stagingRoot: workspace.url
            )
        }
        try expectFailure(.duplicateStagedArtifact(expected.id)) {
            try validator.validate(
                plannedArtifacts: [expected],
                stagedArtifacts: [
                    StagedOutputArtifact(id: expected.id, fileURL: file),
                    StagedOutputArtifact(id: expected.id, fileURL: extraFile)
                ],
                allowedSourceInputIDs: [sourceID],
                stagingRoot: workspace.url
            )
        }
        let foreign = try planned(foreignID, "foreign.jpg")
        try expectFailure(.foreignSourceInput(foreignID)) {
            try validator.validate(
                plannedArtifacts: [foreign],
                stagedArtifacts: [StagedOutputArtifact(id: foreign.id, fileURL: file)],
                allowedSourceInputIDs: [sourceID],
                stagingRoot: workspace.url
            )
        }
    }

    @Test("Invalid segment ordinal and total sets fail closed")
    func invalidSegmentSetsFailClosed() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sourceID = UUID()
        let file = try workspace.file("segment.mp4")
        let validator = OutputArtifactManifestValidator()

        for role in [
            OutputArtifactRole.videoSegment(ordinal: 0, total: 1),
            .videoSegment(ordinal: 2, total: 1),
            .videoSegment(ordinal: 1, total: 0)
        ] {
            let artifact = PlannedOutputArtifact(
                id: OutputArtifactID(sourceInputID: sourceID, role: role),
                preferredRelativePath: try SafeRelativePath("segment.mp4")
            )
            try expectFailure(.invalidArtifactRole(artifact.id)) {
                try validator.validate(
                    plannedArtifacts: [artifact],
                    stagedArtifacts: [StagedOutputArtifact(id: artifact.id, fileURL: file)],
                    allowedSourceInputIDs: [sourceID],
                    stagingRoot: workspace.url
                )
            }
        }

        let first = PlannedOutputArtifact(
            id: OutputArtifactID(sourceInputID: sourceID, role: .videoSegment(ordinal: 1, total: 2)),
            preferredRelativePath: try SafeRelativePath("part-01.mp4")
        )
        try expectFailure(.invalidSegmentSet(sourceID)) {
            try validator.validate(
                plannedArtifacts: [first],
                stagedArtifacts: [StagedOutputArtifact(id: first.id, fileURL: file)],
                allowedSourceInputIDs: [sourceID],
                stagingRoot: workspace.url
            )
        }
    }

    @Test("Empty files, directories, symlinks, duplicate files, and root escapes fail closed")
    func unsafeStagingEntriesFailClosed() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let outside = try Workspace()
        defer { outside.remove() }
        let sourceID = UUID()
        let expected = try planned(sourceID, "result.jpg")
        let validator = OutputArtifactManifestValidator()

        let empty = workspace.url.appendingPathComponent("empty.jpg")
        try Data().write(to: empty)
        try expectFailure(.emptyStagedFile(empty)) {
            try validate(expected, fileURL: empty, root: workspace.url, validator: validator)
        }

        let directory = workspace.url.appendingPathComponent("directory.jpg", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try expectFailure(.stagedItemIsNotRegularFile(directory)) {
            try validate(expected, fileURL: directory, root: workspace.url, validator: validator)
        }

        let target = try workspace.file("target.jpg")
        let symlink = workspace.url.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        try expectFailure(.stagedItemIsSymbolicLink(symlink)) {
            try validate(expected, fileURL: symlink, root: workspace.url, validator: validator)
        }

        let escaped = try outside.file("escaped.jpg")
        try expectFailure(.stagingRootEscape(escaped)) {
            try validate(expected, fileURL: escaped, root: workspace.url, validator: validator)
        }

        let secondSourceID = UUID()
        let second = try planned(secondSourceID, "second.jpg")
        try expectFailure(.duplicateStagedFile(target)) {
            try validator.validate(
                plannedArtifacts: [expected, second],
                stagedArtifacts: [
                    StagedOutputArtifact(id: expected.id, fileURL: target),
                    StagedOutputArtifact(id: second.id, fileURL: target)
                ],
                allowedSourceInputIDs: [sourceID, secondSourceID],
                stagingRoot: workspace.url
            )
        }
    }

    @Test("Two artifact paths backed by the same inode fail closed")
    func hardLinkedArtifactsFailClosed() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let firstSourceID = UUID()
        let secondSourceID = UUID()
        let first = try workspace.file("first.jpg", bytes: [0x01, 0x02])
        let second = workspace.url.appendingPathComponent("second.jpg")
        try FileManager.default.linkItem(at: first, to: second)
        let firstPlan = try planned(firstSourceID, "first.jpg")
        let secondPlan = try planned(secondSourceID, "second.jpg")

        do {
            _ = try OutputArtifactManifestValidator().validate(
                plannedArtifacts: [firstPlan, secondPlan],
                stagedArtifacts: [
                    StagedOutputArtifact(id: firstPlan.id, fileURL: first),
                    StagedOutputArtifact(id: secondPlan.id, fileURL: second)
                ],
                allowedSourceInputIDs: [firstSourceID, secondSourceID],
                stagingRoot: workspace.url
            )
            Issue.record("Expected hard-linked staged artifacts to be rejected")
        } catch {
            guard case .duplicateStagedFileIdentity =
                    error as? OutputArtifactManifestError else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test("Revalidation detects replacement after media validation")
    func revalidationDetectsReplacement() throws {
        let workspace = try Workspace()
        defer { workspace.remove() }
        let sourceID = UUID()
        let artifact = try planned(sourceID, "result.jpg")
        let file = try workspace.file("result.jpg", bytes: [0x01])
        let validator = OutputArtifactManifestValidator()
        let firstValidation = try validator.validate(
            plannedArtifacts: [artifact],
            stagedArtifacts: [StagedOutputArtifact(id: artifact.id, fileURL: file)],
            allowedSourceInputIDs: [sourceID],
            stagingRoot: workspace.url
        )
        try FileManager.default.removeItem(at: file)
        try Data([0x02, 0x03]).write(to: file)

        try expectFailure(.artifactIdentityMismatch) {
            try validator.revalidate(
                plannedArtifacts: [artifact],
                previouslyValidatedArtifacts: firstValidation.entries,
                allowedSourceInputIDs: [sourceID],
                stagingRoot: workspace.url
            )
        }
    }

    private func planned(_ sourceID: UUID, _ path: String) throws -> PlannedOutputArtifact {
        PlannedOutputArtifact(
            id: OutputArtifactID(sourceInputID: sourceID, role: .converted),
            preferredRelativePath: try SafeRelativePath(path)
        )
    }

    private func validate(
        _ planned: PlannedOutputArtifact,
        fileURL: URL,
        root: URL,
        validator: OutputArtifactManifestValidator
    ) throws -> ValidatedOutputArtifactManifest {
        try validator.validate(
            plannedArtifacts: [planned],
            stagedArtifacts: [StagedOutputArtifact(id: planned.id, fileURL: fileURL)],
            allowedSourceInputIDs: [planned.id.sourceInputID],
            stagingRoot: root
        )
    }

    private func expectFailure<T>(
        _ expected: OutputArtifactManifestError,
        operation: () throws -> T
    ) throws {
        do {
            _ = try operation()
            Issue.record("Expected \(expected)")
        } catch {
            #expect(error as? OutputArtifactManifestError == expected)
        }
    }
}

private struct Workspace {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

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
