import Foundation

struct ImageConversionPlanBuilder: Sendable {
    func makePlan(
        inputs: [InputFile],
        intent: ImageIntent,
        outputDirectory: URL
    ) throws -> ConversionPlan {
        guard !inputs.isEmpty else {
            throw ConversionError.unsupportedInput
        }
        guard intent.targetBytes.map({ $0 > 0 }) ?? true else {
            throw ConversionError.targetSizeUnreachable
        }
        guard intent.maxPixelDimension.map({ $0 > 0 }) ?? true,
              let outputFormat = intent.outputFormat,
              outputFormat != .webP else {
            throw ConversionError.unsupportedOutput
        }

        let supportedInputs: Set<InputFileFormat> = [.heic, .jpeg, .png]
        guard inputs.allSatisfy({ supportedInputs.contains($0.format) }) else {
            throw ConversionError.unsupportedInput
        }
        guard inputs.allSatisfy({ outputFormat.canConvert($0.format) }) else {
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
            steps: [.image(intent)],
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
