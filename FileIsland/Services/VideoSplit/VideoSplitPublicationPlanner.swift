import Foundation

enum VideoSplitPublicationPlanningError: Error, Equatable, Sendable {
    case invalidOutputRoot
    case invalidArtifactGroup
    case noAvailableDestination
    case unsafeDestination
}

/// Chooses one collision suffix for an entire segment folder. The result is a
/// reservation plan only; `OutputArtifactPublisher` still performs the final
/// no-overwrite checks so a filesystem race fails closed.
struct VideoSplitPublicationPlanner: Sendable {
    func reserveSplitDirectories(
        for artifacts: [PlannedOutputArtifact],
        outputRoot: URL
    ) throws -> [PlannedOutputArtifact] {
        guard outputRoot.isFileURL,
              let values = try? outputRoot.resourceValues(
                  forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw VideoSplitPublicationPlanningError.invalidOutputRoot
        }

        let grouped = Dictionary(grouping: artifacts, by: { $0.id.sourceInputID })
        var reservedParents: Set<SafeRelativePath> = []
        var rewrittenByID: [OutputArtifactID: PlannedOutputArtifact] = [:]

        for sourceID in grouped.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let group = grouped[sourceID], !group.isEmpty,
                  let originalParent = group.first?.preferredRelativePath.parent,
                  group.allSatisfy({ $0.preferredRelativePath.parent == originalParent }) else {
                throw VideoSplitPublicationPlanningError.invalidArtifactGroup
            }
            let selectedParent = try availableParent(
                originalParent,
                outputRoot: outputRoot,
                reservedParents: reservedParents
            )
            reservedParents.insert(selectedParent)

            for artifact in group {
                guard let filename = artifact.preferredRelativePath.components.last else {
                    throw VideoSplitPublicationPlanningError.invalidArtifactGroup
                }
                let rewrittenPath: SafeRelativePath
                do {
                    rewrittenPath = try SafeRelativePath(
                        (selectedParent.components + [filename]).joined(separator: "/")
                    )
                } catch {
                    throw VideoSplitPublicationPlanningError.unsafeDestination
                }
                rewrittenByID[artifact.id] = PlannedOutputArtifact(
                    id: artifact.id,
                    preferredRelativePath: rewrittenPath
                )
            }
        }

        guard rewrittenByID.count == artifacts.count else {
            throw VideoSplitPublicationPlanningError.invalidArtifactGroup
        }
        return try artifacts.map { artifact in
            guard let rewritten = rewrittenByID[artifact.id] else {
                throw VideoSplitPublicationPlanningError.invalidArtifactGroup
            }
            return rewritten
        }
    }

    private func availableParent(
        _ original: SafeRelativePath,
        outputRoot: URL,
        reservedParents: Set<SafeRelativePath>
    ) throws -> SafeRelativePath {
        guard let baseName = original.components.last, !baseName.isEmpty else {
            throw VideoSplitPublicationPlanningError.invalidArtifactGroup
        }
        let ancestor = Array(original.components.dropLast())
        for sequence in 1...10_000 {
            let candidateName = sequence == 1 ? baseName : "\(baseName)-\(sequence)"
            let candidate: SafeRelativePath
            do {
                candidate = try SafeRelativePath(
                    (ancestor + [candidateName]).joined(separator: "/")
                )
            } catch {
                throw VideoSplitPublicationPlanningError.unsafeDestination
            }
            guard !reservedParents.contains(candidate) else { continue }
            let candidateURL: URL
            do {
                candidateURL = try candidate.resolvedURL(relativeTo: outputRoot)
            } catch {
                throw VideoSplitPublicationPlanningError.unsafeDestination
            }
            guard !FileManager.default.fileExists(atPath: candidateURL.path) else { continue }
            return candidate
        }
        throw VideoSplitPublicationPlanningError.noAvailableDestination
    }
}
