import Foundation

struct BatchRequestBuilder: Sendable {
    private let imagePlanBuilder: ImageConversionPlanBuilder
    private let videoPlanBuilder: VideoConversionPlanBuilder
    private let audioPlanBuilder: AudioConversionPlanBuilder

    init(
        imagePlanBuilder: ImageConversionPlanBuilder = ImageConversionPlanBuilder(),
        videoPlanBuilder: VideoConversionPlanBuilder = VideoConversionPlanBuilder(),
        audioPlanBuilder: AudioConversionPlanBuilder = AudioConversionPlanBuilder()
    ) {
        self.imagePlanBuilder = imagePlanBuilder
        self.videoPlanBuilder = videoPlanBuilder
        self.audioPlanBuilder = audioPlanBuilder
    }

    func makeRequest(
        id: UUID = UUID(),
        scan: InputScanResult,
        imageIntent: ImageIntent?,
        videoIntent: VideoIntent?,
        audioIntent: AudioIntent? = nil,
        outputDirectory: URL
    ) throws -> BatchConversionRequest {
        let buckets = Dictionary(grouping: scan.inputs, by: Self.groupKind)
        var groups: [ConversionGroup] = []

        for kind in ConversionGroupKind.allCases {
            let inputs = buckets[kind] ?? []
            let plan: ConversionPlan?
            switch kind {
            case .image:
                plan = try makeImagePlan(
                    inputs: inputs,
                    intent: imageIntent,
                    outputDirectory: outputDirectory
                )
            case .nativeVideo:
                plan = try makeVideoPlan(
                    inputs: inputs,
                    intent: videoIntent,
                    outputDirectory: outputDirectory,
                    removesTargetSize: false
                )
            case .fallbackVideo:
                plan = try makeVideoPlan(
                    inputs: inputs,
                    intent: videoIntent,
                    outputDirectory: outputDirectory,
                    removesTargetSize: true
                )
            case .audio:
                plan = try makeAudioPlan(
                    inputs: inputs,
                    intent: audioIntent,
                    outputDirectory: outputDirectory
                )
            case .unsupported:
                plan = nil
            }
            groups.append(ConversionGroup(kind: kind, inputs: inputs, plan: plan))
        }

        return BatchConversionRequest(
            id: id,
            selections: scan.selections,
            outputDirectory: outputDirectory,
            groups: groups
        )
    }

    private func makeImagePlan(
        inputs: [BatchInput],
        intent: ImageIntent?,
        outputDirectory: URL
    ) throws -> ConversionPlan? {
        guard let intent else { return nil }
        let executableInputs = inputs.filter { !Self.isNoOpImage($0.file, intent: intent) }
        guard !executableInputs.isEmpty else { return nil }
        return try imagePlanBuilder.makePlan(
            inputs: executableInputs.map(\.file),
            intent: intent,
            outputDirectory: outputDirectory
        )
    }

    private func makeVideoPlan(
        inputs: [BatchInput],
        intent: VideoIntent?,
        outputDirectory: URL,
        removesTargetSize: Bool
    ) throws -> ConversionPlan? {
        guard !inputs.isEmpty, var intent else { return nil }
        if removesTargetSize { intent.targetBytes = nil }
        return try videoPlanBuilder.makePlan(
            inputs: inputs.map(\.file),
            intent: intent,
            outputDirectory: outputDirectory
        )
    }

    private func makeAudioPlan(
        inputs: [BatchInput],
        intent: AudioIntent?,
        outputDirectory: URL
    ) throws -> ConversionPlan? {
        guard !inputs.isEmpty, let intent else { return nil }
        let executableInputs = inputs.filter {
            $0.file.format.rawValue != intent.outputFormat.rawValue
                || intent.stripMetadata
        }
        guard !executableInputs.isEmpty else { return nil }
        return try audioPlanBuilder.makePlan(
            inputs: executableInputs.map(\.file),
            intent: intent,
            outputDirectory: outputDirectory
        )
    }

    private static func groupKind(_ input: BatchInput) -> ConversionGroupKind {
        if MediaConversionMatrix.imageInputFormats.contains(input.file.format) {
            return .image
        }
        if MediaConversionMatrix.nativeVideoInputFormats.contains(input.file.format) {
            return .nativeVideo
        }
        if MediaConversionMatrix.fallbackVideoInputFormats.contains(input.file.format) {
            return .fallbackVideo
        }
        if MediaConversionMatrix.audioInputFormats.contains(input.file.format) {
            return .audio
        }
        return .unsupported
    }

    private static func isNoOpImage(_ file: InputFile, intent: ImageIntent) -> Bool {
        let sourceOutput: ImageOutputFormat?
        switch file.format {
        case .jpeg: sourceOutput = .jpeg
        case .png: sourceOutput = .png
        default: sourceOutput = nil
        }
        return sourceOutput == intent.outputFormat
            && intent.maxPixelDimension == nil
            && intent.targetBytes == nil
            && !intent.stripMetadata
    }
}
