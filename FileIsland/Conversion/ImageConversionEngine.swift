import Foundation
import ImageIO
import UniformTypeIdentifiers

actor ImageConversionEngine: ConversionEngine {
    private let outputURLProvider: SafeOutputURLProvider
    private var cancelledJobIDs: Set<UUID> = []

    init(outputURLProvider: SafeOutputURLProvider = SafeOutputURLProvider()) {
        self.outputURLProvider = outputURLProvider
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool {
        Self.intent(for: plan) != nil
    }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable (Double) -> Void
    ) async throws -> [URL] {
        guard let intent = Self.intent(for: plan),
              let outputFormat = intent.outputFormat else {
            throw ConversionError.unsupportedInput
        }

        var completedOutputs: [URL] = []
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

                try await Task.detached(priority: .userInitiated) {
                    try Self.convert(
                        inputURL: input.url,
                        outputURL: outputURL,
                        intent: intent
                    )
                }.value

                completedOutputs.append(outputURL)
                try checkCancellation(for: plan.id)
                progress(Double(index + 1) / Double(plan.inputs.count))
            }

            return completedOutputs
        } catch {
            for outputURL in completedOutputs {
                try? FileManager.default.removeItem(at: outputURL)
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
              intent.targetBytes == nil,
              intent.maxPixelDimension.map({ $0 > 0 }) ?? true,
              let outputFormat = intent.outputFormat,
              outputFormat != .webP,
              plan.inputs.allSatisfy({ outputFormat.canConvert($0.format) }) else {
            return nil
        }
        return intent
    }

    private nonisolated static func convert(
        inputURL: URL,
        outputURL: URL,
        intent: ImageIntent
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
        let maximumDimension = min(intent.maxPixelDimension ?? sourceMaximum, sourceMaximum)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            sourceIndex,
            thumbnailOptions as CFDictionary
        ) else {
            throw ConversionError.invalidMedia
        }

        let temporaryURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".fileisland-\(UUID().uuidString).\(outputFormat.filenameExtension)")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let destinationType = destinationType(for: outputFormat) else {
            throw ConversionError.unsupportedOutput
        }
        guard let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL,
                destinationType.identifier as CFString,
                1,
                nil
              ) else {
            throw ConversionError.permissionDenied
        }

        var destinationProperties: [CFString: Any] = intent.stripMetadata
            ? [:]
            : sourceProperties
        destinationProperties[kCGImagePropertyOrientation] = 1
        if outputFormat == .jpeg {
            destinationProperties[kCGImageDestinationLossyCompressionQuality] = jpegQuality(
                for: intent.qualityPreference
            )
        }

        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed(underlying: "Image encoder could not finalize the output.")
        }

        do {
            try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        } catch let error as CocoaError where error.code == .fileWriteNoPermission {
            throw ConversionError.permissionDenied
        } catch {
            throw ConversionError.conversionFailed(underlying: "The output file could not be saved.")
        }
    }

    private nonisolated static func destinationType(for format: ImageOutputFormat) -> UTType? {
        switch format {
        case .jpeg:
            .jpeg
        case .png:
            .png
        case .webP:
            nil
        }
    }

    private nonisolated static func jpegQuality(for preference: QualityPreference) -> Double {
        switch preference {
        case .smallestFile:
            0.45
        case .balanced:
            0.82
        case .highestQuality:
            0.96
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
