import Foundation

enum FFprobeParsingError: Error, Equatable, Sendable {
    case malformedOutput
    case unsupportedMedia
    case arithmeticOverflow
    case lineTooLong
    case tooManyRecords
}

struct FFprobeMetadata: Equatable, Sendable {
    let durationMilliseconds: Int64
    let timelineOriginSeconds: Decimal
    let displayWidth: Int
    let displayHeight: Int
    let rotationDegrees: Int
    let averageBitrateBitsPerSecond: Int64
    let container: String
    let videoCodec: String
    let audioCodec: String?
    let videoStartMilliseconds: Int64
    let audioStartMilliseconds: Int64?
    let audioDurationMilliseconds: Int64?
    let userMetadataKeys: Set<String>
    let frameDurationMilliseconds: Double
}

struct FFprobeMetadataParser: Sendable {
    func parse(
        _ data: Data,
        inputURL: URL,
        fileByteCount: Int64
    ) throws -> FFprobeMetadata {
        let root: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FFprobeParsingError.malformedOutput
            }
            root = decoded
        } catch let error as FFprobeParsingError {
            throw error
        } catch {
            throw FFprobeParsingError.malformedOutput
        }

        guard let format = root["format"] as? [String: Any],
              let streams = root["streams"] as? [[String: Any]],
              let video = streams.first(where: { string($0["codec_type"]) == "video" }),
              let formatName = string(format["format_name"]),
              let container = normalizedContainer(
                  formatName: formatName,
                  filenameExtension: inputURL.pathExtension
              ),
              let videoCodec = normalizedToken(video["codec_name"]),
              let width = integer(video["width"]), width > 0,
              let height = integer(video["height"]), height > 0 else {
            throw FFprobeParsingError.unsupportedMedia
        }

        // Video is the reference stream for split boundaries. Container
        // duration often includes AAC priming/padding, so prefer the video
        // timeline and use the container only when the track omits duration.
        let durationText = string(video["duration"]) ?? string(format["duration"])
        guard let durationText,
              let durationSeconds = decimal(durationText),
              durationSeconds > 0 else {
            throw FFprobeParsingError.unsupportedMedia
        }
        let durationMilliseconds = try wholeMilliseconds(durationSeconds)

        let frameRateText = string(video["avg_frame_rate"])
            ?? string(video["r_frame_rate"])
        guard let frameRateText,
              let frameRate = rational(frameRateText),
              frameRate > 0 else {
            throw FFprobeParsingError.unsupportedMedia
        }
        let frameDurationMilliseconds = 1_000 / frameRate
        guard frameDurationMilliseconds.isFinite, frameDurationMilliseconds > 0 else {
            throw FFprobeParsingError.unsupportedMedia
        }

        let rotationDegrees = try normalizedRotationDegrees(video)
        let swapsDimensions = rotationDegrees == 90 || rotationDegrees == 270

        let audio = streams.first(where: { string($0["codec_type"]) == "audio" })
        let audioCodec = audio.flatMap { normalizedToken($0["codec_name"]) }

        let bitrate: Int64
        if let bitrateText = string(format["bit_rate"]),
           let parsedBitrate = Int64(bitrateText),
           parsedBitrate > 0 {
            bitrate = parsedBitrate
        } else {
            bitrate = try fallbackBitrate(
                fileByteCount: fileByteCount,
                durationMilliseconds: durationMilliseconds
            )
        }

        let timelineOrigin = (string(video["start_time"])
            ?? string(format["start_time"]))
            .flatMap(decimal) ?? .zero
        let videoStartMilliseconds = try signedWholeMilliseconds(timelineOrigin)
        let audioStartMilliseconds = try audio
            .flatMap { string($0["start_time"]) }
            .flatMap(decimal)
            .map(signedWholeMilliseconds)
        let audioDurationMilliseconds = try audio
            .flatMap { string($0["duration"]) }
            .flatMap(decimal)
            .map(wholeMilliseconds)

        return FFprobeMetadata(
            durationMilliseconds: durationMilliseconds,
            timelineOriginSeconds: timelineOrigin,
            displayWidth: swapsDimensions ? height : width,
            displayHeight: swapsDimensions ? width : height,
            rotationDegrees: rotationDegrees,
            averageBitrateBitsPerSecond: bitrate,
            container: container,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            videoStartMilliseconds: videoStartMilliseconds,
            audioStartMilliseconds: audioStartMilliseconds,
            audioDurationMilliseconds: audioDurationMilliseconds,
            userMetadataKeys: userMetadataKeys(format: format, streams: streams),
            frameDurationMilliseconds: frameDurationMilliseconds
        )
    }

    private func wholeMilliseconds(_ seconds: Decimal) throws -> Int64 {
        var scaled = seconds * Decimal(1_000)
        guard scaled.isFinite else { throw FFprobeParsingError.arithmeticOverflow }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded >= 1, rounded <= Decimal(Int64.max) else {
            throw FFprobeParsingError.arithmeticOverflow
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func signedWholeMilliseconds(_ seconds: Decimal) throws -> Int64 {
        var scaled = seconds * Decimal(1_000)
        guard scaled.isFinite else { throw FFprobeParsingError.arithmeticOverflow }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded >= Decimal(Int64.min), rounded <= Decimal(Int64.max) else {
            throw FFprobeParsingError.arithmeticOverflow
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func userMetadataKeys(
        format: [String: Any],
        streams: [[String: Any]]
    ) -> Set<String> {
        let dictionaries = [format] + streams
        return Set(dictionaries.flatMap { dictionary -> [String] in
            guard let tags = dictionary["tags"] as? [String: Any] else { return [] }
            return tags.compactMap { key, value in
                let normalized = key.lowercased()
                guard Self.userMetadataKeyAllowlist.contains(normalized),
                      let text = string(value),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                return normalized
            }
        })
    }

    private func fallbackBitrate(
        fileByteCount: Int64,
        durationMilliseconds: Int64
    ) throws -> Int64 {
        guard fileByteCount > 0, durationMilliseconds > 0 else {
            throw FFprobeParsingError.unsupportedMedia
        }
        let calculated = Decimal(fileByteCount) * Decimal(8_000)
            / Decimal(durationMilliseconds)
        guard calculated.isFinite,
              calculated >= 1,
              calculated <= Decimal(Int64.max) else {
            throw FFprobeParsingError.arithmeticOverflow
        }
        var rounded = Decimal()
        var mutable = calculated
        NSDecimalRound(&rounded, &mutable, 0, .down)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func rational(_ value: String) -> Double? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let numerator = Double(parts[0]), numerator.isFinite,
              let denominator = Double(parts[1]), denominator.isFinite,
              denominator != 0 else { return nil }
        let result = numerator / denominator
        return result.isFinite ? result : nil
    }

    private func normalizedRotationDegrees(_ video: [String: Any]) throws -> Int {
        let rawRotation: Double
        if let sideData = video["side_data_list"] as? [[String: Any]],
           let rotationEntry = sideData.first(where: { $0["rotation"] != nil }) {
            guard let value = number(rotationEntry["rotation"]) else {
                throw FFprobeParsingError.unsupportedMedia
            }
            rawRotation = value
        } else if let tags = video["tags"] as? [String: Any],
                  tags["rotate"] != nil {
            guard let value = number(tags["rotate"]) else {
                throw FFprobeParsingError.unsupportedMedia
            }
            rawRotation = value
        } else {
            rawRotation = 0
        }

        var wrapped = rawRotation.truncatingRemainder(dividingBy: 360)
        if wrapped < 0 { wrapped += 360 }
        let nearestQuarterTurns = (wrapped / 90).rounded()
        let nearestDegrees = nearestQuarterTurns * 90
        guard abs(wrapped - nearestDegrees) <= 0.5 else {
            throw FFprobeParsingError.unsupportedMedia
        }
        return Int(nearestDegrees).quotientAndRemainder(dividingBy: 360).remainder
    }

    private func normalizedContainer(
        formatName: String,
        filenameExtension: String
    ) -> String? {
        let names = Set(formatName.lowercased().split(separator: ",").map(String.init))
        let extensionName = filenameExtension.lowercased()

        switch extensionName {
        case "mp4" where names.contains("mp4") || names.contains("mov"):
            return "mp4"
        case "mov" where names.contains("mov"):
            return "mov"
        case "m4v" where names.contains("mov") || names.contains("mp4"):
            return "m4v"
        case "mkv" where names.contains("matroska"):
            return "matroska"
        case "webm" where names.contains("webm"):
            return "webm"
        case "avi" where names.contains("avi"):
            return "avi"
        case "ts", "mts", "m2ts":
            return names.contains("mpegts") ? "mpegts" : nil
        case "mpeg", "mpg":
            return names.contains("mpeg") || names.contains("mpegvideo") ? "mpeg" : nil
        case "flv" where names.contains("flv"):
            return "flv"
        case "3gp" where names.contains("3gp") || names.contains("mov"):
            return "3gp"
        case "wmv" where names.contains("asf"):
            return "wmv"
        default:
            return nil
        }
    }

    private func normalizedToken(_ value: Any?) -> String? {
        guard let value = string(value)?.lowercased(),
              !value.isEmpty,
              value.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
              }) else { return nil }
        return value
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        guard let text = string(value) else { return nil }
        return Int(text)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        guard let text = string(value), let result = Double(text), result.isFinite else {
            return nil
        }
        return result
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let value as String: value
        case let value as NSNumber: value.stringValue
        default: nil
        }
    }

    private func decimal(_ value: String) -> Decimal? {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static let userMetadataKeyAllowlist: Set<String> = [
        "album",
        "artist",
        "comment",
        "copyright",
        "creation_time",
        "description",
        "location",
        "make",
        "model",
        "software",
        "title"
    ]
}
