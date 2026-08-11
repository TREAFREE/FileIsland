import Foundation

struct FileIslandCLIApplication: Sendable {
    private let core: any FileIslandCoreServing
    private let output: any CLIOutputWriting
    private let parser: CLIArgumentParser

    init(
        core: any FileIslandCoreServing,
        output: any CLIOutputWriting = FileHandleCLIOutput(),
        parser: CLIArgumentParser = CLIArgumentParser()
    ) {
        self.core = core
        self.output = output
        self.parser = parser
    }

    func run(arguments: [String]) async -> CLIExitCode {
        do {
            let invocation = try parser.parse(arguments)
            switch invocation {
            case .help:
                try emit([
                    "schemaVersion": 1,
                    "kind": "help",
                    "usage": [
                        "fileisland capabilities --json",
                        "fileisland inspect <paths> [--recursive] --json",
                        "fileisland convert <paths> --output <directory> [options] --json",
                        "fileisland split <paths> --output <directory> [--recursive] [--max-bytes N] [--max-duration-seconds N] --mode fast-keyframe-copy --json"
                    ]
                ])
                return .success
            case .capabilities:
                try await emitCapabilities()
                return .success
            case let .inspect(paths, recursive):
                try await emitInspection(paths: paths, recursive: recursive)
                return .success
            case let .convert(options):
                return try await convert(options)
            case let .split(options):
                return await split(options)
            }
        } catch {
            let code = exitCode(for: error)
            emitDiagnostic(for: code)
            if code != .argumentError {
                try? emit([
                    "schemaVersion": 1,
                    "kind": "conversionEvent",
                    "state": code == .cancelled ? "cancelled" : "failed",
                    "exitCode": Int(code.rawValue)
                ])
            }
            return code
        }
    }

    private func emitCapabilities() async throws {
        let value = try await core.capabilities()
        var payload: [String: Any] = [
            "schemaVersion": value.schemaVersion,
            "kind": "capabilities",
            "image": [
                "inputFormats": value.image.inputFormats,
                "outputFormats": value.image.outputFormats
            ],
            "video": [
                "nativeInputFormats": value.video.nativeInputFormats,
                "fallbackInputFormats": value.video.fallbackInputFormats,
                "outputContainer": value.video.outputContainer,
                "resolutions": value.video.resolutions,
                "nativeSupportsTargetBytes": value.video.nativeSupportsTargetBytes,
                "fallbackSupportsTargetBytes": value.video.fallbackSupportsTargetBytes
            ],
            "audio": [
                "inputFormats": value.audio.inputFormats,
                "outputFormats": value.audio.outputFormats
            ],
            "presets": value.presets.map {
                [
                    "id": $0.id,
                    "displayName": $0.displayName,
                    "summary": $0.summary,
                    "mediaType": $0.mediaType
                ]
            }
        ]
        if let videoSplit = value.videoSplit {
            payload["videoSplit"] = [
                "constraintSources": videoSplit.constraintSources,
                "modes": videoSplit.modes,
                "inputContainers": videoSplit.inputContainers,
                "videoCodecs": videoSplit.videoCodecs,
                "audioCodecs": videoSplit.audioCodecs,
                "allowsNoAudio": videoSplit.allowsNoAudio,
                "customConstraints": [
                    "supported": videoSplit.customConstraints.supported,
                    "requiresAtLeastOne": videoSplit.customConstraints.requiresAtLeastOne,
                    "decimalMegabyteBytes": videoSplit.customConstraints.decimalMegabyteBytes,
                    "durationUnit": videoSplit.customConstraints.durationUnit,
                    "durationPrecisionMilliseconds": videoSplit.customConstraints.durationPrecisionMilliseconds
                ] as [String: Any]
            ] as [String: Any]
        }
        try emit(payload)
    }

    private func emitInspection(paths: [String], recursive: Bool) async throws {
        let inspection = try await core.inspect(
            paths: paths.map { URL(fileURLWithPath: $0) },
            recursive: recursive
        )
        try emit([
            "schemaVersion": inspection.schemaVersion,
            "kind": "inspection",
            "fileCount": inspection.files.count,
            "files": inspection.files.map {
                [
                    "displayName": $0.displayName,
                    "mediaKind": $0.mediaKind,
                    "format": $0.format,
                    "byteCount": $0.byteCount,
                    "relativePath": $0.relativePath
                ] as [String: Any]
            }
        ])
    }

    private func convert(_ options: CLIConvertOptions) async throws -> CLIExitCode {
        let request = CoreConversionRequest(
            paths: options.paths.map { URL(fileURLWithPath: $0) },
            recursive: options.recursive,
            outputDirectory: URL(fileURLWithPath: options.outputPath, isDirectory: true),
            imageIntent: options.imageIntent,
            videoIntent: options.videoIntent,
            audioIntent: options.audioIntent,
            imagePresetID: options.imagePresetID,
            videoPresetID: options.videoPresetID
        )
        try emit([
            "schemaVersion": 1,
            "kind": "conversionEvent",
            "jobID": request.id.uuidString.lowercased(),
            "state": "preparing"
        ])
        let outputDirectory = request.outputDirectory
        let result = try await core.convert(request) { progress in
            try? emit([
                "schemaVersion": 1,
                "kind": "conversionEvent",
                "jobID": progress.requestID.uuidString.lowercased(),
                "state": "running",
                "fraction": min(max(progress.fraction, 0), 1),
                "current": progress.currentFile,
                "total": progress.totalFiles,
                "displayName": progress.currentDisplayName ?? ""
            ])
        }
        try emit([
            "schemaVersion": 1,
            "kind": "conversionEvent",
            "jobID": result.requestID.uuidString.lowercased(),
            "state": "completed",
            "outputs": result.outputURLs.map { relativePath(for: $0, root: outputDirectory) },
            "skippedCount": result.skippedCount,
            "failClosedCount": result.failClosedCount
        ])
        return result.skippedCount > 0 || result.failClosedCount > 0 ? .partialSkip : .success
    }

    private func split(_ options: CLIVideoSplitOptions) async -> CLIExitCode {
        let request = CoreVideoSplitRequest(
            paths: options.paths.map { URL(fileURLWithPath: $0) },
            recursive: options.recursive,
            outputDirectory: URL(fileURLWithPath: options.outputPath, isDirectory: true),
            maxBytes: options.maxBytes,
            maxDurationMilliseconds: options.maxDurationMilliseconds,
            mode: options.mode
        )
        let outputDirectory = request.outputDirectory
        do {
            let result = try await core.split(request) { event in
                try? emitSplitEvent(event, outputDirectory: outputDirectory)
            }
            try emit([
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": result.requestID.uuidString.lowercased(),
                "state": "completed",
                "outputs": result.outputURLs.map {
                    relativePath(for: $0, root: outputDirectory)
                },
                "segmentCount": result.segmentCount,
                "totalBytes": result.totalBytes
            ])
            return .success
        } catch {
            let code = exitCode(for: error)
            emitDiagnostic(for: code)
            try? emit([
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": request.id.uuidString.lowercased(),
                "state": code == .cancelled ? "cancelled" : "failed",
                "exitCode": Int(code.rawValue)
            ])
            return code
        }
    }

    private func emitSplitEvent(
        _ event: CoreVideoSplitEvent,
        outputDirectory: URL
    ) throws {
        switch event {
        case let .plan(value):
            try emit([
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": value.requestID.uuidString.lowercased(),
                "state": "plan",
                "current": value.inputOrdinal,
                "total": value.totalInputs,
                "displayName": value.displayName,
                "segments": value.segmentRelativePaths.map(\.string)
            ])
        case let .segment(value):
            var object: [String: Any] = [
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": value.requestID.uuidString.lowercased(),
                "state": "segment",
                "fraction": min(max(value.fraction, 0), 1),
                "current": value.currentFile,
                "total": value.totalFiles,
                "displayName": value.currentDisplayName ?? ""
            ]
            if let currentSegment = value.currentSegment {
                object["currentSegment"] = currentSegment
            }
            if let totalSegments = value.totalSegments {
                object["totalSegments"] = totalSegments
            }
            try emit(object)
        case let .validation(value):
            try emit([
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": value.requestID.uuidString.lowercased(),
                "state": "validation",
                "segmentCount": value.segmentCount
            ])
        case let .publication(value):
            try emit([
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": value.requestID.uuidString.lowercased(),
                "state": "publication",
                "outputs": value.outputURLs.map {
                    relativePath(for: $0, root: outputDirectory)
                }
            ])
        case let .rollback(requestID):
            try emit([
                "schemaVersion": 1,
                "kind": "splitEvent",
                "jobID": requestID.uuidString.lowercased(),
                "state": "rollback"
            ])
        }
    }

    private func relativePath(for url: URL, root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let outputComponents = url.standardizedFileURL.pathComponents
        guard outputComponents.count > rootComponents.count,
              outputComponents.starts(with: rootComponents) else {
            return url.lastPathComponent
        }
        return outputComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private func emit(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        output.writeStandardOutput(data)
    }

    private func emitDiagnostic(for code: CLIExitCode) {
        let message = switch code {
        case .success: ""
        case .argumentError: "fileisland: invalid arguments; use --help.\n"
        case .unsupported: "fileisland: the request is not supported.\n"
        case .permissionError: "fileisland: permission was denied.\n"
        case .cancelled: "fileisland: conversion cancelled.\n"
        case .conversionFailure: "fileisland: conversion failed.\n"
        case .partialSkip: "fileisland: conversion completed with skipped inputs.\n"
        }
        if !message.isEmpty { output.writeStandardError(Data(message.utf8)) }
    }

    private func exitCode(for error: Error) -> CLIExitCode {
        if error is CLIArgumentError { return .argumentError }
        if error is CancellationError { return .cancelled }
        if let coreError = error as? FileIslandCoreError {
            return switch coreError {
            case .recursiveRequired, .missingImageConfiguration,
                 .missingVideoConfiguration, .missingAudioConfiguration,
                 .conflictingConfiguration, .invalidSplitConfiguration:
                .argumentError
            case .presetNotApplicable, .unsupportedInput, .splitRuntimeUnavailable:
                .unsupported
            }
        }
        if let splitError = error as? VideoSplitJobError {
            return switch splitError {
            case .cancelled:
                .cancelled
            case .keyframeSpacingUnreachable, .retryLimitReached, .stalePlan,
                 .engineUnavailable, .validationFailed:
                .unsupported
            case .anotherRequestIsRunning, .emptyRequest, .invalidOutputDirectory,
                 .duplicateInputIdentity, .publicationFailed:
                .conversionFailure
            }
        }
        if let probeError = error as? VideoSplitProbeError {
            return switch probeError {
            case .probeCancelled:
                .cancelled
            case .unreadableFile:
                .permissionError
            default:
                .unsupported
            }
        }
        if error is VideoSplitPlanningError {
            return .unsupported
        }
        if let scanError = error as? InputScanningError {
            return switch scanError {
            case .notLocalFile: .argumentError
            case .noFiles, .unsupportedRoot, .unsafeRelativePath: .unsupported
            }
        }
        if let inspectionError = error as? FileInspectionError {
            return switch inspectionError {
            case .noFiles, .notRegularFile:
                .unsupported
            case .notLocalFile:
                .argumentError
            case .unreadableFile:
                .permissionError
            }
        }
        if let conversionError = error as? ConversionError {
            return switch conversionError {
            case .unsupportedInput, .unsupportedOutput, .engineUnavailable,
                 .invalidMedia, .targetSizeUnreachable:
                .unsupported
            case .permissionDenied: .permissionError
            case .cancelled: .cancelled
            case .insufficientDiskSpace, .conversionFailed: .conversionFailure
            }
        }
        if let cocoaError = error as? CocoaError,
           [.fileReadNoPermission, .fileWriteNoPermission].contains(cocoaError.code) {
            return .permissionError
        }
        return .conversionFailure
    }
}
