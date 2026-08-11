import Darwin
import Foundation

enum CLIResourceError: Error, Equatable, Sendable {
    case executablePathUnavailable
    case presetCatalogMissing
    case ffmpegMissing
    case ffprobeMissing
    case mediaValidatorMissing
}

/// Resolves the current process image from the Darwin kernel rather than from
/// `argv[0]`. A shell or `/usr/bin/env` is allowed to supply a bare argv token,
/// so treating it as a filesystem path would make sibling resources relative
/// to an attacker-controlled working directory.
struct CLIExecutableURLResolver: Sendable {
    typealias ExecutablePathProvider = @Sendable () throws -> String

    private let executablePathProvider: ExecutablePathProvider

    init() {
        executablePathProvider = Self.kernelExecutablePath
    }

    init(executablePathProvider: @escaping ExecutablePathProvider) {
        self.executablePathProvider = executablePathProvider
    }

    func resolve() throws -> URL {
        let reportedPath = try executablePathProvider()
        guard reportedPath.hasPrefix("/"),
              reportedPath.utf8.contains(0) == false else {
            throw CLIResourceError.executablePathUnavailable
        }

        let resolvedPointer = reportedPath.withCString { path in
            realpath(path, nil)
        }
        guard let resolvedPointer else {
            throw CLIResourceError.executablePathUnavailable
        }
        defer { free(resolvedPointer) }

        let canonicalPath = String(cString: resolvedPointer)
        var metadata = stat()
        guard canonicalPath.hasPrefix("/"),
              lstat(canonicalPath, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              access(canonicalPath, X_OK) == 0 else {
            throw CLIResourceError.executablePathUnavailable
        }
        return URL(fileURLWithPath: canonicalPath, isDirectory: false)
    }

    private static func kernelExecutablePath() throws -> String {
        var capacity: UInt32 = 1_024
        let maximumCapacity: UInt32 = 1_048_576

        while capacity <= maximumCapacity {
            var buffer = [CChar](repeating: 0, count: Int(capacity))
            var requiredCapacity = capacity
            let result = buffer.withUnsafeMutableBufferPointer { pointer in
                _NSGetExecutablePath(pointer.baseAddress, &requiredCapacity)
            }
            if result == 0 {
                guard let terminator = buffer.firstIndex(of: 0),
                      terminator > buffer.startIndex else {
                    throw CLIResourceError.executablePathUnavailable
                }
                return String(
                    decoding: buffer[..<terminator].map {
                        UInt8(bitPattern: $0)
                    },
                    as: UTF8.self
                )
            }
            guard requiredCapacity > capacity,
                  requiredCapacity <= maximumCapacity else {
                throw CLIResourceError.executablePathUnavailable
            }
            capacity = requiredCapacity
        }
        throw CLIResourceError.executablePathUnavailable
    }
}

struct CLIResourceLocator: Sendable {
    let executableURL: URL

    func presetCatalogURL() throws -> URL {
        let url = resourceURL(named: "built-in-presets.json")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw CLIResourceError.presetCatalogMissing
        }
        return url
    }

    func ffmpegExecutableURL() throws -> URL {
        let url = resourceURL(named: "ffmpeg")
        guard isTrustedAdjacentExecutable(url) else {
            throw CLIResourceError.ffmpegMissing
        }
        return url
    }

    func ffprobeExecutableURL() throws -> URL {
        let url = resourceURL(named: "ffprobe")
        guard isTrustedAdjacentExecutable(url) else {
            throw CLIResourceError.ffprobeMissing
        }
        return url
    }

    func mediaValidatorExecutableURL() throws -> URL {
        let url = resourceURL(named: "FileIslandMediaValidator")
        guard isTrustedAdjacentExecutable(url) else {
            throw CLIResourceError.mediaValidatorMissing
        }
        return url
    }

    private func resourceURL(named name: String) -> URL {
        executableURL.standardizedFileURL.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: false)
    }

    private func isTrustedAdjacentExecutable(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              access(url.path, X_OK) == 0 else {
            return false
        }
        return true
    }
}
