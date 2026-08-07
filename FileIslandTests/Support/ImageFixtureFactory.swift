import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

enum ImageFixtureFactory {
    static let metadataMarker = "FileIsland fixture metadata"

    static func writeImage(
        to url: URL,
        type: UTType,
        width: Int = 96,
        height: Int = 64,
        includeMetadata: Bool = true
    ) throws {
        let image = try makeImage(width: width, height: height)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                type.identifier as CFString,
                1,
                nil
            )
        )

        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]
        if includeMetadata {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifUserComment: metadataMarker
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    static func imageProperties(at url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let index = CGImageSourceGetPrimaryImageIndex(source)
        return try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        )
    }

    static func imageType(at url: URL) throws -> UTType {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let identifier = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        return try XCTUnwrap(UTType(identifier))
    }

    private static func makeImage(width: Int, height: Int) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                pixels[offset] = UInt8(truncatingIfNeeded: (x * 37) ^ (y * 13))
                pixels[offset + 1] = UInt8(truncatingIfNeeded: (x * 11) + (y * 29))
                pixels[offset + 2] = UInt8(truncatingIfNeeded: (x * y) + (x * 7))
                pixels[offset + 3] = 255
            }
        }

        let data = Data(pixels) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        return try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        )
    }
}
