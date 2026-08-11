import Foundation

enum VideoSplitRefinementError: Error, Equatable, Sendable {
    case unsupportedPlan
    case invalidFailedSegment
    case noEarlierKeyframe
    case tooManySegments
    case arithmeticOverflow
    case unsafeOutputPath
    case unchangedPlan
}

/// Pure retry planner for fast-copy output that exceeded an original limit.
/// Each call reduces the global cut interval to the previous independently
/// decodable keyframe available inside the failed segment.
struct VideoSplitPlanRefiner: Sendable {
    private static let minimumNonTailDurationMilliseconds: Int64 = 1_000
    private static let maximumSegmentCount = 999

    func refine(
        _ plan: VideoSplitPlan,
        source: VideoSplitSourceFacts,
        failedSegmentIndex: Int
    ) throws -> VideoSplitPlan {
        guard plan.intent.mode == .fastKeyframeCopy,
              plan.segments.allSatisfy({ !$0.requiresReencoding }) else {
            throw VideoSplitRefinementError.unsupportedPlan
        }
        do {
            try VideoSplitDomainValidator.validate(plan: plan)
            _ = try source.validated(for: .fastKeyframeCopy, matching: plan.input)
        } catch {
            throw VideoSplitRefinementError.unsupportedPlan
        }
        guard let failed = plan.segments.first(where: { $0.index == failedSegmentIndex }) else {
            throw VideoSplitRefinementError.invalidFailedSegment
        }

        let candidate = source.keyframeMilliseconds.last {
            $0 > failed.startMilliseconds + Self.minimumNonTailDurationMilliseconds - 1
                && $0 < failed.endMilliseconds
        }
        guard let candidate else {
            throw VideoSplitRefinementError.noEarlierKeyframe
        }
        let reducedInterval = candidate - failed.startMilliseconds
        guard reducedInterval >= Self.minimumNonTailDurationMilliseconds,
              reducedInterval < failed.endMilliseconds - failed.startMilliseconds else {
            throw VideoSplitRefinementError.noEarlierKeyframe
        }

        let ranges = try fastRanges(
            durationMilliseconds: source.durationMilliseconds,
            maximumSegmentDurationMilliseconds: reducedInterval,
            keyframes: source.keyframeMilliseconds
        )
        guard ranges.count <= Self.maximumSegmentCount else {
            throw VideoSplitRefinementError.tooManySegments
        }
        guard ranges.map(\.end) != plan.segments.map(\.endMilliseconds) else {
            throw VideoSplitRefinementError.unchangedPlan
        }

        guard let firstOutput = plan.segments.first?.outputRelativePath,
              let filenameExtension = firstOutput.components.last?
                .split(separator: ".").last.map(String.init),
              !filenameExtension.isEmpty else {
            throw VideoSplitRefinementError.unsafeOutputPath
        }
        let outputDirectory = firstOutput.components.dropLast().joined(separator: "/")
        let baseName = plan.input.url.deletingPathExtension().lastPathComponent
        guard !outputDirectory.isEmpty, !baseName.isEmpty else {
            throw VideoSplitRefinementError.unsafeOutputPath
        }
        let digits = max(2, String(ranges.count).count)
        let segments = try ranges.enumerated().map { offset, range in
            let ordinal = offset + 1
            let ordinalLabel = String(format: "%0*d", digits, ordinal)
            let totalLabel = String(format: "%0*d", digits, ranges.count)
            let path: SafeRelativePath
            do {
                path = try SafeRelativePath(
                    "\(outputDirectory)/\(baseName)-part-\(ordinalLabel)-of-\(totalLabel).\(filenameExtension)"
                )
            } catch {
                throw VideoSplitRefinementError.unsafeOutputPath
            }
            return VideoSegmentPlan(
                index: ordinal,
                startMilliseconds: range.start,
                endMilliseconds: range.end,
                outputRelativePath: path,
                estimatedBytes: try estimatedBytes(
                    durationMilliseconds: range.end - range.start,
                    bitrateBitsPerSecond: source.averageBitrateBitsPerSecond
                ),
                requiresReencoding: false
            )
        }
        let refined = VideoSplitPlan(
            id: plan.id,
            input: plan.input,
            sourceFileIdentity: plan.sourceFileIdentity,
            intent: plan.intent,
            ruleSnapshot: plan.ruleSnapshot,
            segments: segments
        )
        do {
            try VideoSplitDomainValidator.validate(plan: refined)
        } catch {
            throw VideoSplitRefinementError.unsupportedPlan
        }
        return refined
    }

    private func fastRanges(
        durationMilliseconds: Int64,
        maximumSegmentDurationMilliseconds: Int64,
        keyframes: [Int64]
    ) throws -> [(start: Int64, end: Int64)] {
        var ranges: [(start: Int64, end: Int64)] = []
        var start: Int64 = 0
        var keyframeIndex = 1
        while start < durationMilliseconds {
            let (candidateEnd, overflow) = start.addingReportingOverflow(
                maximumSegmentDurationMilliseconds
            )
            guard !overflow else { throw VideoSplitRefinementError.arithmeticOverflow }
            let target = min(candidateEnd, durationMilliseconds)
            if target == durationMilliseconds {
                ranges.append((start, durationMilliseconds))
                break
            }

            var boundary: Int64?
            while keyframeIndex < keyframes.count, keyframes[keyframeIndex] <= target {
                if keyframes[keyframeIndex] > start {
                    boundary = keyframes[keyframeIndex]
                }
                keyframeIndex += 1
            }
            guard let boundary,
                  boundary - start >= Self.minimumNonTailDurationMilliseconds else {
                throw VideoSplitRefinementError.noEarlierKeyframe
            }
            ranges.append((start, boundary))
            guard ranges.count <= Self.maximumSegmentCount else {
                throw VideoSplitRefinementError.tooManySegments
            }
            start = boundary
        }
        return ranges
    }

    private func estimatedBytes(
        durationMilliseconds: Int64,
        bitrateBitsPerSecond: Int64
    ) throws -> Int64 {
        let estimate = Decimal(durationMilliseconds)
            * Decimal(bitrateBitsPerSecond)
            / Decimal(8_000)
        guard estimate >= 0, estimate <= Decimal(Int64.max) else {
            throw VideoSplitRefinementError.arithmeticOverflow
        }
        return NSDecimalNumber(decimal: estimate).int64Value
    }
}
