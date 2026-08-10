import SwiftUI

struct SelectionChoiceAppearance: Equatable, Sendable {
    let showsCheckmark: Bool
    let fillOpacity: Double
    let borderOpacity: Double
    let foregroundOpacity: Double
    let borderWidth: Double
    let usesSemiboldText: Bool

    static func resolve(
        isSelected: Bool,
        isHovered: Bool,
        isEnabled: Bool,
        increaseContrast: Bool
    ) -> SelectionChoiceAppearance {
        let fillOpacity: Double
        let borderOpacity: Double
        let foregroundOpacity: Double

        if isSelected {
            fillOpacity = isEnabled ? 0.86 : 0.52
            borderOpacity = isEnabled ? 0.72 : 0.42
            foregroundOpacity = isEnabled ? 1 : 0.72
        } else if isHovered && isEnabled {
            fillOpacity = 0.16
            borderOpacity = 0.42
            foregroundOpacity = 0.95
        } else {
            fillOpacity = isEnabled ? 0.07 : 0.04
            borderOpacity = isEnabled ? 0.24 : 0.14
            foregroundOpacity = isEnabled ? 0.74 : 0.42
        }

        return SelectionChoiceAppearance(
            showsCheckmark: isSelected,
            fillOpacity: fillOpacity,
            borderOpacity: min(borderOpacity + (increaseContrast ? 0.20 : 0), 1),
            foregroundOpacity: foregroundOpacity,
            borderWidth: increaseContrast ? 1.5 : 1,
            usesSemiboldText: isSelected
        )
    }
}

struct SelectionChoiceButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(LocalizationController.self) private var localization
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 8)
                    .opacity(appearance.showsCheckmark ? 1 : 0)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(
                        size: 10.5,
                        weight: appearance.usesSemiboldText ? .semibold : .medium,
                        design: .rounded
                    ))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(appearance.foregroundOpacity))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background {
                Capsule(style: .continuous)
                    .fill(fillColor.opacity(appearance.fillOpacity))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(appearance.borderOpacity),
                        lineWidth: appearance.borderWidth
                    )
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(SelectionChoicePressStyle(reduceMotion: reduceMotion))
        .onHover { isHovered = $0 }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: appearance
        )
        .accessibilityLabel(title)
        .accessibilityValue(localization.string(selected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var appearance: SelectionChoiceAppearance {
        SelectionChoiceAppearance.resolve(
            isSelected: selected,
            isHovered: isHovered,
            isEnabled: isEnabled,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    private var fillColor: Color {
        selected ? .accentColor : .white
    }

}

private struct SelectionChoicePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}
