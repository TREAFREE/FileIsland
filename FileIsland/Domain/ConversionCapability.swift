import Foundation

enum UnsupportedBatchKind: Equatable, Sendable {
    case video
    case audio
    case other
    case mixed
}

enum ConversionCapability: Equatable, Sendable {
    case image(availableFormats: [ImageOutputFormat])
    case video(
        availableResolutions: [VideoResolution],
        supportsTargetSize: Bool
    )
    case audio(availableFormats: [AudioOutputFormat])
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
            let formats = MediaConversionMatrix.imageOutputFormats(
                for: files.map(\.format)
            )
            return formats.isEmpty
                ? .unsupported(kind: .other)
                : .image(availableFormats: formats)
        case .video:
            switch MediaConversionMatrix.videoBackend(for: files.map(\.format)) {
            case .native:
                return .video(
                    availableResolutions: [.source, .p1080, .p720],
                    supportsTargetSize: true
                )
            case .ffmpegFallback:
                return .video(
                    availableResolutions: [.source, .p1080, .p720],
                    supportsTargetSize: false
                )
            case nil:
                return .unsupported(kind: .video)
            }
        case .audio:
            return files.allSatisfy({ MediaConversionMatrix.audioInputFormats.contains($0.format) })
                ? .audio(availableFormats: MediaConversionMatrix.audioOutputFormats)
                : .unsupported(kind: .audio)
        case .other:
            return .unsupported(kind: .other)
        }
    }
}
