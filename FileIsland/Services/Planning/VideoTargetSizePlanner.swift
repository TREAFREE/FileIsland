import CoreGraphics
import Foundation

enum VideoExportTier: Int, CaseIterable, Equatable, Sendable {
    case p480
    case p540
    case p720
    case p1080
    case p2160

    static let descending: [VideoExportTier] = [.p2160, .p1080, .p720, .p540, .p480]
}

struct VideoTargetSizePlan: Equatable, Sendable {
    let targetBytes: Int64
    let fileLengthLimit: Int64
    let totalBitRate: Int
    let videoBitRate: Int
    let audioBitRate: Int
    let exportTiers: [VideoExportTier]
}

struct VideoTargetSizePlanner: Sendable {
    private let safetyRatio = 0.95
    private let aacBitRate = 128_000
    private let minimumVideoBitRate = 200_000

    func makePlan(
        targetBytes: Int64,
        duration: Double,
        hasAudio: Bool,
        sourceDisplaySize: CGSize,
        requestedResolution: VideoResolution
    ) throws -> VideoTargetSizePlan {
        guard targetBytes > 0,
              duration.isFinite,
              duration > 0,
              sourceDisplaySize.width > 0,
              sourceDisplaySize.height > 0 else {
            throw ConversionError.targetSizeUnreachable
        }

        let fileLengthLimit = Int64((Double(targetBytes) * safetyRatio).rounded(.down))
        let totalBitRate = Int((Double(fileLengthLimit) * 8 / duration).rounded(.down))
        let audioBitRate = hasAudio ? aacBitRate : 0
        let videoBitRate = totalBitRate - audioBitRate
        guard fileLengthLimit > 0, videoBitRate >= minimumVideoBitRate else {
            throw ConversionError.targetSizeUnreachable
        }

        let sourceTier = tier(forLongestEdge: max(sourceDisplaySize.width, sourceDisplaySize.height))
        let requestedTier: VideoExportTier
        switch requestedResolution {
        case .source:
            requestedTier = sourceTier
        case .p1080:
            requestedTier = minimum(sourceTier, .p1080)
        case .p720:
            requestedTier = minimum(sourceTier, .p720)
        }
        let startTier = minimum(requestedTier, tier(forVideoBitRate: videoBitRate))
        let exportTiers = VideoExportTier.descending.filter { $0.rawValue <= startTier.rawValue }

        return VideoTargetSizePlan(
            targetBytes: targetBytes,
            fileLengthLimit: fileLengthLimit,
            totalBitRate: totalBitRate,
            videoBitRate: videoBitRate,
            audioBitRate: audioBitRate,
            exportTiers: exportTiers
        )
    }

    private func tier(forLongestEdge longestEdge: CGFloat) -> VideoExportTier {
        switch longestEdge {
        case ...640: .p480
        case ...960: .p540
        case ...1280: .p720
        case ...1920: .p1080
        default: .p2160
        }
    }

    private func tier(forVideoBitRate bitRate: Int) -> VideoExportTier {
        switch bitRate {
        case 8_000_000...: .p2160
        case 3_000_000...: .p1080
        case 1_200_000...: .p720
        case 600_000...: .p540
        default: .p480
        }
    }

    private func minimum(_ lhs: VideoExportTier, _ rhs: VideoExportTier) -> VideoExportTier {
        lhs.rawValue <= rhs.rawValue ? lhs : rhs
    }
}
