import Foundation

protocol FileInspecting: Sendable {
    func inspect(urls: [URL]) async throws -> [InputFile]
}

enum FileInspectionError: Error, Equatable, Sendable {
    case noFiles
    case notLocalFile(URL)
    case notRegularFile(URL)
    case unreadableFile(URL)
}
