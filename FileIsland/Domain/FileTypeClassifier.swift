import Foundation
import UniformTypeIdentifiers

enum InputFileFormat: String, Equatable, Sendable {
    case heic
    case jpeg
    case png
    case webP
    case mov
    case mp4
    case mkv
    case webM
    case other

    var displayName: String? {
        switch self {
        case .heic:
            "HEIC"
        case .jpeg:
            "JPG"
        case .png:
            "PNG"
        case .webP:
            "WEBP"
        case .mov:
            "MOV"
        case .mp4:
            "MP4"
        case .mkv:
            "MKV"
        case .webM:
            "WEBM"
        case .other:
            nil
        }
    }
}

struct FileClassification: Equatable, Sendable {
    let format: InputFileFormat
    let kind: MediaKind
}

enum FileTypeClassifier {
    static func classify(
        type: UTType?,
        filenameExtension: String
    ) -> FileClassification {
        if let exactTypeClassification = exactClassification(for: type) {
            return exactTypeClassification
        }

        if let extensionClassification = classification(
            forNormalizedExtension: filenameExtension.lowercased()
        ) {
            return extensionClassification
        }

        guard let type else {
            return FileClassification(format: .other, kind: .other)
        }

        if type.conforms(to: .image) {
            return FileClassification(format: .other, kind: .image)
        }
        if type.conforms(to: .movie) {
            return FileClassification(format: .other, kind: .video)
        }
        if type.conforms(to: .audio) {
            return FileClassification(format: .other, kind: .audio)
        }
        if type.conforms(to: .audiovisualContent) {
            return FileClassification(format: .other, kind: .video)
        }
        return FileClassification(format: .other, kind: .other)
    }

    private static func exactClassification(for type: UTType?) -> FileClassification? {
        guard let type else { return nil }

        if type.conforms(to: .heic) {
            return FileClassification(format: .heic, kind: .image)
        }
        if type.conforms(to: .jpeg) {
            return FileClassification(format: .jpeg, kind: .image)
        }
        if type.conforms(to: .png) {
            return FileClassification(format: .png, kind: .image)
        }
        if let webP = UTType(filenameExtension: "webp"), type.conforms(to: webP) {
            return FileClassification(format: .webP, kind: .image)
        }
        if type.conforms(to: .mpeg4Movie) {
            return FileClassification(format: .mp4, kind: .video)
        }
        if type.conforms(to: .quickTimeMovie) {
            return FileClassification(format: .mov, kind: .video)
        }
        if isWebM(type) {
            return FileClassification(format: .webM, kind: .video)
        }
        if isMatroska(type) {
            return FileClassification(format: .mkv, kind: .video)
        }
        return nil
    }

    private static func classification(
        forNormalizedExtension filenameExtension: String
    ) -> FileClassification? {
        switch filenameExtension {
        case "heic":
            FileClassification(format: .heic, kind: .image)
        case "jpg", "jpeg":
            FileClassification(format: .jpeg, kind: .image)
        case "png":
            FileClassification(format: .png, kind: .image)
        case "webp":
            FileClassification(format: .webP, kind: .image)
        case "mov":
            FileClassification(format: .mov, kind: .video)
        case "mp4":
            FileClassification(format: .mp4, kind: .video)
        case "mkv":
            FileClassification(format: .mkv, kind: .video)
        case "webm":
            FileClassification(format: .webM, kind: .video)
        default:
            nil
        }
    }

    private static func isMatroska(_ type: UTType) -> Bool {
        let identifier = type.identifier.lowercased()
        let preferredExtension = type.preferredFilenameExtension?.lowercased()
        return preferredExtension == "mkv"
            || identifier.contains("matroska")
            || identifier.hasSuffix(".mkv")
    }

    private static func isWebM(_ type: UTType) -> Bool {
        let identifier = type.identifier.lowercased()
        let preferredExtension = type.preferredFilenameExtension?.lowercased()
        return preferredExtension == "webm"
            || identifier.contains("webm")
            || identifier.hasSuffix(".webm")
    }
}
