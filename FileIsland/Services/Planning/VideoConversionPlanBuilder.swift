import Foundation

struct VideoConversionPlanBuilder: Sendable {
    func makePlan(
        inputs: [InputFile],
        intent: VideoIntent,
        outputDirectory: URL
    ) throws -> ConversionPlan {
        guard !inputs.isEmpty,
              inputs.allSatisfy({ $0.format == .mov || $0.format == .mp4 }) else {
            throw ConversionError.unsupportedInput
        }
        guard intent.targetBytes == nil else {
            throw ConversionError.targetSizeUnreachable
        }
        guard intent.compatibility == .highCompatibility,
              intent.maxResolution != nil else {
            throw ConversionError.unsupportedOutput
        }

        return ConversionPlan(
            inputs: inputs,
            steps: [.video(intent)],
            outputPolicy: .chosenDirectory(outputDirectory, suffix: "")
        )
    }
}
