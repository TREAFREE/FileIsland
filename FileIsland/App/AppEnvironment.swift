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
        let viewModel = IslandViewModel(
            fileInspector: core.fileInspector,
            inputScanner: core.inputScanner,
            conversionEngine: core.conversionEngine,
            batchCoordinator: core.batchCoordinator,
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
