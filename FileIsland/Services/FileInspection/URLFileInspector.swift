import Foundation
import UniformTypeIdentifiers

struct URLFileInspector: FileInspecting {
    private let contentTypeResolver: @Sendable (URL) -> UTType?

    init() {
        contentTypeResolver = { url in
            try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        }
    }

    init(contentTypeResolver: @escaping @Sendable (URL) -> UTType?) {
        self.contentTypeResolver = contentTypeResolver
    }

    func inspect(urls: [URL]) async throws -> [InputFile] {
        try Task.checkCancellation()
        guard !urls.isEmpty else {
            throw FileInspectionError.noFiles
        }

        let contentTypeResolver = self.contentTypeResolver
        let worker = Task.detached(priority: .userInitiated) {
            var files: [InputFile] = []
            files.reserveCapacity(urls.count)
            for url in urls {
                try Task.checkCancellation()
                files.append(
                    try Self.inspectSynchronously(
                        url: url,
                        contentTypeResolver: contentTypeResolver
                    )
                )
            }
            try Task.checkCancellation()
            return files
        }
        let files = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return files
    }

    private static func inspectSynchronously(
        url: URL,
        contentTypeResolver: @Sendable (URL) -> UTType?
    ) throws -> InputFile {
        try Task.checkCancellation()
        guard url.isFileURL else {
            throw FileInspectionError.notLocalFile(url)
        }

        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .nameKey,
            .isReadableKey
        ]
        let values = try url.resourceValues(forKeys: keys)
        try Task.checkCancellation()

        guard values.isSymbolicLink != true else {
            throw FileInspectionError.notRegularFile(url)
        }
        guard values.isRegularFile == true else {
            throw FileInspectionError.notRegularFile(url)
        }
        guard values.isReadable != false else {
            throw FileInspectionError.unreadableFile(url)
        }

        let fallbackType = url.pathExtension.isEmpty
            ? nil
            : UTType(filenameExtension: url.pathExtension)
        let contentType = contentTypeResolver(url)
        try Task.checkCancellation()

        return InputFile(
            url: url,
            type: contentType ?? fallbackType,
            fileSize: Int64(values.fileSize ?? 0),
            displayName: values.name ?? url.lastPathComponent
        )
    }
}
