import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ImageConversionEngine: ConversionEngine {
    private let outputURLProvider: SafeOutputURLProvider
    private let targetSizeEncoder: ImageTargetSizeEncoder
    private var cancelledJobIDs: Set<UUID> = []

    init(
        outputURLProvider: SafeOutputURLProvider = SafeOutputURLProvider(),
        targetSizeEncoder: ImageTargetSizeEncoder = ImageTargetSizeEncoder()
    ) {
        self.outputURLProvider = outputURLProvider
        self.targetSizeEncoder = targetSizeEncoder
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool {
        Self.intent(for: plan) != nil
    }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult {
        guard let intent = Self.intent(for: plan),
              let outputFormat = intent.outputFormat else {
            throw ConversionError.unsupportedInput
        }

        var completedArtifacts: [StagedOutputArtifact] = []
        var reservedOutputs: Set<URL> = []
        defer { cancelledJobIDs.remove(plan.id) }

        do {
            try checkCancellation(for: plan.id)
            progress(0)

            for (index, input) in plan.inputs.enumerated() {
                try checkCancellation(for: plan.id)
                let outputURL = try outputURLProvider.outputURL(
                    for: input.url,
                    format: outputFormat,
                    policy: plan.outputPolicy,
                    reserved: reservedOutputs
                )
                reservedOutputs.insert(outputURL)

                let encodingTask = Task.detached(priority: .userInitiated) { [targetSizeEncoder] in
                    try Self.convert(
                        inputURL: input.url,
                        outputURL: outputURL,
                        intent: intent,
                        targetSizeEncoder: targetSizeEncoder
                    )
                }
                try await withTaskCancellationHandler {
                    try await encodingTask.value
                } onCancel: {
                    encodingTask.cancel()
                }

                completedArtifacts.append(
                    StagedOutputArtifact(
                        id: OutputArtifactID(
                            sourceInputID: input.id,
                            role: .converted
                        ),
                        fileURL: outputURL
                    )
                )
                try checkCancellation(for: plan.id)
                progress(Double(index + 1) / Double(plan.inputs.count))
            }

            return EngineExecutionResult(artifacts: completedArtifacts)
        } catch {
            for artifact in completedArtifacts {
                try? FileManager.default.removeItem(at: artifact.fileURL)
            }
            throw Self.map(error)
        }
    }

    func cancel(jobID: UUID) async {
        cancelledJobIDs.insert(jobID)
    }

    private func checkCancellation(for jobID: UUID) throws {
        guard !Task.isCancelled, !cancelledJobIDs.contains(jobID) else {
            throw ConversionError.cancelled
        }
    }

    private nonisolated static func intent(for plan: ConversionPlan) -> ImageIntent? {
        guard !plan.inputs.isEmpty,
              plan.steps.count == 1,
              case let .image(intent) = plan.steps[0],
              intent.targetBytes.map({ $0 > 0 }) ?? true,
              intent.maxPixelDimension.map({ $0 > 0 }) ?? true,
              let outputFormat = intent.outputFormat,
              MediaConversionMatrix.imageOutputFormats(
                for: plan.inputs.map(\.format)
              ).contains(outputFormat) else {
            return nil
        }
        return intent
    }

    private nonisolated static func convert(
        inputURL: URL,
        outputURL: URL,
        intent: ImageIntent,
        targetSizeEncoder: ImageTargetSizeEncoder
    ) throws {
        guard let outputFormat = intent.outputFormat else {
            throw ConversionError.unsupportedOutput
        }

        let accessed = inputURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                inputURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil) else {
            throw ConversionError.invalidMedia
        }
        let sourceIndex = CGImageSourceGetPrimaryImageIndex(source)
        guard let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, sourceIndex, nil)
                as? [CFString: Any],
              let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? NSNumber,
              let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ConversionError.invalidMedia
        }

        let sourceMaximum = max(sourceWidth.intValue, sourceHeight.intValue)
        let encodedData = try targetSizeEncoder.encode(
            source: source,
            sourceIndex: sourceIndex,
            sourceProperties: sourceProperties,
            sourceMaximumDimension: sourceMaximum,
            intent: intent
        )

        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".fileisland-\(UUID().uuidString).\(outputFormat.filenameExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try encodedData.write(to: temporaryURL, options: .atomic)
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw ConversionError.permissionDenied
        } catch {
            throw ConversionError.conversionFailed(underlying: "The output file could not be saved.")
        }
    }

    private nonisolated static func map(_ error: Error) -> ConversionError {
        if let conversionError = error as? ConversionError {
            return conversionError
        }
        if error is CancellationError {
            return .cancelled
        }
        return .conversionFailed(underlying: "The image conversion failed.")
    }
}
