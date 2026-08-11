import Foundation

protocol CLIOutputWriting: Sendable {
    func writeStandardOutput(_ data: Data)
    func writeStandardError(_ data: Data)
}

final class FileHandleCLIOutput: CLIOutputWriting, @unchecked Sendable {
    private let lock = NSLock()

    func writeStandardOutput(_ data: Data) {
        lock.withLock {
            try? FileHandle.standardOutput.write(contentsOf: data)
        }
    }

    func writeStandardError(_ data: Data) {
        lock.withLock {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }
}

enum CLIExitCode: Int32, Equatable, Sendable {
    case success = 0
    case argumentError = 2
    case unsupported = 3
    case permissionError = 4
    case cancelled = 5
    case conversionFailure = 6
    case partialSkip = 7
}
