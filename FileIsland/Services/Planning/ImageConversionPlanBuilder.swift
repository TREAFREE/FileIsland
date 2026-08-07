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
        guard intent.targetBytes == nil else {
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

        return ConversionPlan(
            inputs: inputs,
            steps: [.image(intent)],
            outputPolicy: .chosenDirectory(outputDirectory, suffix: "")
        )
    }
}
