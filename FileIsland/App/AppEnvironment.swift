import Foundation

@MainActor
struct AppEnvironment {
    let fileInspector: any FileInspecting
    let conversionEngine: any ConversionEngine
    let outputDirectorySelector: any OutputDirectorySelecting
    let screenProvider: IslandScreenProvider

    static let live = AppEnvironment(
        fileInspector: URLFileInspector(),
        conversionEngine: ImageConversionEngine(),
        outputDirectorySelector: AppKitOutputDirectorySelector(),
        screenProvider: IslandScreenProvider()
    )

    func makeIslandWindowController() -> IslandWindowController {
        let viewModel = IslandViewModel(
            fileInspector: fileInspector,
            conversionEngine: conversionEngine,
            outputDirectorySelector: outputDirectorySelector
        )
        return IslandWindowController(
            viewModel: viewModel,
            screenProvider: screenProvider
        )
    }
}
