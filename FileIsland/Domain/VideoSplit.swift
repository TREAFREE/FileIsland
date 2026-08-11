import Foundation

enum VideoSplitMode: String, Codable, Equatable, Sendable {
    case fastKeyframeCopy
    case preciseCompatible
}

enum VideoSplitConstraintSource: Equatable, Codable, Sendable {
    case custom
    case verifiedRule(id: String, revision: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case id
        case revision
    }

    private enum Kind: String, Codable {
        case custom
        case verifiedRule
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .custom:
            self = .custom
        case .verifiedRule:
            let id = try container.decode(String.self, forKey: .id)
            let revision = try container.decode(Int.self, forKey: .revision)
            guard !id.isEmpty, revision > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id,
                    in: container,
                    debugDescription: "A verified rule requires a non-empty ID and positive revision."
                )
            }
            self = .verifiedRule(id: id, revision: revision)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .custom:
            try container.encode(Kind.custom, forKey: .kind)
        case let .verifiedRule(id, revision):
            try container.encode(Kind.verifiedRule, forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(revision, forKey: .revision)
        }
    }
}

struct VideoSegmentConstraints: Equatable, Codable, Sendable {
    let maxBytes: Int64?
    let maxDurationMilliseconds: Int64?
    let safetyRatio: Double
    let requiredContainer: String?
    let requiredVideoCodec: String?
    let requiredAudioCodec: String?
}

struct VideoSplitIntent: Equatable, Codable, Sendable {
    let source: VideoSplitConstraintSource
    let mode: VideoSplitMode
    let constraints: VideoSegmentConstraints
    let stripMetadata: Bool
}

struct VideoSplitFileIdentity: Equatable, Codable, Sendable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
}

struct VideoSegmentPlan: Equatable, Codable, Sendable {
    let index: Int
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let outputRelativePath: SafeRelativePath
    let estimatedBytes: Int64
    let requiresReencoding: Bool
}

struct VideoSplitPlan: Equatable, Codable, Sendable {
    let id: UUID
    let input: InputFile
    let sourceFileIdentity: VideoSplitFileIdentity
    let intent: VideoSplitIntent
    let ruleSnapshot: SharingRuleSnapshot?
    let segments: [VideoSegmentPlan]
}

enum VideoSplitValidationError: Error, Equatable, Sendable {
    case missingLimits
    case nonPositiveMaxBytes
    case nonPositiveMaxDurationMilliseconds
    case invalidSafetyRatio
    case invalidSegmentIndex
    case invalidSegmentBounds
    case negativeEstimatedBytes
    case emptySegments
    case invalidPlanOrdering
    case invalidSourceFileIdentity
    case invalidDecimalMegabytes
    case decimalMegabytesOverflow
}

enum VideoSplitDomainValidator {
    static func validate(constraints: VideoSegmentConstraints) throws {
        guard constraints.maxBytes != nil || constraints.maxDurationMilliseconds != nil else {
            throw VideoSplitValidationError.missingLimits
        }
        guard constraints.maxBytes.map({ $0 > 0 }) ?? true else {
            throw VideoSplitValidationError.nonPositiveMaxBytes
        }
        guard constraints.maxDurationMilliseconds.map({ $0 > 0 }) ?? true else {
            throw VideoSplitValidationError.nonPositiveMaxDurationMilliseconds
        }
        guard constraints.safetyRatio.isFinite,
              (0.80...0.98).contains(constraints.safetyRatio) else {
            throw VideoSplitValidationError.invalidSafetyRatio
        }
    }

    static func validate(segment: VideoSegmentPlan) throws {
        guard segment.index > 0 else {
            throw VideoSplitValidationError.invalidSegmentIndex
        }
        guard segment.startMilliseconds >= 0,
              segment.endMilliseconds > segment.startMilliseconds else {
            throw VideoSplitValidationError.invalidSegmentBounds
        }
        guard segment.estimatedBytes >= 0 else {
            throw VideoSplitValidationError.negativeEstimatedBytes
        }
    }

    static func validate(plan: VideoSplitPlan) throws {
        try validate(constraints: plan.intent.constraints)
        guard plan.sourceFileIdentity.byteCount == plan.input.fileSize,
              plan.sourceFileIdentity.byteCount > 0,
              plan.sourceFileIdentity.modificationNanoseconds >= 0,
              plan.sourceFileIdentity.modificationNanoseconds < 1_000_000_000 else {
            throw VideoSplitValidationError.invalidSourceFileIdentity
        }
        guard !plan.segments.isEmpty else {
            throw VideoSplitValidationError.emptySegments
        }

        var expectedIndex = 1
        var expectedStart: Int64 = 0
        var outputPaths: Set<SafeRelativePath> = []
        for segment in plan.segments {
            try validate(segment: segment)
            guard segment.index == expectedIndex,
                  segment.startMilliseconds == expectedStart,
                  outputPaths.insert(segment.outputRelativePath).inserted else {
                throw VideoSplitValidationError.invalidPlanOrdering
            }
            expectedIndex += 1
            expectedStart = segment.endMilliseconds
        }
    }

    static func bytes(forDecimalMegabytes megabytes: Decimal) throws -> Int64 {
        guard !megabytes.isNaN, megabytes > 0 else {
            throw VideoSplitValidationError.invalidDecimalMegabytes
        }

        var scaled = megabytes * Decimal(1_000_000)
        guard !scaled.isNaN else {
            throw VideoSplitValidationError.decimalMegabytesOverflow
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        guard rounded >= 1 else {
            throw VideoSplitValidationError.invalidDecimalMegabytes
        }
        guard rounded <= Decimal(Int64.max) else {
            throw VideoSplitValidationError.decimalMegabytesOverflow
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
