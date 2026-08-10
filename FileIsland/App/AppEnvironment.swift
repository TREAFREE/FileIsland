import Foundation

@MainActor
struct AppEnvironment {
    let fileInspector: any FileInspecting
    let conversionEngine: any ConversionEngine
    let outputDirectorySelector: any OutputDirectorySelecting
    let screenProvider: IslandScreenProvider
    let outputFolderStore: OutputFolderBookmarkStore
    let preferences: AppPreferences
    let loginItemController: any LoginItemControlling
    let presetCatalogLoader: any PresetCatalogLoading

    static let live = AppEnvironment(
        fileInspector: URLFileInspector(),
        conversionEngine: ConversionEngineRouter(
            engines: [
                ImageConversionEngine(),
                NativeVideoConversionEngine(),
                FFmpegConversionEngine()
            ]
        ),
        outputDirectorySelector: AppKitOutputDirectorySelector(),
        screenProvider: IslandScreenProvider(),
        outputFolderStore: OutputFolderBookmarkStore(),
        preferences: AppPreferences(),
        loginItemController: ServiceManagementLoginItemController(),
        presetCatalogLoader: BundledPresetCatalogLoader()
    )

    func makeIslandWindowController() -> IslandWindowController {
        let viewModel = IslandViewModel(
            fileInspector: fileInspector,
            conversionEngine: conversionEngine,
            outputDirectorySelector: outputDirectorySelector,
            outputFolderStore: outputFolderStore,
            preferences: preferences,
            presetCatalogLoader: presetCatalogLoader
        )
        return IslandWindowController(
            viewModel: viewModel,
            screenProvider: screenProvider
        )
    }

    func makeSettingsWindowController() -> SettingsWindowController {
        SettingsWindowController(
            viewModel: SettingsViewModel(
                preferences: preferences,
                outputFolderStore: outputFolderStore,
                outputDirectorySelector: outputDirectorySelector,
                loginItemController: loginItemController
            )
        )
    }
}
