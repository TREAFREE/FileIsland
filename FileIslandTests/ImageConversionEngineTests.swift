import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class ImageConversionEngineTests: XCTestCase {
    func testConvertsHEICToDecodableJPEGWithoutTouchingInput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("源 图片.heic")
        let outputDirectory = workspace.appendingPathComponent("Output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: false)
        try ImageFixtureFactory.writeImage(to: inputURL, type: .heic)
        let inputBytes = try Data(contentsOf: inputURL)
        let input = try makeInput(url: inputURL, type: .heic)
        let intent = ImageIntent(
            outputFormat: .jpeg,
            maxPixelDimension: nil,
            targetBytes: nil,
            qualityPreference: .balanced,
            stripMetadata: false
        )
        let plan = try ImageConversionPlanBuilder().makePlan(
            inputs: [input],
            intent: intent,
            outputDirectory: outputDirectory
        )
        let engine = ImageConversionEngine()

        XCTAssertTrue(engine.canHandle(plan))
        let outputs = try await engine.execute(plan) { _ in }

        let output = try XCTUnwrap(outputs.first)
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(output.lastPathComponent, "源 图片.jpg")
        XCTAssertTrue(try ImageFixtureFactory.imageType(at: output).conforms(to: .jpeg))
        XCTAssertEqual(try Data(contentsOf: inputURL), inputBytes)
    }

    func testConvertsPNGToJPEGAndJPEGToPNG() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let cases: [(UTType, ImageOutputFormat, UTType)] = [
            (.png, .jpeg, .jpeg),
            (.jpeg, .png, .png)
        ]
        for (index, conversion) in cases.enumerated() {
            let inputURL = workspace.appendingPathComponent("input-\(index).\(conversion.0.preferredFilenameExtension ?? "img")")
            let outputDirectory = workspace.appendingPathComponent("output-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: false)
            try ImageFixtureFactory.writeImage(to: inputURL, type: conversion.0)
            let plan = try makePlan(
                inputs: [makeInput(url: inputURL, type: conversion.0)],
                outputFormat: conversion.1,
                outputDirectory: outputDirectory
            )

            let outputs = try await ImageConversionEngine().execute(plan) { _ in }

            XCTAssertEqual(outputs.count, 1)
            XCTAssertTrue(try ImageFixtureFactory.imageType(at: outputs[0]).conforms(to: conversion.2))
        }
    }

    func testConvertsWebPTIFFAndHEICIntoDecodableJPEGOrPNG() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let cases: [(String, UTType, ImageOutputFormat, UTType)] = [
            ("webp", .webP, .jpeg, .jpeg),
            ("tiff", .tiff, .png, .png),
            ("heic", .heic, .png, .png)
        ]

        for (index, conversion) in cases.enumerated() {
            let inputURL = workspace.appendingPathComponent("input-\(index).\(conversion.0)")
            let outputDirectory = try createDirectory(named: "output-\(index)", in: workspace)
            if conversion.1 == .webP {
                try ImageFixtureFactory.writeTinyWebP(to: inputURL)
            } else {
                try ImageFixtureFactory.writeImage(to: inputURL, type: conversion.1)
            }
            let plan = try makePlan(
                inputs: [makeInput(url: inputURL, type: conversion.1)],
                outputFormat: conversion.2,
                outputDirectory: outputDirectory
            )

            let outputs = try await ImageConversionEngine().execute(plan) { _ in }

            let output = try XCTUnwrap(outputs.first)
            XCTAssertGreaterThan(try fileSize(at: output), 0)
            XCTAssertTrue(try ImageFixtureFactory.imageType(at: output).conforms(to: conversion.3))
            _ = try ImageFixtureFactory.imageProperties(at: output)
        }
    }

    func testSupportsSameFormatImageProcessingWithoutOverwritingInput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let cases: [(UTType, ImageOutputFormat)] = [(.jpeg, .jpeg), (.png, .png)]

        for (index, conversion) in cases.enumerated() {
            let inputURL = workspace.appendingPathComponent("same-\(index).\(conversion.0.preferredFilenameExtension ?? "img")")
            let outputDirectory = try createDirectory(named: "same-output-\(index)", in: workspace)
            try ImageFixtureFactory.writeImage(to: inputURL, type: conversion.0, width: 96, height: 64)
            let inputBytes = try Data(contentsOf: inputURL)
            let plan = try makePlan(
                inputs: [makeInput(url: inputURL, type: conversion.0)],
                outputFormat: conversion.1,
                outputDirectory: outputDirectory,
                maxPixelDimension: 48
            )

            let outputs = try await ImageConversionEngine().execute(plan) { _ in }
            let output = try XCTUnwrap(outputs.first)

            let properties = try ImageFixtureFactory.imageProperties(at: output)
            XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 48)
            XCTAssertEqual(try Data(contentsOf: inputURL), inputBytes)
        }
    }

    func testTransparentPNGToJPEGUsesOpaqueWhiteBackground() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("transparent.png")
        let outputDirectory = try createDirectory(named: "alpha-output", in: workspace)
        try ImageFixtureFactory.writeTransparentPNG(to: inputURL)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .png)],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory
        )

        let outputs = try await ImageConversionEngine().execute(plan) { _ in }
        let output = try XCTUnwrap(outputs.first)
        let pixel = try ImageFixtureFactory.firstRGBPixel(at: output)

        XCTAssertGreaterThan(pixel.red, 245)
        XCTAssertTrue((115...140).contains(pixel.green), "green=\(pixel.green)")
        XCTAssertTrue((115...140).contains(pixel.blue), "blue=\(pixel.blue)")
    }

    func testResizeLimitsLongestEdgeWithoutUpscaling() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("wide.png")
        let outputDirectory = workspace.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: false)
        try ImageFixtureFactory.writeImage(to: inputURL, type: .png, width: 120, height: 80)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .png)],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory,
            maxPixelDimension: 40
        )

        let outputs = try await ImageConversionEngine().execute(plan) { _ in }
        let output = try XCTUnwrap(outputs.first)
        let properties = try ImageFixtureFactory.imageProperties(at: output)
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? NSNumber).intValue
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? NSNumber).intValue

        XCTAssertEqual(max(width, height), 40)
        XCTAssertEqual(width, 40)
        XCTAssertEqual(height, 27)
    }

    func testJPEGQualityPreferenceChangesOutputSize() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("detail.png")
        try ImageFixtureFactory.writeImage(to: inputURL, type: .png, width: 640, height: 480)
        let input = try makeInput(url: inputURL, type: .png)

        let smallestURL = try await convertSingle(
            input: input,
            outputDirectory: try createDirectory(named: "smallest", in: workspace),
            quality: .smallestFile
        )
        let highestURL = try await convertSingle(
            input: input,
            outputDirectory: try createDirectory(named: "highest", in: workspace),
            quality: .highestQuality
        )

        XCTAssertLessThan(try fileSize(at: smallestURL), try fileSize(at: highestURL))
    }

    func testJPEGTargetProducesDecodableOutputWithinPerFileLimit() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("target-detail.png")
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        try ImageFixtureFactory.writeImage(to: inputURL, type: .png, width: 640, height: 480)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .png)],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory,
            targetBytes: 50_000
        )

        let outputs = try await ImageConversionEngine().execute(plan) { _ in }

        let output = try XCTUnwrap(outputs.first)
        XCTAssertGreaterThan(try fileSize(at: output), 0)
        XCTAssertLessThanOrEqual(try fileSize(at: output), 50_000)
        XCTAssertTrue(try ImageFixtureFactory.imageType(at: output).conforms(to: .jpeg))
    }

    func testPNGTargetFallsBackToSmallerDimensions() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("target-detail.jpg")
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        try ImageFixtureFactory.writeImage(to: inputURL, type: .jpeg, width: 640, height: 480)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .jpeg)],
            outputFormat: .png,
            outputDirectory: outputDirectory,
            targetBytes: 30_000
        )

        let outputs = try await ImageConversionEngine().execute(plan) { _ in }
        let output = try XCTUnwrap(outputs.first)
        let properties = try ImageFixtureFactory.imageProperties(at: output)
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? NSNumber).intValue

        XCTAssertLessThan(width, 640)
        XCTAssertGreaterThan(try fileSize(at: output), 0)
        XCTAssertLessThanOrEqual(try fileSize(at: output), 30_000)
        XCTAssertTrue(try ImageFixtureFactory.imageType(at: output).conforms(to: .png))
    }

    func testImpossibleTargetReturnsStructuredErrorAndLeavesNoOutput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("impossible.png")
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        try ImageFixtureFactory.writeImage(to: inputURL, type: .png, width: 640, height: 480)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .png)],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory,
            targetBytes: 10
        )

        do {
            _ = try await ImageConversionEngine().execute(plan) { _ in }
            XCTFail("Expected an unreachable target error")
        } catch {
            XCTAssertEqual(error as? ConversionError, .targetSizeUnreachable)
        }
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: nil
            ),
            []
        )
    }

    func testBatchAppliesTargetToEveryOutput() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstDirectory = try createDirectory(named: "first-target", in: workspace)
        let secondDirectory = try createDirectory(named: "second-target", in: workspace)
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        let firstURL = firstDirectory.appendingPathComponent("detail.png")
        let secondURL = secondDirectory.appendingPathComponent("detail.png")
        try ImageFixtureFactory.writeImage(to: firstURL, type: .png, width: 640, height: 480)
        try ImageFixtureFactory.writeImage(to: secondURL, type: .png, width: 800, height: 600)
        let plan = try makePlan(
            inputs: [
                makeInput(url: firstURL, type: .png),
                makeInput(url: secondURL, type: .png)
            ],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory,
            targetBytes: 40_000
        )

        let outputs = try await ImageConversionEngine().execute(plan) { _ in }

        XCTAssertEqual(outputs.count, 2)
        for output in outputs {
            XCTAssertGreaterThan(try fileSize(at: output), 0)
            XCTAssertLessThanOrEqual(try fileSize(at: output), 40_000)
            XCTAssertTrue(try ImageFixtureFactory.imageType(at: output).conforms(to: .jpeg))
        }
    }

    func testStripMetadataRemovesEmbeddedSourceMarker() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let inputURL = workspace.appendingPathComponent("metadata.png")
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        try ImageFixtureFactory.writeImage(to: inputURL, type: .png, includeMetadata: true)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .png)],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory,
            stripMetadata: true
        )

        let outputs = try await ImageConversionEngine().execute(plan) { _ in }
        let output = try XCTUnwrap(outputs.first)
        let properties = try ImageFixtureFactory.imageProperties(at: output)

        XCTAssertFalse(String(describing: properties).contains(ImageFixtureFactory.metadataMarker))
    }

    func testBatchUsesStableUniqueNamesAndReportsMonotonicProgress() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstDirectory = try createDirectory(named: "first", in: workspace)
        let secondDirectory = try createDirectory(named: "second", in: workspace)
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        let firstURL = firstDirectory.appendingPathComponent("photo.png")
        let secondURL = secondDirectory.appendingPathComponent("photo.png")
        try ImageFixtureFactory.writeImage(to: firstURL, type: .png)
        try ImageFixtureFactory.writeImage(to: secondURL, type: .png)
        let inputs = try [firstURL, secondURL].map { try makeInput(url: $0, type: .png) }
        let plan = try makePlan(
            inputs: inputs,
            outputFormat: .jpeg,
            outputDirectory: outputDirectory
        )
        let progress = LockedProgressRecorder()

        let outputs = try await ImageConversionEngine().execute(plan, progress: progress.record)

        XCTAssertEqual(outputs.map(\.lastPathComponent), ["photo.jpg", "photo-2.jpg"])
        XCTAssertEqual(progress.values, [0, 0.5, 1])
    }

    func testCancelledPlanCreatesNoOutputs() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        let inputURL = workspace.appendingPathComponent("cancel.png")
        try ImageFixtureFactory.writeImage(to: inputURL, type: .png)
        let plan = try makePlan(
            inputs: [makeInput(url: inputURL, type: .png)],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory
        )
        let engine = ImageConversionEngine()
        await engine.cancel(jobID: plan.id)

        do {
            _ = try await engine.execute(plan) { _ in }
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? ConversionError, .cancelled)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil), [])
    }

    func testBatchFailureRollsBackCompletedOutputs() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outputDirectory = try createDirectory(named: "output", in: workspace)
        let validURL = workspace.appendingPathComponent("valid.png")
        let invalidURL = workspace.appendingPathComponent("invalid.png")
        try ImageFixtureFactory.writeImage(to: validURL, type: .png)
        try Data("not an image".utf8).write(to: invalidURL)
        let plan = try makePlan(
            inputs: [
                makeInput(url: validURL, type: .png),
                makeInput(url: invalidURL, type: .png)
            ],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory
        )

        do {
            _ = try await ImageConversionEngine().execute(plan) { _ in }
            XCTFail("Expected invalid media")
        } catch {
            XCTAssertEqual(error as? ConversionError, .invalidMedia)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil), [])
    }

    private func makePlan(
        inputs: [InputFile],
        outputFormat: ImageOutputFormat,
        outputDirectory: URL,
        maxPixelDimension: Int? = nil,
        targetBytes: Int64? = nil,
        quality: QualityPreference = .balanced,
        stripMetadata: Bool = false
    ) throws -> ConversionPlan {
        try ImageConversionPlanBuilder().makePlan(
            inputs: inputs,
            intent: ImageIntent(
                outputFormat: outputFormat,
                maxPixelDimension: maxPixelDimension,
                targetBytes: targetBytes,
                qualityPreference: quality,
                stripMetadata: stripMetadata
            ),
            outputDirectory: outputDirectory
        )
    }

    private func convertSingle(
        input: InputFile,
        outputDirectory: URL,
        quality: QualityPreference
    ) async throws -> URL {
        let plan = try makePlan(
            inputs: [input],
            outputFormat: .jpeg,
            outputDirectory: outputDirectory,
            quality: quality
        )
        let outputs = try await ImageConversionEngine().execute(plan) { _ in }
        return try XCTUnwrap(outputs.first)
    }

    private func makeInput(url: URL, type: UTType) throws -> InputFile {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return InputFile(
            url: url,
            type: type,
            fileSize: Int64(values.fileSize ?? 0),
            displayName: url.lastPathComponent
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func createDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func fileSize(at url: URL) throws -> Int64 {
        Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
}

private final class LockedProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []

    var values: [Double] {
        lock.withLock { storage }
    }

    func record(_ value: Double) {
        lock.withLock { storage.append(value) }
    }
}
