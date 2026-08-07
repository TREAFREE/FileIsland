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

    var kind: MediaKind {
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .other
    }

    var displayType: String {
        type?.preferredFilenameExtension?.uppercased()
            ?? type?.localizedDescription
            ?? "Unknown"
    }
}

enum MediaKind: String, Equatable, Sendable {
    case image
    case video
    case audio
    case other
}
