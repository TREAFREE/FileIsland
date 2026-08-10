import Foundation
import UniformTypeIdentifiers

enum InputFileFormat: String, Equatable, Hashable, Sendable {
    case heic
    case heif
    case jpeg
    case png
    case webP
    case tiff
    case gif
    case bmp
    case avif
    case mov
    case mp4
    case m4v
    case mkv
    case webM
    case avi
    case mpeg
    case ts
    case flv
    case threeGP = "3gp"
    case wmv
    case mp3
    case wav
    case aiff
    case m4a
    case aac
    case flac
    case ogg
    case opus
    case ac3
    case other

    var displayName: String? {
        switch self {
        case .heic:
            "HEIC"
        case .heif:
            "HEIF"
        case .jpeg:
            "JPG"
        case .png:
            "PNG"
        case .webP:
            "WEBP"
        case .tiff:
            "TIFF"
        case .gif:
            "GIF"
        case .bmp:
            "BMP"
        case .avif:
            "AVIF"
        case .mov:
            "MOV"
        case .mp4:
            "MP4"
        case .m4v:
            "M4V"
        case .mkv:
            "MKV"
        case .webM:
            "WEBM"
        case .avi:
            "AVI"
        case .mpeg:
            "MPEG"
        case .ts:
            "TS"
        case .flv:
            "FLV"
        case .threeGP:
            "3GP"
        case .wmv:
            "WMV"
        case .mp3:
            "MP3"
        case .wav:
            "WAV"
        case .aiff:
            "AIFF"
        case .m4a:
            "M4A"
        case .aac:
            "AAC"
        case .flac:
            "FLAC"
        case .ogg:
            "OGG"
        case .opus:
            "OPUS"
        case .ac3:
            "AC3"
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
        if type.conforms(to: .heif) {
            return FileClassification(format: .heif, kind: .image)
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
        if type.conforms(to: .tiff) {
            return FileClassification(format: .tiff, kind: .image)
        }
        if isM4V(type) {
            return FileClassification(format: .m4v, kind: .video)
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
        if let preferredExtension = type.preferredFilenameExtension,
           let classification = classification(
               forNormalizedExtension: preferredExtension.lowercased()
           ) {
            return classification
        }
        return nil
    }

    private static func classification(
        forNormalizedExtension filenameExtension: String
    ) -> FileClassification? {
        switch filenameExtension {
        case "heic":
            FileClassification(format: .heic, kind: .image)
        case "heif":
            FileClassification(format: .heif, kind: .image)
        case "jpg", "jpeg":
            FileClassification(format: .jpeg, kind: .image)
        case "png":
            FileClassification(format: .png, kind: .image)
        case "webp":
            FileClassification(format: .webP, kind: .image)
        case "tif", "tiff":
            FileClassification(format: .tiff, kind: .image)
        case "gif":
            FileClassification(format: .gif, kind: .image)
        case "bmp", "dib":
            FileClassification(format: .bmp, kind: .image)
        case "avif":
            FileClassification(format: .avif, kind: .image)
        case "mov":
            FileClassification(format: .mov, kind: .video)
        case "mp4":
            FileClassification(format: .mp4, kind: .video)
        case "m4v":
            FileClassification(format: .m4v, kind: .video)
        case "mkv":
            FileClassification(format: .mkv, kind: .video)
        case "webm":
            FileClassification(format: .webM, kind: .video)
        case "avi":
            FileClassification(format: .avi, kind: .video)
        case "mpeg", "mpg", "mpe", "m1v", "m2v":
            FileClassification(format: .mpeg, kind: .video)
        case "ts", "mts", "m2ts":
            FileClassification(format: .ts, kind: .video)
        case "flv", "f4v":
            FileClassification(format: .flv, kind: .video)
        case "3gp", "3gpp":
            FileClassification(format: .threeGP, kind: .video)
        case "wmv", "asf":
            FileClassification(format: .wmv, kind: .video)
        case "mp3":
            FileClassification(format: .mp3, kind: .audio)
        case "wav", "wave":
            FileClassification(format: .wav, kind: .audio)
        case "aif", "aiff", "aifc":
            FileClassification(format: .aiff, kind: .audio)
        case "m4a":
            FileClassification(format: .m4a, kind: .audio)
        case "aac":
            FileClassification(format: .aac, kind: .audio)
        case "flac":
            FileClassification(format: .flac, kind: .audio)
        case "ogg", "oga":
            FileClassification(format: .ogg, kind: .audio)
        case "opus":
            FileClassification(format: .opus, kind: .audio)
        case "ac3":
            FileClassification(format: .ac3, kind: .audio)
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

    private static func isM4V(_ type: UTType) -> Bool {
        let identifier = type.identifier.lowercased()
        let preferredExtension = type.preferredFilenameExtension?.lowercased()
        return preferredExtension == "m4v"
            || identifier.contains("m4v")
            || identifier.hasSuffix(".m4v")
    }

    private static func isWebM(_ type: UTType) -> Bool {
        let identifier = type.identifier.lowercased()
        let preferredExtension = type.preferredFilenameExtension?.lowercased()
        return preferredExtension == "webm"
            || identifier.contains("webm")
            || identifier.hasSuffix(".webm")
    }
}
