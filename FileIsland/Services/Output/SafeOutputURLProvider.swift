import Foundation

struct SafeOutputURLProvider: Sendable {
    func outputURL(
        for inputURL: URL,
        format: ImageOutputFormat,
        policy: OutputPolicy,
        reserved: Set<URL>
    ) throws -> URL {
        try outputURL(
            for: inputURL,
            filenameExtension: format.filenameExtension,
            policy: policy,
            reserved: reserved
        )
    }

    func outputURL(
        for inputURL: URL,
        filenameExtension: String,
        policy: OutputPolicy,
        reserved: Set<URL>
    ) throws -> URL {
        let normalizedExtension = filenameExtension
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !normalizedExtension.isEmpty,
              normalizedExtension.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw ConversionError.unsupportedOutput
        }
        let (directory, suffix) = destination(for: inputURL, policy: policy)
        guard isExistingDirectory(directory) else {
            throw ConversionError.permissionDenied
        }

        let baseName = inputURL.deletingPathExtension().lastPathComponent + suffix
        let reservedURLs = Set(reserved.map(\.standardizedFileURL))
        let standardizedInput = inputURL.standardizedFileURL

        for sequence in 1...10_000 {
            let collisionSuffix = sequence == 1 ? "" : "-\(sequence)"
            let filename = "\(baseName)\(collisionSuffix).\(normalizedExtension)"
            let candidate = directory
                .appendingPathComponent(filename, isDirectory: false)
                .standardizedFileURL

            guard candidate != standardizedInput,
                  !reservedURLs.contains(candidate),
                  !FileManager.default.fileExists(atPath: candidate.path) else {
                continue
            }
            return candidate
        }

        throw ConversionError.conversionFailed(underlying: "No available output filename.")
    }

    private func destination(
        for inputURL: URL,
        policy: OutputPolicy
    ) -> (directory: URL, suffix: String) {
        switch policy {
        case let .sameDirectory(suffix):
            (inputURL.deletingLastPathComponent(), suffix)
        case let .chosenDirectory(directory, suffix):
            (directory, suffix)
        }
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
