import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class ConversionPresetResolverTests: XCTestCase {
    private let resolver = ConversionPresetResolver()

    func testImageForWebMapsAllCommonImageInputsIncludingSameFormatProcessing() async throws {
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let inputs = [
            input("photo.jpg", type: .jpeg),
            input("graphic.webp", type: UTType(filenameExtension: "webp")),
            input("scan.tiff", type: .tiff)
        ]
        let capability = ConversionCapabilityResolver().resolve(inputs)

        let recommendations = resolver.recommendations(
            for: inputs,
            capability: capability,
            presets: presets
        )

        XCTAssertEqual(recommendations.map(\.preset.id), ["image-for-web"])
        XCTAssertEqual(
            recommendations.first?.intent,
            .convertImage(
                ImageIntent(
                    outputFormat: .jpeg,
                    maxPixelDimension: 2_048,
                    targetBytes: nil,
                    qualityPreference: .balanced,
                    stripMetadata: true
                )
            )
        )

    }

    func testNativeVideoMapsAllVideoPresetsFromCatalog() async throws {
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let mov = input("clip.mov", type: .quickTimeMovie)

        let recommendations = resolver.recommendations(
            for: [mov],
            capability: ConversionCapabilityResolver().resolve([mov]),
            presets: presets
        )

        XCTAssertEqual(
            recommendations.map(\.preset.id),
            ["windows-compatible-video", "web-friendly-video", "under-100mb-video"]
        )
        XCTAssertEqual(videoIntent(in: recommendations, id: "windows-compatible-video")?.maxResolution, .source)
        XCTAssertNil(videoIntent(in: recommendations, id: "windows-compatible-video")?.targetBytes)
        XCTAssertEqual(videoIntent(in: recommendations, id: "web-friendly-video")?.maxResolution, .p1080)
        XCTAssertNil(videoIntent(in: recommendations, id: "web-friendly-video")?.targetBytes)
        XCTAssertEqual(videoIntent(in: recommendations, id: "under-100mb-video")?.maxResolution, .source)
        XCTAssertEqual(videoIntent(in: recommendations, id: "under-100mb-video")?.targetBytes, 100_000_000)
    }

    func testM4VMapsAllNativeVideoPresets() async throws {
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let m4v = input("clip.m4v", type: nil)

        let recommendations = resolver.recommendations(
            for: [m4v],
            capability: ConversionCapabilityResolver().resolve([m4v]),
            presets: presets
        )

        XCTAssertEqual(
            recommendations.map(\.preset.id),
            ["windows-compatible-video", "web-friendly-video", "under-100mb-video"]
        )
    }

    func testFallbackVideoExcludesTargetSizePreset() async throws {
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()
        let webM = input("clip.webm", type: UTType(filenameExtension: "webm"))

        let recommendations = resolver.recommendations(
            for: [webM],
            capability: ConversionCapabilityResolver().resolve([webM]),
            presets: presets
        )

        XCTAssertEqual(
            recommendations.map(\.preset.id),
            ["windows-compatible-video", "web-friendly-video"]
        )
        XCTAssertTrue(recommendations.allSatisfy { recommendation in
            guard case let .convertVideo(intent) = recommendation.intent else { return false }
            return intent.targetBytes == nil
        })
    }

    private func input(_ name: String, type: UTType?) -> InputFile {
        InputFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            type: type,
            fileSize: 1,
            displayName: name
        )
    }

    private func videoIntent(
        in recommendations: [PresetRecommendation],
        id: String
    ) -> VideoIntent? {
        guard let recommendation = recommendations.first(where: { $0.preset.id == id }),
              case let .convertVideo(intent) = recommendation.intent else {
            return nil
        }
        return intent
    }
}
