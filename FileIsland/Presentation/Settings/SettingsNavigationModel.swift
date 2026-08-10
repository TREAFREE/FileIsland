import Observation

@MainActor
@Observable
final class SettingsNavigationModel {
    private(set) var selection: SettingsView.Pane

    init(selection: SettingsView.Pane = .general) {
        self.selection = selection
    }

    func select(_ pane: SettingsView.Pane) {
        selection = pane
    }
}
