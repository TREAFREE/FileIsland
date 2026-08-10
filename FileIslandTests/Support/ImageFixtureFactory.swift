import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest

enum ImageFixtureFactory {
    static let metadataMarker = "FileIsland fixture metadata"
    private static let tinyWebPBase64 =
        "UklGRh4AAABXRUJQVlA4TBEAAAAvAAAAAAfQ//73v/+BiOh/AAA="

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

    static func writeTinyWebP(to url: URL) throws {
        let data = try XCTUnwrap(Data(base64Encoded: tinyWebPBase64))
        try data.write(to: url, options: .atomic)
        XCTAssertTrue(try imageType(at: url).conforms(to: .webP))
    }

    static func writeTransparentPNG(
        to url: URL,
        width: Int = 32,
        height: Int = 32
    ) throws {
        let image = try makeHalfTransparentRedImage(width: width, height: height)
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    static func firstRGBPixel(at url: URL) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }

    private static func makeImage(
        width: Int,
        height: Int,
        alpha: UInt8 = 255
    ) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = ((y * width) + x) * 4
                pixels[offset] = UInt8(truncatingIfNeeded: (x * 37) ^ (y * 13))
                pixels[offset + 1] = UInt8(truncatingIfNeeded: (x * 11) + (y * 29))
                pixels[offset + 2] = UInt8(truncatingIfNeeded: (x * y) + (x * 7))
                pixels[offset + 3] = alpha
            }
        }

        let data = Data(pixels) as CFData
        let provider = try XCTUnwrap(CGDataProvider(data: data))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(
            rawValue: alpha == 255
                ? CGImageAlphaInfo.noneSkipLast.rawValue
                : CGImageAlphaInfo.premultipliedLast.rawValue
        )
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

    private static func makeHalfTransparentRedImage(
        width: Int,
        height: Int
    ) throws -> CGImage {
        let pixel: [UInt8] = [128, 0, 0, 128]
        let pixels = Data(Array(repeating: pixel, count: width * height).flatMap { $0 })
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}
