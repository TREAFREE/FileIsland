import UniformTypeIdentifiers
import XCTest
@testable import FileIsland

final class FileTypeClassifierTests: XCTestCase {
    func testRecognizesRequiredFormatsFromTypeConformance() throws {
        let webP = try XCTUnwrap(UTType(filenameExtension: "webp"))
        let webM = try XCTUnwrap(UTType(filenameExtension: "webm"))
        let matroska = try XCTUnwrap(UTType(filenameExtension: "mkv"))
        let cases: [(UTType, InputFileFormat, MediaKind)] = [
            (.heic, .heic, .image),
            (.heif, .heif, .image),
            (.jpeg, .jpeg, .image),
            (.png, .png, .image),
            (.tiff, .tiff, .image),
            (webP, .webP, .image),
            (.quickTimeMovie, .mov, .video),
            (.mpeg4Movie, .mp4, .video),
            (matroska, .mkv, .video),
            (webM, .webM, .video)
        ]

        for (type, expectedFormat, expectedKind) in cases {
            let result = FileTypeClassifier.classify(
                type: type,
                filenameExtension: ""
            )

            XCTAssertEqual(result.format, expectedFormat)
            XCTAssertEqual(result.kind, expectedKind)
        }
    }

    func testRecognizesRequiredFormatsFromNormalizedExtensionFallback() {
        let cases: [(String, InputFileFormat, MediaKind)] = [
            ("HEIC", .heic, .image),
            ("heif", .heif, .image),
            ("jpg", .jpeg, .image),
            ("JPEG", .jpeg, .image),
            ("png", .png, .image),
            ("WEBP", .webP, .image),
            ("tif", .tiff, .image),
            ("TIFF", .tiff, .image),
            ("mov", .mov, .video),
            ("MP4", .mp4, .video),
            ("m4v", .m4v, .video),
            ("mkv", .mkv, .video),
            ("WEBM", .webM, .video)
        ]

        for (extensionName, expectedFormat, expectedKind) in cases {
            let result = FileTypeClassifier.classify(
                type: nil,
                filenameExtension: extensionName
            )

            XCTAssertEqual(result.format, expectedFormat)
            XCTAssertEqual(result.kind, expectedKind)
        }
    }

    func testTypeConformanceTakesPriorityOverConflictingExtension() {
        let result = FileTypeClassifier.classify(
            type: .jpeg,
            filenameExtension: "png"
        )

        XCTAssertEqual(result.format, .jpeg)
        XCTAssertEqual(result.kind, .image)
    }

    func testUnknownTypeUsesBroadMediaKindOrOther() {
        XCTAssertEqual(
            FileTypeClassifier.classify(type: .mp3, filenameExtension: "").kind,
            .audio
        )
        XCTAssertEqual(
            FileTypeClassifier.classify(type: nil, filenameExtension: "bin"),
            FileClassification(format: .other, kind: .other)
        )
    }
}
