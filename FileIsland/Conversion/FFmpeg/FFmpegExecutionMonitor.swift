import Foundation

final class FFmpegExecutionMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var progressParser = FFmpegProgressParser()
    private var diagnosticParser: FFmpegDiagnosticParser
    private var lastItemProgress = 0.0
    private let batchIndex: Int
    private let batchCount: Int
    private let progress: @Sendable (Double) -> Void

    init(
        sensitivePaths: [String],
        batchIndex: Int,
        batchCount: Int,
        progress: @Sendable @escaping (Double) -> Void
    ) {
        diagnosticParser = FFmpegDiagnosticParser(sensitivePaths: sensitivePaths)
        self.batchIndex = batchIndex
        self.batchCount = batchCount
        self.progress = progress
    }

    func consume(_ event: FFmpegProcessEvent) {
        let emittedProgress: [Double] = lock.withLock {
            switch event {
            case let .standardError(data):
                diagnosticParser.consume(data)
                return []
            case let .standardOutput(data):
                let duration = diagnosticParser.metadata.duration
                return progressParser.consume(data).compactMap { record in
                    let itemProgress: Double
                    if record.isFinished {
                        itemProgress = 1
                    } else if let duration,
                              let outTime = record.outTimeMicroseconds,
                              duration > 0 {
                        itemProgress = min(max(Double(outTime) / 1_000_000 / duration, 0), 0.99)
                    } else {
                        return nil
                    }
                    lastItemProgress = max(lastItemProgress, itemProgress)
                    return (Double(batchIndex) + lastItemProgress) / Double(batchCount)
                }
            }
        }
        emittedProgress.forEach(progress)
    }

    var metadata: FFmpegSourceMetadata {
        lock.withLock { diagnosticParser.metadata }
    }

    var diagnostic: String {
        lock.withLock { diagnosticParser.diagnostic }
    }
}
