import Foundation

enum CLIArgumentError: Error, Equatable, Sendable {
    case invalidCommand
    case missingValue(String)
    case missingRequired(String)
    case unknownOption(String)
    case repeatedOption(String)
    case invalidValue(String)
    case conflictingOptions(String, String)
}

enum CLIInvocation: Equatable, Sendable {
    case help
    case capabilities
    case inspect(paths: [String], recursive: Bool)
    case convert(CLIConvertOptions)
}

struct CLIConvertOptions: Equatable, Sendable {
    let paths: [String]
    let outputPath: String
    let recursive: Bool
    let imageIntent: ImageIntent?
    let videoIntent: VideoIntent?
    let imagePresetID: String?
    let videoPresetID: String?
}

struct CLIArgumentParser: Sendable {
    func parse(_ arguments: [String]) throws -> CLIInvocation {
        guard let command = arguments.first else { return .help }
        let tail = Array(arguments.dropFirst())
        switch command {
        case "help", "--help", "-h":
            guard tail.isEmpty else { throw CLIArgumentError.invalidCommand }
            return .help
        case "capabilities":
            try requireJSONOnly(tail)
            return .capabilities
        case "inspect":
            return try parseInspect(tail)
        case "convert":
            return try parseConvert(tail)
        default:
            throw CLIArgumentError.invalidCommand
        }
    }

    private func requireJSONOnly(_ arguments: [String]) throws {
        guard arguments == ["--json"] else {
            if let first = arguments.first, first != "--json" {
                throw CLIArgumentError.unknownOption(first)
            }
            throw CLIArgumentError.missingRequired("--json")
        }
    }

    private func parseInspect(_ arguments: [String]) throws -> CLIInvocation {
        var cursor = Cursor(arguments)
        var paths: [String] = []
        var recursive = false
        var json = false
        var options: Set<String> = []
        var positionalOnly = false
        while let token = cursor.next() {
            if positionalOnly {
                paths.append(token)
            } else if token == "--" {
                positionalOnly = true
            } else if token == "--recursive" {
                try insert(token, into: &options)
                recursive = true
            } else if token == "--json" {
                try insert(token, into: &options)
                json = true
            } else if token.hasPrefix("-") {
                throw CLIArgumentError.unknownOption(token)
            } else {
                paths.append(token)
            }
        }
        guard !paths.isEmpty else { throw CLIArgumentError.missingRequired("paths") }
        guard json else { throw CLIArgumentError.missingRequired("--json") }
        return .inspect(paths: paths, recursive: recursive)
    }

    private func parseConvert(_ arguments: [String]) throws -> CLIInvocation {
        var cursor = Cursor(arguments)
        var paths: [String] = []
        var values: [String: String] = [:]
        var flags: Set<String> = []
        var positionalOnly = false
        let valueOptions: Set<String> = [
            "--output", "--image-preset", "--image-format", "--image-max-dimension",
            "--image-target-bytes", "--image-quality", "--video-preset",
            "--video-resolution", "--video-target-bytes", "--video-quality"
        ]
        let flagOptions: Set<String> = ["--recursive", "--strip-metadata", "--json"]

        while let token = cursor.next() {
            if positionalOnly {
                paths.append(token)
            } else if token == "--" {
                positionalOnly = true
            } else if valueOptions.contains(token) {
                guard values[token] == nil else { throw CLIArgumentError.repeatedOption(token) }
                guard let value = cursor.next() else { throw CLIArgumentError.missingValue(token) }
                values[token] = value
            } else if flagOptions.contains(token) {
                try insert(token, into: &flags)
            } else if token.hasPrefix("-") {
                throw CLIArgumentError.unknownOption(token)
            } else {
                paths.append(token)
            }
        }

        guard !paths.isEmpty else { throw CLIArgumentError.missingRequired("paths") }
        guard let output = values["--output"], !output.isEmpty else {
            throw CLIArgumentError.missingRequired("--output")
        }
        guard flags.contains("--json") else { throw CLIArgumentError.missingRequired("--json") }

        let imagePreset = values["--image-preset"]
        let imageManualKeys = [
            "--image-format", "--image-max-dimension", "--image-target-bytes", "--image-quality"
        ]
        let hasImageManual = imageManualKeys.contains { values[$0] != nil }
            || flags.contains("--strip-metadata")
        if imagePreset != nil, hasImageManual {
            throw CLIArgumentError.conflictingOptions("--image-preset", "image options")
        }
        let imageIntent: ImageIntent?
        if let rawFormat = values["--image-format"] {
            let format: ImageOutputFormat = switch rawFormat.lowercased() {
            case "jpeg", "jpg": .jpeg
            case "png": .png
            default: throw CLIArgumentError.invalidValue("--image-format")
            }
            imageIntent = ImageIntent(
                outputFormat: format,
                maxPixelDimension: try positiveInt(values["--image-max-dimension"], option: "--image-max-dimension"),
                targetBytes: try positiveInt64(values["--image-target-bytes"], option: "--image-target-bytes"),
                qualityPreference: try quality(values["--image-quality"]),
                stripMetadata: flags.contains("--strip-metadata")
            )
        } else {
            guard !hasImageManual else { throw CLIArgumentError.missingRequired("--image-format") }
            imageIntent = nil
        }

        let videoPreset = values["--video-preset"]
        let videoManualKeys = ["--video-resolution", "--video-target-bytes", "--video-quality"]
        let hasVideoManual = videoManualKeys.contains { values[$0] != nil }
        if videoPreset != nil, hasVideoManual {
            throw CLIArgumentError.conflictingOptions("--video-preset", "video options")
        }
        let videoIntent: VideoIntent?
        if let rawResolution = values["--video-resolution"] {
            let resolution: VideoResolution = switch rawResolution.lowercased() {
            case "source": .source
            case "1080p": .p1080
            case "720p": .p720
            default: throw CLIArgumentError.invalidValue("--video-resolution")
            }
            videoIntent = VideoIntent(
                compatibility: .highCompatibility,
                maxResolution: resolution,
                targetBytes: try positiveInt64(values["--video-target-bytes"], option: "--video-target-bytes"),
                qualityPreference: try quality(values["--video-quality"])
            )
        } else {
            guard !hasVideoManual else { throw CLIArgumentError.missingRequired("--video-resolution") }
            videoIntent = nil
        }

        return .convert(
            CLIConvertOptions(
                paths: paths,
                outputPath: output,
                recursive: flags.contains("--recursive"),
                imageIntent: imageIntent,
                videoIntent: videoIntent,
                imagePresetID: imagePreset,
                videoPresetID: videoPreset
            )
        )
    }

    private func insert(_ option: String, into options: inout Set<String>) throws {
        guard options.insert(option).inserted else { throw CLIArgumentError.repeatedOption(option) }
    }

    private func positiveInt(_ value: String?, option: String) throws -> Int? {
        guard let value else { return nil }
        guard let number = Int(value), number > 0 else { throw CLIArgumentError.invalidValue(option) }
        return number
    }

    private func positiveInt64(_ value: String?, option: String) throws -> Int64? {
        guard let value else { return nil }
        guard let number = Int64(value), number > 0 else { throw CLIArgumentError.invalidValue(option) }
        return number
    }

    private func quality(_ value: String?) throws -> QualityPreference {
        guard let value else { return .balanced }
        switch value.lowercased() {
        case "smallest": return .smallestFile
        case "balanced": return .balanced
        case "highest": return .highestQuality
        default: throw CLIArgumentError.invalidValue("quality")
        }
    }
}

private struct Cursor {
    private let arguments: [String]
    private var index = 0

    init(_ arguments: [String]) { self.arguments = arguments }

    mutating func next() -> String? {
        guard arguments.indices.contains(index) else { return nil }
        defer { index += 1 }
        return arguments[index]
    }
}
