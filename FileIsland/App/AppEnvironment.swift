import Foundation

@MainActor
struct AppEnvironment {
    let core: FileIslandCore
    let outputDirectorySelector: any OutputDirectorySelecting
    let screenProvider: IslandScreenProvider
    let outputFolderStore: OutputFolderBookmarkStore
    let preferences: AppPreferences
    let localization: LocalizationController
    let loginItemController: any LoginItemControlling

    static let live: AppEnvironment = {
        let preferences = AppPreferences()
        return AppEnvironment(
            core: .live(),
            outputDirectorySelector: AppKitOutputDirectorySelector(),
            screenProvider: IslandScreenProvider(),
            outputFolderStore: OutputFolderBookmarkStore(),
            preferences: preferences,
            localization: LocalizationController(preferences: preferences),
            loginItemController: ServiceManagementLoginItemController()
        )
    }()

    func makeIslandWindowController() -> IslandWindowController {
        let ffmpegURL = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")
        let ffprobeURL = Bundle.main.url(forAuxiliaryExecutable: "ffprobe")
        let mediaValidatorURL = Bundle.main.url(
            forAuxiliaryExecutable: "FileIslandMediaValidator"
        )
        let splitRuntimeAvailable = core.videoSplitProbe != nil
            && core.videoSplitCoordinator != nil
            && Self.isUsableBundledExecutable(ffmpegURL)
            && Self.isUsableBundledExecutable(ffprobeURL)
            && Self.isUsableBundledExecutable(mediaValidatorURL)
            && ffmpegURL?.deletingLastPathComponent().standardizedFileURL
                == ffprobeURL?.deletingLastPathComponent().standardizedFileURL
            && ffmpegURL?.deletingLastPathComponent().standardizedFileURL
                == mediaValidatorURL?.deletingLastPathComponent().standardizedFileURL
        let viewModel = IslandViewModel(
            fileInspector: core.fileInspector,
            inputScanner: core.inputScanner,
            conversionEngine: core.conversionEngine,
            batchCoordinator: core.batchCoordinator,
            videoSplitProbe: core.videoSplitProbe,
            videoSplitCoordinator: core.videoSplitCoordinator,
            videoSplitPlanBuilder: core.videoSplitPlanBuilder,
            videoSplitRuntimeAvailable: splitRuntimeAvailable,
            outputDirectorySelector: outputDirectorySelector,
            outputFolderStore: outputFolderStore,
            preferences: preferences,
            capabilityResolver: core.capabilityResolver,
            presetCatalogLoader: core.presetCatalogLoader,
            presetResolver: core.presetResolver,
            batchRequestBuilder: core.batchRequestBuilder
        )
        return IslandWindowController(
            viewModel: viewModel,
            screenProvider: screenProvider,
            localization: localization
        )
    }

    private static func isUsableBundledExecutable(_ url: URL?) -> Bool {
        guard let url,
              url.isFileURL,
              let values = try? url.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    func makeSettingsWindowController() -> SettingsWindowController {
        SettingsWindowController(
            viewModel: SettingsViewModel(
                preferences: preferences,
                outputFolderStore: outputFolderStore,
                outputDirectorySelector: outputDirectorySelector,
                loginItemController: loginItemController
            ),
            localization: localization
        )
    }
}
