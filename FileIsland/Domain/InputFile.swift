import Foundation
import UniformTypeIdentifiers

struct InputFile: Identifiable, Codable, Equatable, Sendable {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case type
        case fileSize
        case displayName
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        displayName = try container.decode(String.self, forKey: .displayName)

        if let identifier = try container.decodeIfPresent(String.self, forKey: .type) {
            guard let reconstructedType = UTType(identifier) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown uniform type identifier: \(identifier)"
                )
            }
            type = reconstructedType
        } else {
            type = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(type?.identifier, forKey: .type)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(displayName, forKey: .displayName)
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
