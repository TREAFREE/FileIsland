import Foundation

struct ConversionEngineRouter: ConversionEngine {
    private let engines: [any ConversionEngine]

    init(engines: [any ConversionEngine]) {
        self.engines = engines
    }

    func canHandle(_ plan: ConversionPlan) -> Bool {
        engines.contains { $0.canHandle(plan) }
    }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        guard let engine = engines.first(where: { $0.canHandle(plan) }) else {
            throw ConversionError.engineUnavailable
        }
        return try await engine.execute(plan, progress: progress)
    }

    func cancel(jobID: UUID) async {
        for engine in engines {
            await engine.cancel(jobID: jobID)
        }
    }
}
