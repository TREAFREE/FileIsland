import Foundation

@MainActor
struct AppEnvironment {
    let fileInspector: any FileInspecting
    let screenProvider: IslandScreenProvider

    static let live = AppEnvironment(
        fileInspector: URLFileInspector(),
        screenProvider: IslandScreenProvider()
    )

    func makeIslandWindowController() -> IslandWindowController {
        let viewModel = IslandViewModel(fileInspector: fileInspector)
        return IslandWindowController(
            viewModel: viewModel,
            screenProvider: screenProvider
        )
    }
}
