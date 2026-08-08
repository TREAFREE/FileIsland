import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImageTargetSizeEncoder: Sendable {
    private static let safetyMargin = 0.97
    private static let minimumLongestEdge = 64
    private static let dimensionScale = 0.82
    private static let minimumJPEGQuality = 0.05
    private static let maximumJPEGQuality = 0.98
    private static let qualityIterations = 8

    func encode(
        source: CGImageSource,
        sourceIndex: Int,
        sourceProperties: [CFString: Any],
        sourceMaximumDimension: Int,
        intent: ImageIntent
    ) throws -> Data {
        guard let outputFormat = intent.outputFormat,
              let destinationType = destinationType(for: outputFormat) else {
            throw ConversionError.unsupportedOutput
        }

        let maximumDimension = min(
            intent.maxPixelDimension ?? sourceMaximumDimension,
            sourceMaximumDimension
        )
        guard maximumDimension > 0 else {
            throw ConversionError.invalidMedia
        }

        guard let targetBytes = intent.targetBytes else {
            let image = try thumbnail(
                source: source,
                sourceIndex: sourceIndex,
                maximumDimension: maximumDimension
            )
            return try encode(
                image: image,
                type: destinationType,
                format: outputFormat,
                quality: Self.jpegQuality(for: intent.qualityPreference),
                sourceProperties: sourceProperties,
                stripMetadata: intent.stripMetadata
            )
        }

        guard targetBytes > 0 else {
            throw ConversionError.targetSizeUnreachable
        }
        let budget = max(1, Int64(floor(Double(targetBytes) * Self.safetyMargin)))

        for dimension in dimensionCandidates(startingAt: maximumDimension) {
            try Task.checkCancellation()
            let image = try thumbnail(
                source: source,
                sourceIndex: sourceIndex,
                maximumDimension: dimension
            )
            let candidate: Data?
            switch outputFormat {
            case .jpeg:
                candidate = try bestJPEGCandidate(
                    image: image,
                    type: destinationType,
                    sourceProperties: sourceProperties,
                    stripMetadata: intent.stripMetadata,
                    budget: budget
                )
            case .png:
                let data = try encode(
                    image: image,
                    type: destinationType,
                    format: .png,
                    quality: nil,
                    sourceProperties: sourceProperties,
                    stripMetadata: intent.stripMetadata
                )
                candidate = Int64(data.count) <= budget ? data : nil
            case .webP:
                throw ConversionError.unsupportedOutput
            }

            if let candidate {
                try validate(candidate, expectedType: destinationType)
                return candidate
            }
        }

        throw ConversionError.targetSizeUnreachable
    }

    private func bestJPEGCandidate(
        image: CGImage,
        type: UTType,
        sourceProperties: [CFString: Any],
        stripMetadata: Bool,
        budget: Int64
    ) throws -> Data? {
        let highest = try encode(
            image: image,
            type: type,
            format: .jpeg,
            quality: Self.maximumJPEGQuality,
            sourceProperties: sourceProperties,
            stripMetadata: stripMetadata
        )
        if Int64(highest.count) <= budget {
            return highest
        }

        let lowest = try encode(
            image: image,
            type: type,
            format: .jpeg,
            quality: Self.minimumJPEGQuality,
            sourceProperties: sourceProperties,
            stripMetadata: stripMetadata
        )
        guard Int64(lowest.count) <= budget else { return nil }

        var best = lowest
        var lowerQuality = Self.minimumJPEGQuality
        var upperQuality = Self.maximumJPEGQuality
        for _ in 0..<Self.qualityIterations {
            try Task.checkCancellation()
            let quality = (lowerQuality + upperQuality) / 2
            let candidate = try encode(
                image: image,
                type: type,
                format: .jpeg,
                quality: quality,
                sourceProperties: sourceProperties,
                stripMetadata: stripMetadata
            )
            if Int64(candidate.count) <= budget {
                best = candidate
                lowerQuality = quality
            } else {
                upperQuality = quality
            }
        }
        return best
    }

    private func thumbnail(
        source: CGImageSource,
        sourceIndex: Int,
        maximumDimension: Int
    ) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            sourceIndex,
            options as CFDictionary
        ) else {
            throw ConversionError.invalidMedia
        }
        return image
    }

    private func encode(
        image: CGImage,
        type: UTType,
        format: ImageOutputFormat,
        quality: Double?,
        sourceProperties: [CFString: Any],
        stripMetadata: Bool
    ) throws -> Data {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.engineUnavailable
        }

        var properties: [CFString: Any] = stripMetadata ? [:] : sourceProperties
        properties[kCGImagePropertyOrientation] = 1
        if format == .jpeg, let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.conversionFailed(underlying: "Image encoder could not finalize the output.")
        }
        let data = mutableData as Data
        guard !data.isEmpty else {
            throw ConversionError.conversionFailed(underlying: "Image encoder produced an empty output.")
        }
        return data
    }

    private func dimensionCandidates(startingAt maximumDimension: Int) -> [Int] {
        let floorDimension = min(Self.minimumLongestEdge, maximumDimension)
        var result: [Int] = []
        var dimension = maximumDimension
        while true {
            result.append(dimension)
            guard dimension > floorDimension else { break }
            let scaled = max(floorDimension, Int(floor(Double(dimension) * Self.dimensionScale)))
            dimension = scaled < dimension ? scaled : dimension - 1
        }
        return result
    }

    private func validate(_ data: Data, expectedType: UTType) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String?,
              let actualType = UTType(identifier),
              actualType.conforms(to: expectedType),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw ConversionError.conversionFailed(underlying: "Encoded image validation failed.")
        }
    }

    private func destinationType(for format: ImageOutputFormat) -> UTType? {
        switch format {
        case .jpeg: .jpeg
        case .png: .png
        case .webP: nil
        }
    }

    private static func jpegQuality(for preference: QualityPreference) -> Double {
        switch preference {
        case .smallestFile: 0.45
        case .balanced: 0.82
        case .highestQuality: 0.96
        }
    }
}
