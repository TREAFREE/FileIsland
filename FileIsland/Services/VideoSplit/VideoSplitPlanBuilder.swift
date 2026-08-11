import Foundation

enum VideoSplitPlanningError: Error, Equatable, Sendable {
    case unsupportedInput
    case invalidSplitConstraint
    case invalidProbe(VideoSplitProbeError)
    case invalidRuleSnapshot
    case sharingRuleExpired
    case requiredMediaIncompatible
    case tooManySegments
    case keyframeSpacingUnreachable
    case splitTargetUnreachable
    case unsafeOutputPath
    case arithmeticOverflow
    case invalidGeneratedPlan
}

struct VideoSplitPlanBuilder: Sendable {
    private static let minimumNonTailDurationMilliseconds: Int64 = 1_000
    private static let maximumSegmentCount = 999

    func makePlan(
        id: UUID = UUID(),
        input: InputFile,
        intent: VideoSplitIntent,
        source: VideoSplitSourceFacts,
        sharingRuleCatalog: SharingRuleCatalog? = nil,
        inputRelativePath: SafeRelativePath? = nil,
        planningDate: Date = Date()
    ) throws -> VideoSplitPlan {
        guard input.kind == .video, input.fileSize > 0 else {
            throw VideoSplitPlanningError.unsupportedInput
        }

        do {
            try VideoSplitDomainValidator.validate(constraints: intent.constraints)
        } catch {
            throw VideoSplitPlanningError.invalidSplitConstraint
        }

        let validatedSource: VideoSplitSourceFacts
        do {
            validatedSource = try source.validated(for: intent.mode, matching: input)
        } catch let error as VideoSplitProbeError {
            throw VideoSplitPlanningError.invalidProbe(error)
        }

        let ruleSnapshot = try resolveConstraintSource(
            intent.source,
            constraints: intent.constraints,
            catalog: sharingRuleCatalog,
            planningDate: planningDate
        )
        let outputExtension = try validateRequiredMedia(
            intent: intent,
            source: validatedSource
        )

        let ranges: [(start: Int64, end: Int64)]
        if sourceAlreadySatisfies(
            input: input,
            durationMilliseconds: validatedSource.durationMilliseconds,
            constraints: intent.constraints
        ) {
            ranges = [(0, validatedSource.durationMilliseconds)]
        } else {
            let planningBitrate = try conservativePlanningBitrate(
                inputBytes: input.fileSize,
                durationMilliseconds: validatedSource.durationMilliseconds,
                probedAverageBitrate: validatedSource.averageBitrateBitsPerSecond
            )
            let maximumDuration = try effectiveSegmentDuration(
                constraints: intent.constraints,
                averageBitrateBitsPerSecond: planningBitrate
            )
            guard maximumDuration >= Self.minimumNonTailDurationMilliseconds else {
                throw VideoSplitPlanningError.splitTargetUnreachable
            }
            switch intent.mode {
            case .fastKeyframeCopy:
                ranges = try fastRanges(
                    durationMilliseconds: validatedSource.durationMilliseconds,
                    maximumSegmentDurationMilliseconds: maximumDuration,
                    keyframes: validatedSource.keyframeMilliseconds
                )
            case .preciseCompatible:
                ranges = try preciseRanges(
                    durationMilliseconds: validatedSource.durationMilliseconds,
                    maximumSegmentDurationMilliseconds: maximumDuration
                )
            }
        }

        guard !ranges.isEmpty, ranges.count <= Self.maximumSegmentCount else {
            throw VideoSplitPlanningError.tooManySegments
        }

        let baseName = input.url.deletingPathExtension().lastPathComponent
        guard isSafePathComponent(baseName), isSafeMediaToken(outputExtension) else {
            throw VideoSplitPlanningError.unsafeOutputPath
        }
        if let inputRelativePath,
           inputRelativePath.components.last != input.url.lastPathComponent {
            throw VideoSplitPlanningError.unsafeOutputPath
        }
        let digitCount = max(2, String(ranges.count).count)
        let outputDirectoryName = try outputDirectoryPath(
            baseName: baseName,
            inputRelativePath: inputRelativePath
        )
        let effectiveMaximumBytes = try intent.constraints.maxBytes.map {
            try scaledInteger($0, by: intent.constraints.safetyRatio)
        }

        let segments = try ranges.enumerated().map { offset, range in
            let index = offset + 1
            let indexLabel = String(format: "%0*d", digitCount, index)
            let totalLabel = String(format: "%0*d", digitCount, ranges.count)
            let relativePath: SafeRelativePath
            do {
                relativePath = try SafeRelativePath(
                    "\(outputDirectoryName)/\(baseName)-part-\(indexLabel)-of-\(totalLabel).\(outputExtension)"
                )
            } catch {
                throw VideoSplitPlanningError.unsafeOutputPath
            }

            let sourceEstimate = try estimatedBytes(
                durationMilliseconds: range.end - range.start,
                averageBitrateBitsPerSecond: validatedSource.averageBitrateBitsPerSecond
            )
            let estimate: Int64
            if intent.mode == .preciseCompatible, let effectiveMaximumBytes {
                estimate = min(sourceEstimate, effectiveMaximumBytes)
            } else if ranges.count == 1 {
                estimate = input.fileSize
            } else {
                estimate = sourceEstimate
            }

            return VideoSegmentPlan(
                index: index,
                startMilliseconds: range.start,
                endMilliseconds: range.end,
                outputRelativePath: relativePath,
                estimatedBytes: estimate,
                requiresReencoding: intent.mode == .preciseCompatible
            )
        }

        let plan = VideoSplitPlan(
            id: id,
            input: input,
            sourceFileIdentity: validatedSource.fileIdentity,
            intent: intent,
            ruleSnapshot: ruleSnapshot,
            segments: segments
        )
        do {
            try VideoSplitDomainValidator.validate(plan: plan)
        } catch {
            throw VideoSplitPlanningError.invalidGeneratedPlan
        }
        return plan
    }

    private func resolveConstraintSource(
        _ source: VideoSplitConstraintSource,
        constraints: VideoSegmentConstraints,
        catalog: SharingRuleCatalog?,
        planningDate: Date
    ) throws -> SharingRuleSnapshot? {
        switch source {
        case .custom:
            return nil
        case let .verifiedRule(id, revision):
            guard let catalog else {
                throw VideoSplitPlanningError.invalidRuleSnapshot
            }
            let validatedCatalog: SharingRuleCatalog
            do {
                validatedCatalog = try JSONSharingRuleCatalogDecoder(
                    now: { planningDate }
                ).validate(catalog)
            } catch SharingRuleCatalogError.expiredRule(_) {
                throw VideoSplitPlanningError.sharingRuleExpired
            } catch {
                throw VideoSplitPlanningError.invalidRuleSnapshot
            }
            guard let currentRule = validatedCatalog.rules.first(where: { $0.id == id }),
                  currentRule.revision == revision,
                  currentRule.maxBytes == constraints.maxBytes,
                  currentRule.maxDurationMilliseconds == constraints.maxDurationMilliseconds,
                  currentRule.safetyRatio == constraints.safetyRatio,
                  contains(
                      constraints.requiredContainer,
                      in: currentRule.acceptedContainers.map(\.rawValue)
                  ),
                  contains(
                      constraints.requiredVideoCodec,
                      in: currentRule.acceptedVideoCodecs.map(\.rawValue)
                  ),
                  contains(
                      constraints.requiredAudioCodec,
                      in: currentRule.acceptedAudioCodecs.map(\.rawValue)
                  ) else {
                throw VideoSplitPlanningError.invalidRuleSnapshot
            }
            return currentRule.snapshot
        }
    }

    private func contains(_ required: String?, in allowed: [String]) -> Bool {
        guard let required else { return false }
        return allowed.contains(required)
    }

    private func validateRequiredMedia(
        intent: VideoSplitIntent,
        source: VideoSplitSourceFacts
    ) throws -> String {
        let constraints = intent.constraints
        switch intent.mode {
        case .fastKeyframeCopy:
            guard constraints.requiredContainer.map({ $0 == source.container }) ?? true,
                  constraints.requiredVideoCodec.map({ $0 == source.videoCodec }) ?? true,
                  source.audioCodec.map({ sourceAudioCodec in
                      constraints.requiredAudioCodec.map({ $0 == sourceAudioCodec }) ?? true
                  }) ?? true else {
                throw VideoSplitPlanningError.requiredMediaIncompatible
            }
            let outputContainer = constraints.requiredContainer ?? source.container
            guard let filenameExtension = VideoSplitSourceFacts.filenameExtension(
                forContainer: outputContainer
            ) else {
                throw VideoSplitPlanningError.requiredMediaIncompatible
            }
            return filenameExtension
        case .preciseCompatible:
            guard constraints.requiredContainer.map({ $0 == "mp4" }) ?? true,
                  constraints.requiredVideoCodec.map({ $0 == "h264" }) ?? true,
                  constraints.requiredAudioCodec.map({ $0 == "aac" }) ?? true else {
                throw VideoSplitPlanningError.requiredMediaIncompatible
            }
            return "mp4"
        }
    }

    private func sourceAlreadySatisfies(
        input: InputFile,
        durationMilliseconds: Int64,
        constraints: VideoSegmentConstraints
    ) -> Bool {
        let sizeFits = constraints.maxBytes.map({ input.fileSize <= $0 }) ?? true
        let durationFits = constraints.maxDurationMilliseconds
            .map({ durationMilliseconds <= $0 }) ?? true
        return sizeFits && durationFits
    }

    private func effectiveSegmentDuration(
        constraints: VideoSegmentConstraints,
        averageBitrateBitsPerSecond: Int64
    ) throws -> Int64 {
        var candidates: [Int64] = []
        if let maximumDuration = constraints.maxDurationMilliseconds {
            candidates.append(try scaledInteger(maximumDuration, by: constraints.safetyRatio))
        }
        if let maximumBytes = constraints.maxBytes {
            let effectiveBytes = try scaledInteger(maximumBytes, by: constraints.safetyRatio)
            let milliseconds = floor(
                Double(effectiveBytes) * 8_000 / Double(averageBitrateBitsPerSecond)
            )
            guard milliseconds.isFinite,
                  milliseconds > 0,
                  let duration = Int64(exactly: milliseconds) else {
                throw VideoSplitPlanningError.splitTargetUnreachable
            }
            candidates.append(duration)
        }
        guard let result = candidates.min(), result > 0 else {
            throw VideoSplitPlanningError.invalidSplitConstraint
        }
        return result
    }

    private func conservativePlanningBitrate(
        inputBytes: Int64,
        durationMilliseconds: Int64,
        probedAverageBitrate: Int64
    ) throws -> Int64 {
        let observed = ceil(
            Double(inputBytes) * 8_000 / Double(durationMilliseconds)
        )
        guard observed.isFinite,
              observed > 0,
              let observedBitrate = Int64(exactly: observed) else {
            throw VideoSplitPlanningError.arithmeticOverflow
        }
        return max(probedAverageBitrate, observedBitrate)
    }

    private func scaledInteger(_ value: Int64, by ratio: Double) throws -> Int64 {
        let scaled = floor(Double(value) * ratio)
        guard scaled.isFinite,
              scaled > 0,
              let result = Int64(exactly: scaled) else {
            throw VideoSplitPlanningError.arithmeticOverflow
        }
        return result
    }

    private func preciseRanges(
        durationMilliseconds: Int64,
        maximumSegmentDurationMilliseconds: Int64
    ) throws -> [(start: Int64, end: Int64)] {
        let quotient = durationMilliseconds / maximumSegmentDurationMilliseconds
        let remainder = durationMilliseconds % maximumSegmentDurationMilliseconds
        let count = quotient + (remainder == 0 ? 0 : 1)
        guard count <= Int64(Self.maximumSegmentCount) else {
            throw VideoSplitPlanningError.tooManySegments
        }

        var ranges: [(start: Int64, end: Int64)] = []
        ranges.reserveCapacity(Int(count))
        var start: Int64 = 0
        while start < durationMilliseconds {
            let end = min(start + maximumSegmentDurationMilliseconds, durationMilliseconds)
            ranges.append((start, end))
            start = end
        }
        return ranges
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
            let target = min(start + maximumSegmentDurationMilliseconds, durationMilliseconds)
            if target == durationMilliseconds {
                ranges.append((start, durationMilliseconds))
                break
            }

            var boundary: Int64?
            while keyframeIndex < keyframes.count, keyframes[keyframeIndex] <= target {
                boundary = keyframes[keyframeIndex]
                keyframeIndex += 1
            }
            guard let boundary,
                  boundary > start,
                  boundary - start >= Self.minimumNonTailDurationMilliseconds else {
                throw VideoSplitPlanningError.keyframeSpacingUnreachable
            }
            ranges.append((start, boundary))
            guard ranges.count <= Self.maximumSegmentCount else {
                throw VideoSplitPlanningError.tooManySegments
            }
            start = boundary
        }
        return ranges
    }

    private func estimatedBytes(
        durationMilliseconds: Int64,
        averageBitrateBitsPerSecond: Int64
    ) throws -> Int64 {
        let estimate = ceil(
            Double(durationMilliseconds) * Double(averageBitrateBitsPerSecond) / 8_000
        )
        guard estimate.isFinite,
              estimate >= 0,
              let result = Int64(exactly: estimate) else {
            throw VideoSplitPlanningError.arithmeticOverflow
        }
        return result
    }

    private func outputDirectoryPath(
        baseName: String,
        inputRelativePath: SafeRelativePath?
    ) throws -> String {
        let splitDirectory = "\(baseName) — Split"
        guard let parent = inputRelativePath?.parent else {
            return splitDirectory
        }
        do {
            return try SafeRelativePath("\(parent.string)/\(splitDirectory)").string
        } catch {
            throw VideoSplitPlanningError.unsafeOutputPath
        }
    }

    private func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
    }

    private func isSafeMediaToken(_ value: String) -> Bool {
        !value.isEmpty
            && value == value.lowercased()
            && value.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            }
    }
}
