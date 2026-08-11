import Darwin
import Foundation

enum OutputArtifactPublisherError: Error, Equatable, Sendable {
    case invalidOutputRoot
    case invalidDestinationPath
    case destinationUnavailable
    case publicationFailed
    case rollbackFailed
}

enum OutputArtifactCollisionPolicy: Equatable, Sendable {
    /// Preserve the established conversion behavior by selecting a safe
    /// per-file suffix when the preferred destination is occupied.
    case rename
    /// Publish only the already-reserved paths. Split batches use this after
    /// reserving a complete folder so a late race cannot fracture the group.
    case failIfUnavailable
}

struct OutputArtifactFileIdentity: Equatable, Hashable, Sendable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
}

protocol OutputArtifactFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func resourceValues(
        at url: URL,
        forKeys keys: Set<URLResourceKey>
    ) throws -> URLResourceValues
    func createDirectory(at url: URL) throws
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at url: URL) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func fileIdentity(at url: URL) throws -> OutputArtifactFileIdentity
}

struct FoundationOutputArtifactFileSystem: OutputArtifactFileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func resourceValues(
        at url: URL,
        forKeys keys: Set<URLResourceKey>
    ) throws -> URLResourceValues {
        try url.resourceValues(forKeys: keys)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    func fileIdentity(at url: URL) throws -> OutputArtifactFileIdentity {
        var status = stat()
        guard lstat(url.path, &status) == 0 else {
            throw OutputArtifactPublisherError.publicationFailed
        }
        return OutputArtifactFileIdentity(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino),
            byteCount: Int64(status.st_size),
            modificationSeconds: Int64(status.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(status.st_mtimespec.tv_nsec)
        )
    }
}

struct OutputArtifactPublisher: Sendable {
    private let fileSystem: any OutputArtifactFileSystem
    private let exactDirectoryCommitter: any ExactDirectoryCommitting

    init(
        fileSystem: any OutputArtifactFileSystem = FoundationOutputArtifactFileSystem(),
        exactDirectoryCommitter: any ExactDirectoryCommitting =
            POSIXExactDirectoryCommitter()
    ) {
        self.fileSystem = fileSystem
        self.exactDirectoryCommitter = exactDirectoryCommitter
    }

    func publish(
        _ manifest: ValidatedOutputArtifactManifest,
        to outputRoot: URL,
        protectedURLs: Set<URL> = [],
        collisionPolicy: OutputArtifactCollisionPolicy = .rename,
        cancellationCheck: @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
    ) throws -> [PublishedOutputArtifact] {
        try cancellationCheck()
        let root = try validatedOutputRoot(outputRoot)
        let reservations = try reserve(
            manifest.entries,
            outputRoot: root,
            protectedURLs: protectedURLs,
            collisionPolicy: collisionPolicy
        )
        if collisionPolicy == .failIfUnavailable {
            return try publishExactDirectoryUnits(
                reservations,
                manifest: manifest,
                outputRoot: root,
                cancellationCheck: cancellationCheck
            )
        }
        try preflightParentDirectories(
            reservations.map(\.destinationURL),
            outputRoot: root
        )

        var journal: [MoveJournalEntry] = []
        var createdDirectories: [URL] = []
        var createdDirectorySet: Set<URL> = []
        do {
            for reservation in reservations {
                try cancellationCheck()
                try createParentDirectories(
                    for: reservation.destinationURL,
                    outputRoot: root,
                    createdDirectories: &createdDirectories,
                    createdDirectorySet: &createdDirectorySet
                )
                guard !fileSystem.fileExists(at: reservation.destinationURL) else {
                    throw OutputArtifactPublisherError.destinationUnavailable
                }
                let sourceIdentity = try fileSystem.fileIdentity(
                    at: reservation.artifact.stagedFileURL
                )
                guard sourceIdentity == reservation.artifact.fileIdentity else {
                    throw OutputArtifactPublisherError.publicationFailed
                }
                try fileSystem.moveItem(
                    at: reservation.artifact.stagedFileURL,
                    to: reservation.destinationURL
                )
                // A successful move is already externally visible. Record the
                // expected identity before the first fallible post-move read so
                // rollback can still remove this request-owned artifact.
                journal.append(
                    MoveJournalEntry(
                        destinationURL: reservation.destinationURL,
                        identity: reservation.artifact.fileIdentity
                    )
                )
                let publishedIdentity = try fileSystem.fileIdentity(
                    at: reservation.destinationURL
                )
                guard publishedIdentity == reservation.artifact.fileIdentity else {
                    throw OutputArtifactPublisherError.publicationFailed
                }
                try cancellationCheck()
            }
        } catch {
            guard rollback(
                journal: journal,
                createdDirectories: createdDirectories
            ) else {
                throw OutputArtifactPublisherError.rollbackFailed
            }
            if error is CancellationError {
                throw CancellationError()
            }
            if let publisherError = error as? OutputArtifactPublisherError {
                throw publisherError
            }
            throw OutputArtifactPublisherError.publicationFailed
        }

        return zip(reservations, journal).map { reservation, _ in
            PublishedOutputArtifact(
                id: reservation.artifact.id,
                fileURL: reservation.destinationURL
            )
        }
    }

    private func publishExactDirectoryUnits(
        _ reservations: [Reservation],
        manifest: ValidatedOutputArtifactManifest,
        outputRoot: URL,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> [PublishedOutputArtifact] {
        let grouped = try exactGroups(reservations)
        let assemblyRoot = manifest.stagingRoot.appendingPathComponent(
            ".publication-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        guard !fileSystem.fileExists(at: assemblyRoot) else {
            throw OutputArtifactPublisherError.publicationFailed
        }
        do {
            try fileSystem.createDirectory(at: assemblyRoot)
        } catch {
            throw OutputArtifactPublisherError.publicationFailed
        }

        var preparedGroups: [PreparedExactGroup] = []
        var journal: [MoveJournalEntry] = []
        var createdDirectories: [URL] = []
        var createdDirectorySet: Set<URL> = []
        do {
            for (offset, group) in grouped.enumerated() {
                try cancellationCheck()
                let unitDirectory = assemblyRoot.appendingPathComponent(
                    "unit-\(offset + 1)",
                    isDirectory: true
                )
                try fileSystem.createDirectory(at: unitDirectory)
                var preparedArtifacts: [PreparedExactArtifact] = []
                for reservation in group.reservations {
                    try cancellationCheck()
                    guard let filename = reservation.artifact.preferredRelativePath
                        .components.last else {
                        throw OutputArtifactPublisherError.invalidDestinationPath
                    }
                    let currentIdentity = try fileSystem.fileIdentity(
                        at: reservation.artifact.stagedFileURL
                    )
                    guard currentIdentity == reservation.artifact.fileIdentity else {
                        throw OutputArtifactPublisherError.publicationFailed
                    }
                    let preparedURL = unitDirectory.appendingPathComponent(filename)
                    guard !fileSystem.fileExists(at: preparedURL) else {
                        throw OutputArtifactPublisherError.destinationUnavailable
                    }
                    try fileSystem.moveItem(
                        at: reservation.artifact.stagedFileURL,
                        to: preparedURL
                    )
                    guard try fileSystem.fileIdentity(at: preparedURL)
                            == reservation.artifact.fileIdentity else {
                        throw OutputArtifactPublisherError.publicationFailed
                    }
                    preparedArtifacts.append(
                        PreparedExactArtifact(
                            reservation: reservation,
                            preparedURL: preparedURL
                        )
                    )
                    try cancellationCheck()
                }
                preparedGroups.append(
                    PreparedExactGroup(
                        destinationParent: group.destinationParent,
                        unitDirectory: unitDirectory,
                        artifacts: preparedArtifacts
                    )
                )
            }

            var published: [PublishedOutputArtifact] = []
            for group in preparedGroups {
                try cancellationCheck()
                let commit = try exactDirectoryCommitter.commit(
                    sourceDirectory: group.unitDirectory,
                    destinationRelativePath: group.destinationParent,
                    outputRoot: outputRoot
                )
                for directory in commit.createdAncestorDirectories
                    + [commit.destinationDirectory]
                where createdDirectorySet.insert(directory).inserted {
                    createdDirectories.append(directory)
                }
                let committedArtifacts = group.artifacts.map { artifact in
                    (
                        artifact: artifact,
                        destination: commit.destinationDirectory.appendingPathComponent(
                            artifact.preparedURL.lastPathComponent
                        )
                    )
                }
                // Register every expected artifact before the first post-commit
                // filesystem read. The directory rename is already visible at
                // this point, so a failed identity read must still roll back the
                // complete publication unit rather than leave unjournaled files.
                journal.append(contentsOf: committedArtifacts.map { committed in
                    MoveJournalEntry(
                        destinationURL: committed.destination,
                        identity: committed.artifact.reservation.artifact.fileIdentity
                    )
                })
                for committed in committedArtifacts {
                    let artifact = committed.artifact
                    let destination = committed.destination
                    let identity = try fileSystem.fileIdentity(at: destination)
                    guard identity == artifact.reservation.artifact.fileIdentity else {
                        throw OutputArtifactPublisherError.publicationFailed
                    }
                    published.append(
                        PublishedOutputArtifact(
                            id: artifact.reservation.artifact.id,
                            fileURL: destination
                        )
                    )
                }
                try cancellationCheck()
            }
            try? fileSystem.removeItem(at: assemblyRoot)
            let byID = Dictionary(uniqueKeysWithValues: published.map { ($0.id, $0) })
            return try reservations.map { reservation in
                guard let artifact = byID[reservation.artifact.id] else {
                    throw OutputArtifactPublisherError.publicationFailed
                }
                return artifact
            }
        } catch {
            let rolledBack = rollback(
                journal: journal,
                createdDirectories: createdDirectories
            )
            try? fileSystem.removeItem(at: assemblyRoot)
            guard rolledBack else {
                throw OutputArtifactPublisherError.rollbackFailed
            }
            if error is CancellationError { throw CancellationError() }
            if let publisherError = error as? OutputArtifactPublisherError {
                throw publisherError
            }
            if error is ExactDirectoryCommitError {
                throw OutputArtifactPublisherError.destinationUnavailable
            }
            throw OutputArtifactPublisherError.publicationFailed
        }
    }

    private func exactGroups(
        _ reservations: [Reservation]
    ) throws -> [ExactReservationGroup] {
        var order: [SafeRelativePath] = []
        var grouped: [SafeRelativePath: [Reservation]] = [:]
        for reservation in reservations {
            guard let parent = reservation.artifact.preferredRelativePath.parent,
                  !parent.components.isEmpty else {
                throw OutputArtifactPublisherError.invalidDestinationPath
            }
            if grouped[parent] == nil { order.append(parent) }
            grouped[parent, default: []].append(reservation)
        }
        return try order.map { parent in
            guard let values = grouped[parent], !values.isEmpty,
                  Set(values.map { $0.artifact.id.sourceInputID }).count == 1 else {
                throw OutputArtifactPublisherError.invalidDestinationPath
            }
            return ExactReservationGroup(
                destinationParent: parent,
                reservations: values
            )
        }
    }

    private func validatedOutputRoot(_ outputRoot: URL) throws -> URL {
        guard outputRoot.isFileURL else {
            throw OutputArtifactPublisherError.invalidOutputRoot
        }
        let root = outputRoot.standardizedFileURL
        let values: URLResourceValues
        do {
            values = try fileSystem.resourceValues(
                at: root,
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw OutputArtifactPublisherError.invalidOutputRoot
        }
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw OutputArtifactPublisherError.invalidOutputRoot
        }
        return root.resolvingSymlinksInPath().standardizedFileURL
    }

    private func reserve(
        _ artifacts: [ValidatedOutputArtifact],
        outputRoot: URL,
        protectedURLs: Set<URL>,
        collisionPolicy: OutputArtifactCollisionPolicy
    ) throws -> [Reservation] {
        let protected = Set(protectedURLs.map {
            $0.standardizedFileURL.resolvingSymlinksInPath()
        })
        var reserved: Set<URL> = []
        var reservations: [Reservation] = []
        reservations.reserveCapacity(artifacts.count)

        for artifact in artifacts {
            var selected: URL?
            let maximumSequence = collisionPolicy == .rename ? 10_000 : 1
            for sequence in 1...maximumSequence {
                let relativePath = try collisionPath(
                    artifact.preferredRelativePath,
                    sequence: sequence
                )
                let candidate = try relativePath
                    .resolvedURL(relativeTo: outputRoot)
                    .standardizedFileURL
                let canonicalCandidate = candidate.resolvingSymlinksInPath()
                guard !protected.contains(canonicalCandidate),
                      !reserved.contains(candidate),
                      !fileSystem.fileExists(at: candidate) else {
                    continue
                }
                selected = candidate
                break
            }
            guard let selected else {
                throw OutputArtifactPublisherError.destinationUnavailable
            }
            reserved.insert(selected)
            reservations.append(
                Reservation(artifact: artifact, destinationURL: selected)
            )
        }
        return reservations
    }

    private func collisionPath(
        _ preferred: SafeRelativePath,
        sequence: Int
    ) throws -> SafeRelativePath {
        guard sequence > 1 else { return preferred }
        var components = preferred.components
        guard let filename = components.popLast() else {
            throw OutputArtifactPublisherError.invalidDestinationPath
        }
        let filenameValue = filename as NSString
        let pathExtension = filenameValue.pathExtension
        let baseName = filenameValue.deletingPathExtension
        guard !baseName.isEmpty else {
            throw OutputArtifactPublisherError.invalidDestinationPath
        }
        let collisionName = pathExtension.isEmpty
            ? "\(baseName)-\(sequence)"
            : "\(baseName)-\(sequence).\(pathExtension)"
        do {
            return try SafeRelativePath((components + [collisionName]).joined(separator: "/"))
        } catch {
            throw OutputArtifactPublisherError.invalidDestinationPath
        }
    }

    private func preflightParentDirectories(
        _ destinations: [URL],
        outputRoot: URL
    ) throws {
        for destination in destinations {
            var cursor = outputRoot
            let relativeComponents = destination.pathComponents
                .dropFirst(outputRoot.pathComponents.count)
                .dropLast()
            for component in relativeComponents {
                cursor.appendPathComponent(component, isDirectory: true)
                guard fileSystem.fileExists(at: cursor) else { continue }
                let values = try fileSystem.resourceValues(
                    at: cursor,
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    throw OutputArtifactPublisherError.invalidDestinationPath
                }
            }
        }
    }

    private func createParentDirectories(
        for destination: URL,
        outputRoot: URL,
        createdDirectories: inout [URL],
        createdDirectorySet: inout Set<URL>
    ) throws {
        var cursor = outputRoot
        let relativeComponents = destination.pathComponents
            .dropFirst(outputRoot.pathComponents.count)
            .dropLast()
        for component in relativeComponents {
            cursor.appendPathComponent(component, isDirectory: true)
            if fileSystem.fileExists(at: cursor) {
                let values = try fileSystem.resourceValues(
                    at: cursor,
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    throw OutputArtifactPublisherError.invalidDestinationPath
                }
            } else {
                try fileSystem.createDirectory(at: cursor)
                if createdDirectorySet.insert(cursor).inserted {
                    createdDirectories.append(cursor)
                }
            }
        }
    }

    private func rollback(
        journal: [MoveJournalEntry],
        createdDirectories: [URL]
    ) -> Bool {
        var succeeded = true
        for entry in journal.reversed() where fileSystem.fileExists(at: entry.destinationURL) {
            do {
                let currentIdentity = try fileSystem.fileIdentity(at: entry.destinationURL)
                if currentIdentity == entry.identity {
                    try fileSystem.removeItem(at: entry.destinationURL)
                }
            } catch {
                succeeded = false
            }
        }
        for directory in createdDirectories.reversed() where fileSystem.fileExists(at: directory) {
            do {
                let values = try fileSystem.resourceValues(
                    at: directory,
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                if values.isDirectory == true,
                   values.isSymbolicLink != true,
                   try fileSystem.contentsOfDirectory(at: directory).isEmpty {
                    try fileSystem.removeItem(at: directory)
                }
            } catch {
                succeeded = false
            }
        }
        return succeeded
    }
}

private struct Reservation: Sendable {
    let artifact: ValidatedOutputArtifact
    let destinationURL: URL
}

private struct MoveJournalEntry: Sendable {
    let destinationURL: URL
    let identity: OutputArtifactFileIdentity
}

private struct ExactReservationGroup: Sendable {
    let destinationParent: SafeRelativePath
    let reservations: [Reservation]
}

private struct PreparedExactArtifact: Sendable {
    let reservation: Reservation
    let preparedURL: URL
}

private struct PreparedExactGroup: Sendable {
    let destinationParent: SafeRelativePath
    let unitDirectory: URL
    let artifacts: [PreparedExactArtifact]
}
