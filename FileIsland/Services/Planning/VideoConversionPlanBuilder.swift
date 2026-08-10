import Foundation

struct VideoConversionPlanBuilder: Sendable {
    func makePlan(
        inputs: [InputFile],
        intent: VideoIntent,
        outputDirectory: URL
    ) throws -> ConversionPlan {
        guard !inputs.isEmpty else {
            throw ConversionError.unsupportedInput
        }
        guard let backend = MediaConversionMatrix.videoBackend(
            for: inputs.map(\.format)
        ) else {
            throw ConversionError.unsupportedInput
        }
        guard intent.targetBytes.map({ $0 > 0 }) ?? true else {
            throw ConversionError.targetSizeUnreachable
        }
        guard backend != .ffmpegFallback || intent.targetBytes == nil else {
            throw ConversionError.unsupportedOutput
        }
        guard intent.compatibility == .highCompatibility,
              intent.maxResolution != nil else {
            throw ConversionError.unsupportedOutput
        }

        let estimatedOutput: EstimatedOutput?
        if let targetBytes = intent.targetBytes {
            let (totalBytes, overflow) = targetBytes.multipliedReportingOverflow(
                by: Int64(inputs.count)
            )
            guard !overflow else {
                throw ConversionError.targetSizeUnreachable
            }
            estimatedOutput = EstimatedOutput(
                totalBytes: totalBytes,
                summary: "Up to \(Self.targetLabel(targetBytes)) per file"
            )
        } else {
            estimatedOutput = nil
        }

        return ConversionPlan(
            inputs: inputs,
            steps: [.video(intent)],
            outputPolicy: .chosenDirectory(outputDirectory, suffix: ""),
            estimatedOutput: estimatedOutput
        )
    }

    private static func targetLabel(_ bytes: Int64) -> String {
        if bytes.isMultiple(of: 1_000_000) {
            return "\(bytes / 1_000_000) MB"
        }
        if bytes.isMultiple(of: 1_000) {
            return "\(bytes / 1_000) KB"
        }
        return "\(bytes) bytes"
    }
}
