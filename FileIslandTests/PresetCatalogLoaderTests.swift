import Foundation
import XCTest
@testable import FileIsland

final class PresetCatalogLoaderTests: XCTestCase {
    func testBundledCatalogContainsFourVersionedPresets() async throws {
        let presets = try await BundledPresetCatalogLoader(bundle: .main).loadPresets()

        XCTAssertEqual(
            presets.map(\.id),
            [
                "windows-compatible-video",
                "web-friendly-video",
                "image-for-web",
                "under-100mb-video"
            ]
        )
        XCTAssertEqual(presets.map(\.version), [1, 1, 1, 1])

        let image = try XCTUnwrap(presets.first { $0.id == "image-for-web" })
        XCTAssertEqual(image.mediaType, .image)
        XCTAssertEqual(image.output.imageFormat, .jpeg)
        XCTAssertEqual(image.constraints.maxPixelDimension, 2_048)
        XCTAssertEqual(image.options.quality, .balanced)
        XCTAssertEqual(image.options.stripMetadata, true)

        let target = try XCTUnwrap(presets.first { $0.id == "under-100mb-video" })
        XCTAssertEqual(target.mediaType, .video)
        XCTAssertEqual(target.output.container, .mp4)
        XCTAssertEqual(target.output.videoCodec, .h264)
        XCTAssertEqual(target.output.audioCodec, .aac)
        XCTAssertEqual(target.output.compatibility, .highCompatibility)
        XCTAssertEqual(target.constraints.maxResolution, .source)
        XCTAssertEqual(target.constraints.maxBytes, 100_000_000)
        XCTAssertEqual(target.options.quality, .balanced)
    }

    func testRejectsUnsupportedSchemaDuplicateAndInvalidIdentity() throws {
        let decoder = JSONPresetCatalogDecoder()

        XCTAssertThrowsError(try decoder.decode(catalog(schemaVersion: 2, presets: [validImagePreset()]))) {
            XCTAssertEqual($0 as? PresetCatalogError, .unsupportedSchemaVersion(2))
        }
        XCTAssertThrowsError(try decoder.decode(catalog(presets: [validImagePreset(), validImagePreset()]))) {
            XCTAssertEqual($0 as? PresetCatalogError, .duplicateID("image-for-web"))
        }
        XCTAssertThrowsError(try decoder.decode(catalog(presets: [validImagePreset(id: " ")]))) {
            XCTAssertEqual($0 as? PresetCatalogError, .invalidIdentity(" "))
        }
        XCTAssertThrowsError(try decoder.decode(catalog(presets: [validImagePreset(version: 0)]))) {
            XCTAssertEqual($0 as? PresetCatalogError, .invalidVersion("image-for-web"))
        }
    }

    func testRejectsInvalidConstraintsAndCrossMediaConfiguration() throws {
        let decoder = JSONPresetCatalogDecoder()
        let invalidSize = validImagePreset().replacingOccurrences(
            of: "\"maxPixelDimension\": 2048",
            with: "\"maxPixelDimension\": 0"
        )
        let imageWithVideoFields = validImagePreset().replacingOccurrences(
            of: "\"imageFormat\": \"jpeg\"",
            with: "\"imageFormat\": \"jpeg\", \"container\": \"mp4\", \"videoCodec\": \"h264\", \"audioCodec\": \"aac\""
        )

        XCTAssertThrowsError(try decoder.decode(catalog(presets: [invalidSize]))) {
            XCTAssertEqual($0 as? PresetCatalogError, .invalidConstraints("image-for-web"))
        }
        XCTAssertThrowsError(try decoder.decode(catalog(presets: [imageWithVideoFields]))) {
            XCTAssertEqual($0 as? PresetCatalogError, .invalidMediaConfiguration("image-for-web"))
        }
    }

    func testUnknownEnumFailsDecoding() {
        let invalid = validImagePreset().replacingOccurrences(
            of: "\"mediaType\": \"image\"",
            with: "\"mediaType\": \"document\""
        )

        XCTAssertThrowsError(try JSONPresetCatalogDecoder().decode(catalog(presets: [invalid]))) {
            XCTAssertTrue($0 is DecodingError)
        }
    }

    private func catalog(schemaVersion: Int = 1, presets: [String]) -> Data {
        Data("""
        {
          "schemaVersion": \(schemaVersion),
          "presets": [\(presets.joined(separator: ","))]
        }
        """.utf8)
    }

    private func validImagePreset(
        id: String = "image-for-web",
        version: Int = 1
    ) -> String {
        """
        {
          "id": "\(id)",
          "version": \(version),
          "displayName": "Image for Web",
          "summary": "Web image",
          "mediaType": "image",
          "output": { "imageFormat": "jpeg" },
          "constraints": { "maxPixelDimension": 2048 },
          "options": { "quality": "balanced", "stripMetadata": true }
        }
        """
    }
}
