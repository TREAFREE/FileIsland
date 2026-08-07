import Foundation
import UniformTypeIdentifiers

struct InputFile: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let type: UTType?
    let fileSize: Int64
    let displayName: String

    init(
        id: UUID = UUID(),
        url: URL,
        type: UTType?,
        fileSize: Int64,
        displayName: String
    ) {
        self.id = id
        self.url = url
        self.type = type
        self.fileSize = fileSize
        self.displayName = displayName
    }

    var format: InputFileFormat {
        classification.format
    }

    var kind: MediaKind {
        classification.kind
    }

    var displayType: String {
        format.displayName
            ?? type?.preferredFilenameExtension?.uppercased()
            ?? type?.localizedDescription
            ?? "Unknown"
    }

    private var classification: FileClassification {
        FileTypeClassifier.classify(
            type: type,
            filenameExtension: url.pathExtension
        )
    }
}

enum MediaKind: String, Equatable, Sendable {
    case image
    case video
    case audio
    case other
}
