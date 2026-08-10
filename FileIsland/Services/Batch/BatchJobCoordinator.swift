import Foundation

actor BatchJobCoordinator: BatchJobCoordinating {
    private let conversionEngine: any ConversionEngine
    private let outputURLProvider: SafeOutputURLProvider
    private let fileManager: FileManager
    private var activeRequestID: UUID?
    private var activePlanID: UUID?
    private var cancelledRequestIDs: Set<UUID> = []

    init(
        conversionEngine: any ConversionEngine,
        outputURLProvider: SafeOutputURLProvider = SafeOutputURLProvider(),
        fileManager: FileManager = .default
    ) {
        self.conversionEngine = conversionEngine
        self.outputURLProvider = outputURLProvider
        self.fileManager = fileManager
    }

    func execute(
        _ request: BatchConversionRequest,
        progress: @Sendable @escaping (BatchProgress) -> Void
    ) async throws -> BatchResult {
        guard activeRequestID == nil else { throw ConversionError.engineUnavailable }
        guard Self.isExistingDirectory(request.outputDirectory) else {
            throw ConversionError.permissionDenied
        }
        activeRequestID = request.id
        cancelledRequestIDs.remove(request.id)
        defer {
            activeRequestID = nil
            activePlanID = nil
            cancelledRequestIDs.remove(request.id)
        }

        let securityScopedURLs = Self.uniqueSecurityScopeURLs(for: request)
        let acquiredScopes = securityScopedURLs.filter {
            $0.startAccessingSecurityScopedResource()
        }
        defer { acquiredScopes.forEach { $0.stopAccessingSecurityScopedResource() } }

        guard request.processCount > 0 else {
            progress(
                BatchProgress(
                    requestID: request.id,
                    fraction: 1,
                    currentFile: 0,
                    totalFiles: 0,
                    currentDisplayName: nil
                )
            )
            return BatchResult(
                outputURLs: [],
                skippedCount: request.skippedCount,
                failClosedCount: request.failClosedCount
            )
        }

        let stagingRoot = request.outputDirectory.appendingPathComponent(
            ".fileisland-\(request.id.uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: false)
        var stagedItems: [StagedItem] = []
        var publishedURLs: [URL] = []
        var createdDirectories: [URL] = []
        let reporter = BatchProgressReporter(
            requestID: request.id,
            totalFiles: request.processCount,
            callback: progress
        )

        do {
            var completedFiles = 0
            for (groupIndex, group) in request.executableGroups.enumerated() {
                try checkCancellation(request.id)
                guard let plan = group.plan else { continue }
                let groupDirectory = stagingRoot.appendingPathComponent(
                    "group-\(groupIndex)",
                    isDirectory: true
                )
                try fileManager.createDirectory(
                    at: groupDirectory,
                    withIntermediateDirectories: false
                )
                let stagingPlan = ConversionPlan(
                    id: plan.id,
                    inputs: plan.inputs,
                    steps: plan.steps,
                    outputPolicy: .chosenDirectory(groupDirectory, suffix: ""),
                    estimatedOutput: plan.estimatedOutput
                )
                activePlanID = stagingPlan.id
                let base = completedFiles
                let count = stagingPlan.inputs.count
                let outputs = try await conversionEngine.execute(stagingPlan) { localProgress in
                    Task {
                        await reporter.reportConversion(
                            completedBeforeGroup: base,
                            groupInputs: stagingPlan.inputs,
                            localProgress: localProgress
                        )
                    }
                }
                activePlanID = nil
                try checkCancellation(request.id)
                guard outputs.count == stagingPlan.inputs.count else {
                    throw ConversionError.conversionFailed(
                        underlying: "Engine output count did not match its plan."
                    )
                }
                let batchInputsByID = Dictionary(uniqueKeysWithValues: group.inputs.map {
                    ($0.file.id, $0)
                })
                for (index, output) in outputs.enumerated() {
                    guard let input = batchInputsByID[stagingPlan.inputs[index].id] else {
                        throw ConversionError.conversionFailed(
                            underlying: "A batch output could not be matched to its input."
                        )
                    }
                    stagedItems.append(StagedItem(input: input, url: output))
                }
                completedFiles += count
                await reporter.completeConversionGroup(
                    completedFiles: completedFiles,
                    displayName: stagingPlan.inputs.last?.displayName
                )
            }

            var reserved: Set<URL> = []
            for (index, item) in stagedItems.enumerated() {
                try checkCancellation(request.id)
                let destinationDirectory = try ensureDestinationDirectory(
                    for: item.input.relativePath.parent,
                    root: request.outputDirectory,
                    createdDirectories: &createdDirectories
                )
                let destination = try outputURLProvider.outputURL(
                    for: item.input.file.url,
                    filenameExtension: item.url.pathExtension,
                    policy: .chosenDirectory(destinationDirectory, suffix: ""),
                    reserved: reserved
                )
                try fileManager.moveItem(at: item.url, to: destination)
                reserved.insert(destination.standardizedFileURL)
                publishedURLs.append(destination)
                await reporter.reportPublication(
                    publishedFiles: index + 1,
                    displayName: item.input.file.displayName
                )
            }

            try? fileManager.removeItem(at: stagingRoot)
            await reporter.finish(displayName: stagedItems.last?.input.file.displayName)
            return BatchResult(
                outputURLs: publishedURLs,
                skippedCount: request.skippedCount,
                failClosedCount: request.failClosedCount
            )
        } catch {
            Self.rollback(
                publishedURLs: publishedURLs,
                createdDirectories: createdDirectories,
                stagingRoot: stagingRoot,
                fileManager: fileManager
            )
            if cancelledRequestIDs.contains(request.id) || Task.isCancelled {
                throw ConversionError.cancelled
            }
            if let conversionError = error as? ConversionError {
                throw conversionError
            }
            throw ConversionError.conversionFailed(underlying: error.localizedDescription)
        }
    }

    func cancel(requestID: UUID) async {
        guard activeRequestID == requestID else { return }
        cancelledRequestIDs.insert(requestID)
        if let activePlanID {
            await conversionEngine.cancel(jobID: activePlanID)
        }
    }

    private func checkCancellation(_ requestID: UUID) throws {
        guard !cancelledRequestIDs.contains(requestID), !Task.isCancelled else {
            throw ConversionError.cancelled
        }
    }

    private func ensureDestinationDirectory(
        for relativeParent: SafeRelativePath?,
        root: URL,
        createdDirectories: inout [URL]
    ) throws -> URL {
        guard let relativeParent else { return root }
        _ = try relativeParent.resolvedURL(relativeTo: root)
        var cursor = root
        for component in relativeParent.components {
            cursor = cursor.appendingPathComponent(component, isDirectory: true)
            if fileManager.fileExists(atPath: cursor.path) {
                guard Self.isExistingDirectory(cursor) else {
                    throw ConversionError.permissionDenied
                }
            } else {
                try fileManager.createDirectory(at: cursor, withIntermediateDirectories: false)
                createdDirectories.append(cursor)
            }
            let relative = try SafeRelativePath(
                cursor.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            )
            _ = try relative.resolvedURL(relativeTo: root)
        }
        return cursor
    }

    private static func rollback(
        publishedURLs: [URL],
        createdDirectories: [URL],
        stagingRoot: URL,
        fileManager: FileManager
    ) {
        for url in publishedURLs.reversed() {
            try? fileManager.removeItem(at: url)
        }
        for directory in createdDirectories.reversed() {
            try? fileManager.removeItem(at: directory)
        }
        try? fileManager.removeItem(at: stagingRoot)
    }

    private static func uniqueSecurityScopeURLs(
        for request: BatchConversionRequest
    ) -> [URL] {
        var seen: Set<URL> = []
        return (request.selections.map(\.url) + [request.outputDirectory]).filter {
            seen.insert($0.standardizedFileURL).inserted
        }
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private struct StagedItem: Sendable {
        let input: BatchInput
        let url: URL
    }
}

private actor BatchProgressReporter {
    private let requestID: UUID
    private let totalFiles: Int
    private let callback: @Sendable (BatchProgress) -> Void
    private var lastFraction = 0.0
    private var lastCurrentFile = 0

    init(
        requestID: UUID,
        totalFiles: Int,
        callback: @Sendable @escaping (BatchProgress) -> Void
    ) {
        self.requestID = requestID
        self.totalFiles = totalFiles
        self.callback = callback
    }

    func reportConversion(
        completedBeforeGroup: Int,
        groupInputs: [InputFile],
        localProgress: Double
    ) {
        let local = min(max(localProgress, 0), 1)
        let completed = Double(completedBeforeGroup) + local * Double(groupInputs.count)
        let fraction = 0.9 * completed / Double(max(totalFiles, 1))
        let localIndex = local > 0
            ? min(groupInputs.count - 1, max(0, Int(ceil(local * Double(groupInputs.count))) - 1))
            : 0
        emit(
            fraction: fraction,
            currentFile: min(totalFiles, completedBeforeGroup + localIndex + 1),
            displayName: groupInputs.indices.contains(localIndex)
                ? groupInputs[localIndex].displayName
                : nil
        )
    }

    func completeConversionGroup(completedFiles: Int, displayName: String?) {
        emit(
            fraction: 0.9 * Double(completedFiles) / Double(max(totalFiles, 1)),
            currentFile: min(totalFiles, completedFiles),
            displayName: displayName
        )
    }

    func reportPublication(publishedFiles: Int, displayName: String?) {
        emit(
            fraction: 0.9 + 0.1 * Double(publishedFiles) / Double(max(totalFiles, 1)),
            currentFile: min(totalFiles, publishedFiles),
            displayName: displayName
        )
    }

    func finish(displayName: String?) {
        emit(fraction: 1, currentFile: totalFiles, displayName: displayName)
    }

    private func emit(fraction: Double, currentFile: Int, displayName: String?) {
        lastFraction = max(lastFraction, min(max(fraction, 0), 1))
        lastCurrentFile = max(lastCurrentFile, min(max(currentFile, 0), totalFiles))
        callback(
            BatchProgress(
                requestID: requestID,
                fraction: lastFraction,
                currentFile: lastCurrentFile,
                totalFiles: totalFiles,
                currentDisplayName: displayName
            )
        )
    }
}
