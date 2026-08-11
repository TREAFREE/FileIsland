import Foundation

struct URLInputScanner: InputScanning {
    private let fileInspector: any FileInspecting

    init(fileInspector: any FileInspecting = URLFileInspector()) {
        self.fileInspector = fileInspector
    }

    func scan(urls: [URL]) async throws -> InputScanResult {
        try Task.checkCancellation()
        guard !urls.isEmpty else { throw InputScanningError.noFiles }
        for url in urls {
            try Task.checkCancellation()
            guard url.isFileURL else { throw InputScanningError.notLocalFile }
        }

        var scopedURLs: [URL] = []
        defer { scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }
        for url in urls {
            try Task.checkCancellation()
            if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) }
        }
        try Task.checkCancellation()

        let discoveryWorker = Task.detached(priority: .userInitiated) {
            try Self.discover(urls: urls)
        }
        let discoveries = try await withTaskCancellationHandler {
            try await discoveryWorker.value
        } onCancel: {
            discoveryWorker.cancel()
        }
        try Task.checkCancellation()
        guard !discoveries.isEmpty else { throw InputScanningError.noFiles }

        var discoveredURLs: [URL] = []
        discoveredURLs.reserveCapacity(discoveries.count)
        for discovery in discoveries {
            try Task.checkCancellation()
            discoveredURLs.append(discovery.url)
        }
        let files = try await fileInspector.inspect(urls: discoveredURLs)
        try Task.checkCancellation()
        guard files.count == discoveries.count else { throw InputScanningError.unsupportedRoot }

        var filesByURL: [URL: InputFile] = [:]
        filesByURL.reserveCapacity(files.count)
        for file in files {
            try Task.checkCancellation()
            guard filesByURL.updateValue(
                file,
                forKey: file.url.standardizedFileURL
            ) == nil else {
                throw InputScanningError.unsupportedRoot
            }
        }
        var inputs: [BatchInput] = []
        inputs.reserveCapacity(discoveries.count)
        for discovery in discoveries {
            try Task.checkCancellation()
            guard let file = filesByURL[discovery.url.standardizedFileURL] else {
                throw InputScanningError.unsupportedRoot
            }
            inputs.append(BatchInput(
                file: file,
                selection: discovery.selection,
                relativePath: discovery.relativePath
            ))
        }
        var selections: [InputSelection] = []
        for discovery in discoveries {
            try Task.checkCancellation()
            guard !selections.contains(discovery.selection) else { continue }
            selections.append(discovery.selection)
        }
        try Task.checkCancellation()
        return InputScanResult(selections: selections, inputs: inputs)
    }

    private struct Discovery: Sendable {
        let url: URL
        let selection: InputSelection
        let relativePath: SafeRelativePath
    }

    private static func discover(urls: [URL]) throws -> [Discovery] {
        var discoveries: [Discovery] = []
        for url in urls {
            try Task.checkCancellation()
            let standardizedURL = url.standardizedFileURL
            let values = try standardizedURL.resourceValues(forKeys: rootResourceKeys)
            try Task.checkCancellation()
            if values.isSymbolicLink == true || values.isPackage == true || values.isHidden == true {
                continue
            }
            if values.isRegularFile == true, values.isReadable != false {
                discoveries.append(
                    Discovery(
                        url: standardizedURL,
                        selection: .file(standardizedURL),
                        relativePath: try SafeRelativePath(standardizedURL.lastPathComponent)
                    )
                )
            } else if values.isDirectory == true {
                discoveries.append(contentsOf: try discoverFolder(standardizedURL))
            } else {
                throw InputScanningError.unsupportedRoot
            }
        }
        try Task.checkCancellation()
        let sorted = discoveries.sorted {
            if $0.selection.url.path != $1.selection.url.path {
                return $0.selection.url.path.localizedStandardCompare($1.selection.url.path) == .orderedAscending
            }
            return $0.relativePath.string.localizedStandardCompare($1.relativePath.string) == .orderedAscending
        }
        try Task.checkCancellation()
        return sorted
    }

    private static func discoverFolder(_ root: URL) throws -> [Discovery] {
        let manager = FileManager.default
        let selection = InputSelection.folder(root)
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(descendantResourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw InputScanningError.unsupportedRoot
        }

        var discoveries: [Discovery] = []
        while let child = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values: URLResourceValues
            do {
                values = try child.resourceValues(forKeys: descendantResourceKeys)
            } catch {
                if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if values.isSymbolicLink == true || values.isPackage == true {
                if values.isDirectory == true || values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, values.isReadable != false else { continue }
            let relativePath = try relativePath(from: root, to: child)
            discoveries.append(
                Discovery(url: child.standardizedFileURL, selection: selection, relativePath: relativePath)
            )
        }
        return discoveries
    }

    private static func relativePath(from root: URL, to child: URL) throws -> SafeRelativePath {
        let rootComponents = root.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        guard childComponents.count > rootComponents.count,
              childComponents.starts(with: rootComponents) else {
            throw InputScanningError.unsafeRelativePath
        }
        do {
            return try SafeRelativePath(childComponents.dropFirst(rootComponents.count).joined(separator: "/"))
        } catch {
            throw InputScanningError.unsafeRelativePath
        }
    }

    private static let rootResourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .isHiddenKey,
        .isReadableKey
    ]

    private static let descendantResourceKeys = rootResourceKeys
}
