import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class ConversionEngineRouterTests: XCTestCase {
    func testExecutesOnlyTheFirstCapableEngine() async throws {
        let incapable = RecordingConversionEngine(canHandle: false, outputName: "wrong.mp4")
        let capable = RecordingConversionEngine(canHandle: true, outputName: "right.mp4")
        let router = ConversionEngineRouter(engines: [incapable, capable])
        let plan = makePlan()

        let outputs = try await router.execute(plan) { _ in }

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["right.mp4"])
        let incapableCount = await incapable.executionCount
        let capableCount = await capable.executionCount
        XCTAssertEqual(incapableCount, 0)
        XCTAssertEqual(capableCount, 1)
    }

    func testThrowsWhenNoEngineCanHandlePlan() async {
        let router = ConversionEngineRouter(
            engines: [RecordingConversionEngine(canHandle: false, outputName: "unused.mp4")]
        )

        do {
            _ = try await router.execute(makePlan()) { _ in }
            XCTFail("Expected engine unavailable")
        } catch {
            XCTAssertEqual(error as? ConversionError, .engineUnavailable)
        }
    }

    func testCancelIsForwardedToEveryEngine() async {
        let first = RecordingConversionEngine(canHandle: true, outputName: "one.mp4")
        let second = RecordingConversionEngine(canHandle: true, outputName: "two.mp4")
        let router = ConversionEngineRouter(engines: [first, second])
        let jobID = UUID()

        await router.cancel(jobID: jobID)

        let firstCancellation = await first.cancelledJobID
        let secondCancellation = await second.cancelledJobID
        XCTAssertEqual(firstCancellation, jobID)
        XCTAssertEqual(secondCancellation, jobID)
    }

    func testNativeAndFallbackVideoEnginesHaveDisjointContainerOwnership() {
        let native = NativeVideoConversionEngine()
        let fallback = FFmpegConversionEngine(executableURL: nil)
        let movPlan = makeVideoPlan(extension: "mov")
        let mkvPlan = makeVideoPlan(extension: "mkv")

        XCTAssertTrue(native.canHandle(movPlan))
        XCTAssertFalse(fallback.canHandle(movPlan))
        XCTAssertFalse(native.canHandle(mkvPlan))
        XCTAssertTrue(fallback.canHandle(mkvPlan))
    }

    private func makePlan() -> ConversionPlan {
        let intent = VideoIntent(
            compatibility: .highCompatibility,
            maxResolution: .source,
            targetBytes: nil,
            qualityPreference: .balanced
        )
        return ConversionPlan(
            inputs: [],
            steps: [.video(intent)],
            outputPolicy: .sameDirectory(suffix: "")
        )
    }

    private func makeVideoPlan(extension pathExtension: String) -> ConversionPlan {
        let url = URL(fileURLWithPath: "/tmp/video.\(pathExtension)")
        return ConversionPlan(
            inputs: [
                InputFile(
                    url: url,
                    type: UTType(filenameExtension: pathExtension),
                    fileSize: 1,
                    displayName: url.lastPathComponent
                )
            ],
            steps: [
                .video(
                    VideoIntent(
                        compatibility: .highCompatibility,
                        maxResolution: .source,
                        targetBytes: nil,
                        qualityPreference: .balanced
                    )
                )
            ],
            outputPolicy: .sameDirectory(suffix: "")
        )
    }
}

private actor RecordingConversionEngine: ConversionEngine {
    nonisolated let handlesPlan: Bool
    nonisolated let outputName: String
    private(set) var executionCount = 0
    private(set) var cancelledJobID: UUID?

    init(canHandle: Bool, outputName: String) {
        handlesPlan = canHandle
        self.outputName = outputName
    }

    nonisolated func canHandle(_ plan: ConversionPlan) -> Bool { handlesPlan }

    func execute(
        _ plan: ConversionPlan,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws -> [URL] {
        executionCount += 1
        return [URL(fileURLWithPath: "/tmp/\(outputName)")]
    }

    func cancel(jobID: UUID) async {
        cancelledJobID = jobID
    }
}
