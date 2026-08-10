import Foundation

protocol InputScanning: Sendable {
    func scan(urls: [URL]) async throws -> InputScanResult
}

struct ExplicitFileInputScanner: InputScanning {
    let fileInspector: any FileInspecting

    func scan(urls: [URL]) async throws -> InputScanResult {
        let files = try await fileInspector.inspect(urls: urls)
        let inputs = try files.map { file in
            BatchInput(
                file: file,
                selection: .file(file.url),
                relativePath: try SafeRelativePath(file.url.lastPathComponent)
            )
        }
        return InputScanResult(
            selections: inputs.map(\.selection),
            inputs: inputs
        )
    }
}

enum InputScanningError: Error, Equatable, Sendable {
    case noFiles
    case notLocalFile
    case unsupportedRoot
    case unsafeRelativePath
}
