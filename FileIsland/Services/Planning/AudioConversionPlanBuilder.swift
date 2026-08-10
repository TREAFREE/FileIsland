import Foundation

struct AudioConversionPlanBuilder: Sendable {
    func makePlan(
        inputs: [InputFile],
        intent: AudioIntent,
        outputDirectory: URL
    ) throws -> ConversionPlan {
        guard !inputs.isEmpty,
              inputs.allSatisfy({
                  MediaConversionMatrix.supportsAudioConversion(
                      from: $0.format,
                      to: intent.outputFormat
                  )
              }) else {
            throw ConversionError.unsupportedInput
        }

        return ConversionPlan(
            inputs: inputs,
            steps: [.audio(intent)],
            outputPolicy: .chosenDirectory(outputDirectory, suffix: "")
        )
    }
}
