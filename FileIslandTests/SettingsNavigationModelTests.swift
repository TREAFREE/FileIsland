import XCTest
@testable import FileIsland

@MainActor
final class SettingsNavigationModelTests: XCTestCase {
    func testEverySettingsPaneCanBecomeTheCurrentSelection() {
        let navigation = SettingsNavigationModel(selection: .general)

        for pane in SettingsView.Pane.allCases {
            navigation.select(pane)
            XCTAssertEqual(navigation.selection, pane)
        }
    }
}
