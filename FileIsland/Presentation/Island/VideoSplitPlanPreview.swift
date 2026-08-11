import Foundation

enum VideoSplitCustomLimitError: Error, Equatable, Sendable {
    case missingLimits
    case invalidMaximumMegabytes
    case invalidMaximumDuration
}

struct VideoSplitLimitFieldAppearance: Equatable, Sendable {
    let borderOpacity: Double
    let borderWidth: Double

    static func resolve(increaseContrast: Bool) -> Self {
        Self(
            borderOpacity: increaseContrast ? 0.58 : 0.24,
            borderWidth: increaseContrast ? 1.5 : 1
        )
    }
}

protocol VideoSplitLimitUnit: CaseIterable, Hashable, Sendable {
    var shortLabel: String { get }
    var canonicalMultiplier: Decimal { get }
}

enum VideoSplitSizeUnit: String, VideoSplitLimitUnit {
    case megabytes
    case gigabytes

    var shortLabel: String {
        switch self {
        case .megabytes: "MB"
        case .gigabytes: "GB"
        }
    }

    var canonicalMultiplier: Decimal {
        switch self {
        case .megabytes: 1
        case .gigabytes: 1_000
        }
    }
}

enum VideoSplitDurationUnit: String, VideoSplitLimitUnit {
    case seconds
    case minutes
    case hours

    var shortLabel: String {
        switch self {
        case .seconds: "sec"
        case .minutes: "min"
        case .hours: "hr"
        }
    }

    var canonicalMultiplier: Decimal {
        switch self {
        case .seconds: 1
        case .minutes: 60
        case .hours: 3_600
        }
    }
}

enum VideoSplitLimitDisplayFormatter {
    static func canonicalText<Unit: VideoSplitLimitUnit>(
        _ displayText: String,
        unit: Unit
    ) -> String {
        guard let displayValue = decimal(from: displayText) else {
            return displayText
        }
        return text(for: displayValue * unit.canonicalMultiplier)
    }

    static func convertedText<Unit: VideoSplitLimitUnit>(
        _ text: String,
        from sourceUnit: Unit,
        to destinationUnit: Unit
    ) -> String {
        guard sourceUnit != destinationUnit,
            let sourceValue = decimal(from: text)
        else {
            return text
        }
        let canonicalValue = sourceValue * sourceUnit.canonicalMultiplier
        return self.text(for: canonicalValue / destinationUnit.canonicalMultiplier)
    }

    static func displayText<Unit: VideoSplitLimitUnit>(
        forCanonicalValue canonicalValue: Decimal,
        unit: Unit
    ) -> String {
        text(for: canonicalValue / unit.canonicalMultiplier)
    }

    static func decimal(from rawValue: String) -> Decimal? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.filter({ $0 == "." }).count <= 1,
            normalized.allSatisfy({ $0.isNumber || $0 == "." }),
            normalized.contains(where: \.isNumber),
            let value = Decimal(
                string: normalized,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            !value.isNaN,
            value > 0
        else {
            return nil
        }
        return value
    }

    private static func text(for value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

enum VideoSplitLimitSliderScale {
    private static let minimumMegabytes = 10.0
    private static let maximumMegabytes = 10_000.0
    private static let minimumSeconds = 10.0
    private static let maximumSeconds = 10_800.0

    static func canonicalMegabytes(at position: Double) -> Decimal {
        let rawValue = exponentialValue(
            at: position,
            minimum: minimumMegabytes,
            maximum: maximumMegabytes
        )
        let step: Double =
            if rawValue < 100 {
                5
            } else if rawValue < 1_000 {
                25
            } else if rawValue < 5_000 {
                100
            } else {
                250
            }
        return Decimal(Int64((rawValue / step).rounded() * step))
    }

    static func canonicalSeconds(at position: Double) -> Decimal {
        let rawValue = exponentialValue(
            at: position,
            minimum: minimumSeconds,
            maximum: maximumSeconds
        )
        let step: Double =
            if rawValue < 60 {
                5
            } else if rawValue < 300 {
                15
            } else if rawValue < 1_800 {
                30
            } else {
                60
            }
        return Decimal(Int64((rawValue / step).rounded() * step))
    }

    static func sizePosition(forCanonicalMegabytes value: Decimal) -> Double {
        position(
            for: NSDecimalNumber(decimal: value).doubleValue,
            minimum: minimumMegabytes,
            maximum: maximumMegabytes
        )
    }

    static func durationPosition(forCanonicalSeconds value: Decimal) -> Double {
        position(
            for: NSDecimalNumber(decimal: value).doubleValue,
            minimum: minimumSeconds,
            maximum: maximumSeconds
        )
    }

    private static func exponentialValue(
        at position: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        let clamped = position.isFinite ? min(max(position, 0), 1) : 0
        let logarithm = log(minimum) + (log(maximum) - log(minimum)) * clamped
        return exp(logarithm)
    }

    private static func position(
        for value: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        let clamped = min(max(value, minimum), maximum)
        return (log(clamped) - log(minimum)) / (log(maximum) - log(minimum))
    }
}

struct VideoSplitCustomLimits: Equatable, Sendable {
    let maxBytes: Int64?
    let maxDurationMilliseconds: Int64?

    static func parse(
        maximumMegabytes: String,
        maximumDurationSeconds: String
    ) throws -> Self {
        let megabytes = try parseOptionalPositiveDecimal(
            maximumMegabytes,
            error: .invalidMaximumMegabytes
        )
        let durationSeconds = try parseOptionalPositiveDecimal(
            maximumDurationSeconds,
            error: .invalidMaximumDuration
        )
        guard megabytes != nil || durationSeconds != nil else {
            throw VideoSplitCustomLimitError.missingLimits
        }

        let maxBytes: Int64?
        if let megabytes {
            do {
                maxBytes = try VideoSplitDomainValidator.bytes(
                    forDecimalMegabytes: megabytes
                )
            } catch {
                throw VideoSplitCustomLimitError.invalidMaximumMegabytes
            }
        } else {
            maxBytes = nil
        }

        let maxDurationMilliseconds: Int64?
        if let durationSeconds {
            var milliseconds = durationSeconds * 1_000
            var rounded = Decimal()
            NSDecimalRound(&rounded, &milliseconds, 0, .down)
            guard rounded >= 1, rounded <= Decimal(Int64.max) else {
                throw VideoSplitCustomLimitError.invalidMaximumDuration
            }
            maxDurationMilliseconds = NSDecimalNumber(decimal: rounded).int64Value
        } else {
            maxDurationMilliseconds = nil
        }

        return Self(
            maxBytes: maxBytes,
            maxDurationMilliseconds: maxDurationMilliseconds
        )
    }

    var constraints: VideoSegmentConstraints {
        VideoSegmentConstraints(
            maxBytes: maxBytes,
            maxDurationMilliseconds: maxDurationMilliseconds,
            safetyRatio: 0.95,
            requiredContainer: nil,
            requiredVideoCodec: nil,
            requiredAudioCodec: nil
        )
    }

    private static func parseOptionalPositiveDecimal(
        _ rawValue: String,
        error: VideoSplitCustomLimitError
    ) throws -> Decimal? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard normalized.filter({ $0 == "." }).count <= 1,
            normalized.allSatisfy({ $0.isNumber || $0 == "." }),
            normalized.contains(where: \.isNumber),
            let value = Decimal(
                string: normalized,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            !value.isNaN,
            value > 0
        else {
            throw error
        }
        return value
    }
}

struct VideoSplitPlanPreview: Equatable, Sendable {
    let segmentCount: Int
    let maxBytes: Int64?
    let maxDurationMilliseconds: Int64?
    let mode: VideoSplitMode
    let requiresReencoding: Bool
    let noSplitNeeded: Bool
    let isExecutionAvailable: Bool

    init(plan: VideoSplitPlan, runtimeAvailable: Bool = false) {
        segmentCount = plan.segments.count
        maxBytes = plan.intent.constraints.maxBytes
        maxDurationMilliseconds = plan.intent.constraints.maxDurationMilliseconds
        mode = plan.intent.mode
        requiresReencoding = plan.segments.contains(where: \.requiresReencoding)
        noSplitNeeded = plan.segments.count == 1
        isExecutionAvailable =
            runtimeAvailable
            && plan.intent.source == .custom
            && plan.intent.mode == .fastKeyframeCopy
            && plan.ruleSnapshot == nil
            && !requiresReencoding
    }

    @MainActor
    func localizedModeTitle(using localization: LocalizationController) -> String {
        switch mode {
        case .fastKeyframeCopy:
            localization.string("Fast · keep original quality")
        case .preciseCompatible:
            localization.string("Precise & compatible")
        }
    }

    @MainActor
    func localizedSegmentSummary(using localization: LocalizationController) -> String {
        noSplitNeeded
            ? localization.string("No split needed")
            : localization.string("Estimated %d segments", segmentCount)
    }

    @MainActor
    func localizedDecimalMegabyteDisclosure(
        using localization: LocalizationController
    ) -> String {
        localization.string("1 MB equals 1,000,000 bytes.")
    }

    @MainActor
    func localizedQualityNotice(using localization: LocalizationController) -> String? {
        requiresReencoding
            ? localization.string("Re-encoding may change image quality.")
            : nil
    }

    @MainActor
    func localizedExecutionStatus(using localization: LocalizationController) -> String {
        localization.string(
            isExecutionAvailable ? "Ready to split" : "Split runtime unavailable"
        )
    }
}

struct VideoSplitBatchPlanPreview: Equatable, Sendable {
    let plans: [VideoSplitPlanPreview]

    init(items: [VideoSplitBatchItem], runtimeAvailable: Bool) {
        plans = items.map {
            VideoSplitPlanPreview(
                plan: $0.plan,
                runtimeAvailable: runtimeAvailable
            )
        }
    }

    var segmentCount: Int { plans.reduce(0) { $0 + $1.segmentCount } }
    var inputCount: Int { plans.count }
    var noSplitNeeded: Bool { !plans.isEmpty && plans.allSatisfy(\.noSplitNeeded) }
    var isExecutionAvailable: Bool {
        !plans.isEmpty && plans.allSatisfy(\.isExecutionAvailable)
    }
    var maxBytes: Int64? { plans.first?.maxBytes }
    var maxDurationMilliseconds: Int64? { plans.first?.maxDurationMilliseconds }

    @MainActor
    func localizedSegmentSummary(using localization: LocalizationController) -> String {
        if noSplitNeeded {
            return localization.string("No split needed")
        }
        return localization.string("Estimated %d segments", segmentCount)
    }
}
