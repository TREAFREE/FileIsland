import XCTest
@testable import FileIsland

final class SelectionChoiceAppearanceTests: XCTestCase {
    func testSelectedChoiceHasUnmistakableEmphasis() {
        let idle = SelectionChoiceAppearance.resolve(
            isSelected: false,
            isHovered: false,
            isEnabled: true,
            increaseContrast: false
        )
        let selected = SelectionChoiceAppearance.resolve(
            isSelected: true,
            isHovered: false,
            isEnabled: true,
            increaseContrast: false
        )

        XCTAssertFalse(idle.showsCheckmark)
        XCTAssertTrue(selected.showsCheckmark)
        XCTAssertGreaterThan(selected.fillOpacity, idle.fillOpacity)
        XCTAssertGreaterThan(selected.borderOpacity, idle.borderOpacity)
        XCTAssertGreaterThan(selected.foregroundOpacity, idle.foregroundOpacity)
        XCTAssertTrue(selected.usesSemiboldText)
    }

    func testHoverEmphasizesIdleWithoutImpersonatingSelection() {
        let idle = SelectionChoiceAppearance.resolve(
            isSelected: false,
            isHovered: false,
            isEnabled: true,
            increaseContrast: false
        )
        let hovered = SelectionChoiceAppearance.resolve(
            isSelected: false,
            isHovered: true,
            isEnabled: true,
            increaseContrast: false
        )
        let selected = SelectionChoiceAppearance.resolve(
            isSelected: true,
            isHovered: false,
            isEnabled: true,
            increaseContrast: false
        )

        XCTAssertFalse(hovered.showsCheckmark)
        XCTAssertGreaterThan(hovered.fillOpacity, idle.fillOpacity)
        XCTAssertLessThan(hovered.fillOpacity, selected.fillOpacity)
        XCTAssertLessThan(hovered.borderOpacity, selected.borderOpacity)
    }

    func testSelectedDisabledChoiceRemainsSelectedAndIsSubdued() {
        let selected = SelectionChoiceAppearance.resolve(
            isSelected: true,
            isHovered: false,
            isEnabled: true,
            increaseContrast: false
        )
        let selectedDisabled = SelectionChoiceAppearance.resolve(
            isSelected: true,
            isHovered: false,
            isEnabled: false,
            increaseContrast: false
        )

        XCTAssertTrue(selectedDisabled.showsCheckmark)
        XCTAssertTrue(selectedDisabled.usesSemiboldText)
        XCTAssertLessThan(selectedDisabled.foregroundOpacity, selected.foregroundOpacity)
        XCTAssertGreaterThan(selectedDisabled.fillOpacity, 0)
    }

    func testIncreaseContrastStrengthensBoundaryWithoutChangingSelection() {
        let standard = SelectionChoiceAppearance.resolve(
            isSelected: false,
            isHovered: false,
            isEnabled: true,
            increaseContrast: false
        )
        let increased = SelectionChoiceAppearance.resolve(
            isSelected: false,
            isHovered: false,
            isEnabled: true,
            increaseContrast: true
        )

        XCTAssertEqual(increased.showsCheckmark, standard.showsCheckmark)
        XCTAssertGreaterThan(increased.borderOpacity, standard.borderOpacity)
        XCTAssertGreaterThan(increased.borderWidth, standard.borderWidth)
    }
}
