import Darwin
import Foundation

enum OutputArtifactManifestError: Error, Equatable, Sendable {
    case emptyManifest
    case duplicatePlannedArtifact(OutputArtifactID)
    case duplicateStagedArtifact(OutputArtifactID)
    case artifactIdentityMismatch
    case foreignSourceInput(UUID)
    case invalidArtifactRole(OutputArtifactID)
    case invalidSegmentSet(UUID)
    case duplicateStagedFile(URL)
    case duplicateStagedFileIdentity(OutputArtifactFileIdentity)
    case invalidStagingRoot
    case stagingRootEscape(URL)
    case stagedItemIsSymbolicLink(URL)
    case stagedItemIsNotRegularFile(URL)
    case emptyStagedFile(URL)
    case fileExtensionMismatch(OutputArtifactID)
}

struct ValidatedOutputArtifact: Equatable, Sendable {
    let id: OutputArtifactID
    let preferredRelativePath: SafeRelativePath
    let stagedFileURL: URL
    let fileIdentity: OutputArtifactFileIdentity
}

struct ValidatedOutputArtifactManifest: Equatable, Sendable {
    let entries: [ValidatedOutputArtifact]
    let stagingRoot: URL

    fileprivate init(entries: [ValidatedOutputArtifact], stagingRoot: URL) {
        self.entries = entries
        self.stagingRoot = stagingRoot
    }
}

struct OutputArtifactManifestValidator: Sendable {
    func validate(
        plannedArtifacts: [PlannedOutputArtifact],
        stagedArtifacts: [StagedOutputArtifact],
        allowedSourceInputIDs: Set<UUID>,
        stagingRoot: URL
    ) throws -> ValidatedOutputArtifactManifest {
        guard !plannedArtifacts.isEmpty else {
            throw OutputArtifactManifestError.emptyManifest
        }
        let canonicalRoot = try validatedRoot(stagingRoot)

        var plannedByID: [OutputArtifactID: PlannedOutputArtifact] = [:]
        for planned in plannedArtifacts {
            guard allowedSourceInputIDs.contains(planned.id.sourceInputID) else {
                throw OutputArtifactManifestError.foreignSourceInput(planned.id.sourceInputID)
            }
            try validate(role: planned.id.role, id: planned.id)
            guard plannedByID.updateValue(planned, forKey: planned.id) == nil else {
                throw OutputArtifactManifestError.duplicatePlannedArtifact(planned.id)
            }
        }
        try validateArtifactSets(plannedArtifacts)

        var stagedByID: [OutputArtifactID: StagedOutputArtifact] = [:]
        for staged in stagedArtifacts {
            guard stagedByID.updateValue(staged, forKey: staged.id) == nil else {
                throw OutputArtifactManifestError.duplicateStagedArtifact(staged.id)
            }
        }
        guard Set(plannedByID.keys) == Set(stagedByID.keys) else {
            throw OutputArtifactManifestError.artifactIdentityMismatch
        }

        var stagedFileURLs: Set<URL> = []
        var stagedFileIdentities: Set<OutputArtifactFileIdentity> = []
        var validated: [ValidatedOutputArtifact] = []
        validated.reserveCapacity(plannedArtifacts.count)
        for planned in plannedArtifacts {
            guard let staged = stagedByID[planned.id] else {
                throw OutputArtifactManifestError.artifactIdentityMismatch
            }
            let fileURL = staged.fileURL.standardizedFileURL
            guard stagedFileURLs.insert(fileURL).inserted else {
                throw OutputArtifactManifestError.duplicateStagedFile(fileURL)
            }
            let fileIdentity = try validateStagedFile(
                fileURL,
                canonicalRoot: canonicalRoot
            )
            guard stagedFileIdentities.insert(fileIdentity).inserted else {
                throw OutputArtifactManifestError.duplicateStagedFileIdentity(
                    fileIdentity
                )
            }
            guard fileURL.pathExtension.lowercased()
                    == planned.preferredRelativePath.components.last?
                        .split(separator: ".").last?.lowercased() else {
                throw OutputArtifactManifestError.fileExtensionMismatch(planned.id)
            }
            validated.append(
                ValidatedOutputArtifact(
                    id: planned.id,
                    preferredRelativePath: planned.preferredRelativePath,
                    stagedFileURL: fileURL,
                    fileIdentity: fileIdentity
                )
            )
        }
        return ValidatedOutputArtifactManifest(
            entries: validated,
            stagingRoot: canonicalRoot
        )
    }

    func revalidate(
        plannedArtifacts: [PlannedOutputArtifact],
        previouslyValidatedArtifacts: [ValidatedOutputArtifact],
        allowedSourceInputIDs: Set<UUID>,
        stagingRoot: URL
    ) throws -> ValidatedOutputArtifactManifest {
        var previousByID: [OutputArtifactID: ValidatedOutputArtifact] = [:]
        for artifact in previouslyValidatedArtifacts {
            guard previousByID.updateValue(artifact, forKey: artifact.id) == nil else {
                throw OutputArtifactManifestError.duplicateStagedArtifact(artifact.id)
            }
        }
        let current = try validate(
            plannedArtifacts: plannedArtifacts,
            stagedArtifacts: previouslyValidatedArtifacts.map {
                StagedOutputArtifact(id: $0.id, fileURL: $0.stagedFileURL)
            },
            allowedSourceInputIDs: allowedSourceInputIDs,
            stagingRoot: stagingRoot
        )
        guard current.entries.allSatisfy({ currentArtifact in
            previousByID[currentArtifact.id]?.fileIdentity == currentArtifact.fileIdentity
        }) else {
            throw OutputArtifactManifestError.artifactIdentityMismatch
        }
        return current
    }

    private func validatedRoot(_ root: URL) throws -> URL {
        guard root.isFileURL else {
            throw OutputArtifactManifestError.invalidStagingRoot
        }
        let root = root.standardizedFileURL
        var status = stat()
        guard lstat(root.path, &status) == 0,
              fileType(status.st_mode) == S_IFDIR else {
            throw OutputArtifactManifestError.invalidStagingRoot
        }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }

    private func validate(
        role: OutputArtifactRole,
        id: OutputArtifactID
    ) throws {
        if case let .videoSegment(ordinal, total) = role {
            guard total > 0, ordinal > 0, ordinal <= total else {
                throw OutputArtifactManifestError.invalidArtifactRole(id)
            }
        }
    }

    private func validateArtifactSets(_ planned: [PlannedOutputArtifact]) throws {
        let groups = Dictionary(grouping: planned, by: { $0.id.sourceInputID })
        for (sourceID, artifacts) in groups {
            let converted = artifacts.filter {
                if case .converted = $0.id.role { return true }
                return false
            }
            let segments: [(ordinal: Int, total: Int)] = artifacts.compactMap {
                if case let .videoSegment(ordinal, total) = $0.id.role {
                    return (ordinal, total)
                }
                return nil
            }
            if !converted.isEmpty {
                guard converted.count == 1, segments.isEmpty else {
                    throw OutputArtifactManifestError.invalidSegmentSet(sourceID)
                }
                continue
            }
            guard let total = segments.first?.total,
                  segments.count == total,
                  segments.allSatisfy({ $0.total == total }),
                  Set(segments.map(\.ordinal)) == Set(1...total) else {
                throw OutputArtifactManifestError.invalidSegmentSet(sourceID)
            }
        }
    }

    private func validateStagedFile(
        _ fileURL: URL,
        canonicalRoot: URL
    ) throws -> OutputArtifactFileIdentity {
        guard fileURL.isFileURL else {
            throw OutputArtifactManifestError.stagingRootEscape(fileURL)
        }
        let canonicalFile = fileURL.resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = canonicalRoot.pathComponents
        guard canonicalFile.pathComponents.count > rootComponents.count,
              canonicalFile.pathComponents.starts(with: rootComponents) else {
            throw OutputArtifactManifestError.stagingRootEscape(fileURL)
        }

        var status = stat()
        guard lstat(fileURL.path, &status) == 0 else {
            throw OutputArtifactManifestError.stagedItemIsNotRegularFile(fileURL)
        }
        switch fileType(status.st_mode) {
        case S_IFLNK:
            throw OutputArtifactManifestError.stagedItemIsSymbolicLink(fileURL)
        case S_IFREG:
            guard status.st_size > 0 else {
                throw OutputArtifactManifestError.emptyStagedFile(fileURL)
            }
        default:
            throw OutputArtifactManifestError.stagedItemIsNotRegularFile(fileURL)
        }
        return OutputArtifactFileIdentity(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            byteCount: Int64(status.st_size),
            modificationSeconds: Int64(status.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(status.st_mtimespec.tv_nsec)
        )
    }

    private func fileType(_ mode: mode_t) -> mode_t {
        mode & S_IFMT
    }
}
