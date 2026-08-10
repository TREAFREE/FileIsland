import Foundation

struct ConversionPlan: Identifiable, Equatable, Sendable {
    let id: UUID
    let inputs: [InputFile]
    let steps: [ConversionStep]
    let outputPolicy: OutputPolicy
    let estimatedOutput: EstimatedOutput?

    init(
        id: UUID = UUID(),
        inputs: [InputFile],
        steps: [ConversionStep],
        outputPolicy: OutputPolicy,
        estimatedOutput: EstimatedOutput? = nil
    ) {
        self.id = id
        self.inputs = inputs
        self.steps = steps
        self.outputPolicy = outputPolicy
        self.estimatedOutput = estimatedOutput
    }
}

enum ConversionStep: Equatable, Sendable {
    case image(ImageIntent)
    case video(VideoIntent)
    case audio(AudioIntent)
}

enum OutputPolicy: Equatable, Sendable {
    case sameDirectory(suffix: String)
    case chosenDirectory(URL, suffix: String)
}

struct EstimatedOutput: Equatable, Sendable {
    let totalBytes: Int64?
    let summary: String
}
