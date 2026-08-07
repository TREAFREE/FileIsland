import Foundation
import UniformTypeIdentifiers

struct URLFileInspector: FileInspecting {
    func inspect(urls: [URL]) async throws -> [InputFile] {
        guard !urls.isEmpty else {
            throw FileInspectionError.noFiles
        }

        return try await Task.detached(priority: .userInitiated) {
            try urls.map(Self.inspectSynchronously)
        }.value
    }

    private static func inspectSynchronously(url: URL) throws -> InputFile {
        guard url.isFileURL else {
            throw FileInspectionError.notLocalFile(url)
        }

        let keys: Set<URLResourceKey> = [
            .contentTypeKey,
            .fileSizeKey,
            .isRegularFileKey,
            .nameKey,
            .isReadableKey
        ]
        let values = try url.resourceValues(forKeys: keys)

        guard values.isRegularFile == true else {
            throw FileInspectionError.notRegularFile(url)
        }
        guard values.isReadable != false else {
            throw FileInspectionError.unreadableFile(url)
        }

        let fallbackType = url.pathExtension.isEmpty
            ? nil
            : UTType(filenameExtension: url.pathExtension)

        return InputFile(
            url: url,
            type: values.contentType ?? fallbackType,
            fileSize: Int64(values.fileSize ?? 0),
            displayName: values.name ?? url.lastPathComponent
        )
    }
}
