import Darwin
import Foundation

enum ExactDirectoryCommitError: Error, Equatable, Sendable {
    case invalidOutputRoot
    case invalidSourceDirectory
    case unsafeDestinationAncestor
    case destinationUnavailable
    case crossDeviceCommit
    case commitFailed
}

struct ExactDirectoryCommitResult: Equatable, Sendable {
    let destinationDirectory: URL
    let createdAncestorDirectories: [URL]
}

protocol ExactDirectoryCommitting: Sendable {
    func commit(
        sourceDirectory: URL,
        destinationRelativePath: SafeRelativePath,
        outputRoot: URL
    ) throws -> ExactDirectoryCommitResult
}

/// Commits a fully assembled directory with one exclusive same-volume rename.
/// Destination ancestors are traversed from an open output-root descriptor and
/// never followed through a symbolic link.
struct POSIXExactDirectoryCommitter: ExactDirectoryCommitting {
    private let beforeRename: @Sendable (URL) throws -> Void

    init(beforeRename: @Sendable @escaping (URL) throws -> Void = { _ in }) {
        self.beforeRename = beforeRename
    }

    func commit(
        sourceDirectory: URL,
        destinationRelativePath: SafeRelativePath,
        outputRoot: URL
    ) throws -> ExactDirectoryCommitResult {
        guard sourceDirectory.isFileURL,
              outputRoot.isFileURL,
              let destinationName = destinationRelativePath.components.last,
              !destinationName.isEmpty else {
            throw ExactDirectoryCommitError.unsafeDestinationAncestor
        }

        let root = outputRoot.standardizedFileURL
        let rootDescriptor = try openDirectory(
            root,
            failure: .invalidOutputRoot
        )
        defer { _ = close(rootDescriptor) }

        let sourceParent = sourceDirectory.deletingLastPathComponent().standardizedFileURL
        let sourceDescriptor = try openDirectory(
            sourceParent,
            failure: .invalidSourceDirectory
        )
        defer { _ = close(sourceDescriptor) }

        var rootStatus = stat()
        var sourceStatus = stat()
        guard fstat(rootDescriptor, &rootStatus) == 0,
              fstat(sourceDescriptor, &sourceStatus) == 0 else {
            throw ExactDirectoryCommitError.commitFailed
        }
        guard rootStatus.st_dev == sourceStatus.st_dev else {
            throw ExactDirectoryCommitError.crossDeviceCommit
        }

        let ancestorComponents = Array(destinationRelativePath.components.dropLast())
        let traversal = try traverseAncestors(
            ancestorComponents,
            rootDescriptor: rootDescriptor,
            outputRoot: root
        )
        defer { _ = close(traversal.parentDescriptor) }

        let destinationDirectory = try destinationRelativePath
            .resolvedURL(relativeTo: root)
            .standardizedFileURL
        do {
            try validateSourceDirectory(
                sourceDirectory.lastPathComponent,
                parentDescriptor: sourceDescriptor
            )
            try beforeRename(destinationDirectory)
            try ensureDirectoryIdentityStillMatches(
                destinationDirectory.deletingLastPathComponent(),
                descriptor: traversal.parentDescriptor
            )

            let result = sourceDirectory.lastPathComponent.withCString { sourceName in
                destinationName.withCString { destinationNamePointer in
                    renameatx_np(
                        sourceDescriptor,
                        sourceName,
                        traversal.parentDescriptor,
                        destinationNamePointer,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard result == 0 else {
                if errno == EEXIST || errno == ENOTEMPTY {
                    throw ExactDirectoryCommitError.destinationUnavailable
                }
                throw ExactDirectoryCommitError.commitFailed
            }
        } catch {
            removeEmptyDirectories(traversal.createdDirectories)
            throw error
        }

        return ExactDirectoryCommitResult(
            destinationDirectory: destinationDirectory,
            createdAncestorDirectories: traversal.createdDirectories
        )
    }

    private func openDirectory(
        _ url: URL,
        failure: ExactDirectoryCommitError
    ) throws -> Int32 {
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw failure }
        return descriptor
    }

    private func traverseAncestors(
        _ components: [String],
        rootDescriptor: Int32,
        outputRoot: URL
    ) throws -> (parentDescriptor: Int32, createdDirectories: [URL]) {
        var currentDescriptor = dup(rootDescriptor)
        guard currentDescriptor >= 0 else {
            throw ExactDirectoryCommitError.commitFailed
        }
        var currentURL = outputRoot
        var created: [URL] = []

        do {
            for component in components {
                currentURL.appendPathComponent(component, isDirectory: true)
                var nextDescriptor = component.withCString {
                    openat(
                        currentDescriptor,
                        $0,
                        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                    )
                }
                if nextDescriptor < 0, errno == ENOENT {
                    let made = component.withCString {
                        mkdirat(
                            currentDescriptor,
                            $0,
                            mode_t(S_IRWXU | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)
                        )
                    }
                    if made == 0 {
                        created.append(currentURL)
                    } else if errno != EEXIST {
                        throw ExactDirectoryCommitError.unsafeDestinationAncestor
                    }
                    nextDescriptor = component.withCString {
                        openat(
                            currentDescriptor,
                            $0,
                            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
                        )
                    }
                }
                guard nextDescriptor >= 0 else {
                    throw ExactDirectoryCommitError.unsafeDestinationAncestor
                }
                _ = close(currentDescriptor)
                currentDescriptor = nextDescriptor
            }
            return (currentDescriptor, created)
        } catch {
            _ = close(currentDescriptor)
            throw error
        }
    }

    private func ensureDirectoryIdentityStillMatches(
        _ directory: URL,
        descriptor: Int32
    ) throws {
        var descriptorStatus = stat()
        var pathStatus = stat()
        guard fstat(descriptor, &descriptorStatus) == 0,
              directory.withUnsafeFileSystemRepresentation({ path in
                  guard let path else { return false }
                  return lstat(path, &pathStatus) == 0
              }),
              pathStatus.st_mode & S_IFMT == S_IFDIR,
              pathStatus.st_dev == descriptorStatus.st_dev,
              pathStatus.st_ino == descriptorStatus.st_ino else {
            throw ExactDirectoryCommitError.unsafeDestinationAncestor
        }
    }

    private func validateSourceDirectory(
        _ name: String,
        parentDescriptor: Int32
    ) throws {
        var status = stat()
        let result = name.withCString {
            fstatat(parentDescriptor, $0, &status, AT_SYMLINK_NOFOLLOW)
        }
        guard result == 0, status.st_mode & S_IFMT == S_IFDIR else {
            throw ExactDirectoryCommitError.invalidSourceDirectory
        }
    }

    private func removeEmptyDirectories(_ directories: [URL]) {
        for directory in directories.reversed() {
            guard let values = try? directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            ),
            values.isDirectory == true,
            values.isSymbolicLink != true,
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ),
            contents.isEmpty else { continue }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
