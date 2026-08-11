import Darwin
import Foundation

struct LocalRegularMediaFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
}

extension LocalRegularMediaFileIdentity {
    var videoSplitIdentity: VideoSplitFileIdentity {
        VideoSplitFileIdentity(
            device: device,
            inode: inode,
            byteCount: byteCount,
            modificationSeconds: modificationSeconds,
            modificationNanoseconds: modificationNanoseconds
        )
    }
}

enum LocalRegularMediaFileValidationError: Error, Equatable, Sendable {
    case notLocalFile
    case symbolicLink
    case notRegularFile
    case unreadableFile
    case fileSizeMismatch
    case fileChanged
}

protocol LocalRegularMediaFileValidating: Sendable {
    func validate(
        _ url: URL,
        expectedByteCount: Int64?
    ) throws -> LocalRegularMediaFileIdentity
}

struct POSIXLocalRegularMediaFileValidator: LocalRegularMediaFileValidating {
    func validate(
        _ url: URL,
        expectedByteCount: Int64? = nil
    ) throws -> LocalRegularMediaFileIdentity {
        guard url.isFileURL else {
            throw LocalRegularMediaFileValidationError.notLocalFile
        }

        return try url.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                throw LocalRegularMediaFileValidationError.notLocalFile
            }

            var pathStatus = stat()
            guard lstat(path, &pathStatus) == 0 else {
                throw LocalRegularMediaFileValidationError.unreadableFile
            }
            guard pathStatus.st_mode & S_IFMT != S_IFLNK else {
                throw LocalRegularMediaFileValidationError.symbolicLink
            }
            guard pathStatus.st_mode & S_IFMT == S_IFREG else {
                throw LocalRegularMediaFileValidationError.notRegularFile
            }

            let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else {
                if errno == ELOOP {
                    throw LocalRegularMediaFileValidationError.symbolicLink
                }
                throw LocalRegularMediaFileValidationError.unreadableFile
            }
            defer { _ = close(descriptor) }

            var openedStatus = stat()
            guard fstat(descriptor, &openedStatus) == 0 else {
                throw LocalRegularMediaFileValidationError.unreadableFile
            }
            guard openedStatus.st_mode & S_IFMT == S_IFREG else {
                throw LocalRegularMediaFileValidationError.notRegularFile
            }
            guard pathStatus.st_dev == openedStatus.st_dev,
                  pathStatus.st_ino == openedStatus.st_ino,
                  pathStatus.st_size == openedStatus.st_size,
                  pathStatus.st_mtimespec.tv_sec == openedStatus.st_mtimespec.tv_sec,
                  pathStatus.st_mtimespec.tv_nsec == openedStatus.st_mtimespec.tv_nsec else {
                throw LocalRegularMediaFileValidationError.fileChanged
            }
            if let expectedByteCount,
               expectedByteCount != Int64(openedStatus.st_size) {
                throw LocalRegularMediaFileValidationError.fileSizeMismatch
            }

            return LocalRegularMediaFileIdentity(
                device: UInt64(openedStatus.st_dev),
                inode: UInt64(openedStatus.st_ino),
                byteCount: Int64(openedStatus.st_size),
                modificationSeconds: Int64(openedStatus.st_mtimespec.tv_sec),
                modificationNanoseconds: Int64(openedStatus.st_mtimespec.tv_nsec)
            )
        }
    }
}
