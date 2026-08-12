import Foundation

enum ResultShelfDragPayload {
    static func urls(
        clickedIndex: Int,
        selectedIndexes: IndexSet,
        outputURLs: [URL]
    ) -> [URL] {
        guard outputURLs.indices.contains(clickedIndex) else { return [] }

        let candidateIndexes: [Int]
        if selectedIndexes.contains(clickedIndex) {
            candidateIndexes = selectedIndexes.sorted()
        } else {
            candidateIndexes = [clickedIndex]
        }

        return candidateIndexes.compactMap { index in
            eligibleURL(at: index, outputURLs: outputURLs)
        }
    }

    static func eligibleURL(at index: Int, outputURLs: [URL]) -> URL? {
        guard outputURLs.indices.contains(index) else { return nil }
        let url = outputURLs[index]
        // These URLs come from the validated publication manifest. Do not
        // re-open them here: a sandbox resource lookup can transiently fail
        // after publication even though Finder can still consume the file URL.
        // Returning nil would prevent NSCollectionView from starting a drag at
        // all, which is both misleading and impossible for the user to recover
        // from. Directories and non-file URLs are never valid shelf artifacts.
        guard url.isFileURL, !url.hasDirectoryPath else { return nil }
        return url
    }
}
