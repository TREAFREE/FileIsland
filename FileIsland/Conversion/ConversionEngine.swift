import Foundation

protocol ConversionEngine: Sendable {
    func canHandle(_ plan: ConversionPlan) -> Bool

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> EngineExecutionResult

    func cancel(jobID: UUID) async
}
