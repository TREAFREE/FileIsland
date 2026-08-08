import Foundation

enum UnsupportedBatchKind: Equatable, Sendable {
    case video
    case audio
    case other
    case mixed
}

enum ConversionCapability: Equatable, Sendable {
    case image(availableFormats: [ImageOutputFormat])
    case video(availableResolutions: [VideoResolution])
    case unsupported(kind: UnsupportedBatchKind)
}

struct ConversionCapabilityResolver: Sendable {
    func resolve(_ files: [InputFile]) -> ConversionCapability {
        guard !files.isEmpty else { return .unsupported(kind: .other) }
        let kinds = Set(files.map(\.kind))
        guard kinds.count == 1, let kind = kinds.first else {
            return .unsupported(kind: .mixed)
        }

        switch kind {
        case .image:
            let formats = [ImageOutputFormat.jpeg, .png].filter { output in
                files.allSatisfy { output.canConvert($0.format) }
            }
            return formats.isEmpty
                ? .unsupported(kind: .other)
                : .image(availableFormats: formats)
        case .video:
            let supportedFormats: Set<InputFileFormat> = [.mov, .mp4]
            guard files.allSatisfy({ supportedFormats.contains($0.format) }) else {
                return .unsupported(kind: .video)
            }
            return .video(availableResolutions: [.source, .p1080, .p720])
        case .audio:
            return .unsupported(kind: .audio)
        case .other:
            return .unsupported(kind: .other)
        }
    }
}
