import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    var onIslandOpacityChange: ((Double) -> Void)?

    var defaultQuality: QualityPreference {
        didSet { defaults.set(defaultQuality.rawValue, forKey: Keys.defaultQuality) }
    }

    var stripMetadataByDefault: Bool {
        didSet { defaults.set(stripMetadataByDefault, forKey: Keys.stripMetadata) }
    }

    var revealOutputOnCompletion: Bool {
        didSet { defaults.set(revealOutputOnCompletion, forKey: Keys.revealOutput) }
    }

    var islandOpacity: Double {
        didSet {
            let clamped = min(max(islandOpacity, 0.65), 1)
            if islandOpacity != clamped { islandOpacity = clamped; return }
            defaults.set(clamped, forKey: Keys.islandOpacity)
            onIslandOpacityChange?(clamped)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultQuality = QualityPreference(
            rawValue: defaults.string(forKey: Keys.defaultQuality) ?? ""
        ) ?? .balanced
        stripMetadataByDefault = defaults.object(forKey: Keys.stripMetadata) as? Bool ?? true
        revealOutputOnCompletion = defaults.object(forKey: Keys.revealOutput) as? Bool ?? false
        let storedOpacity = defaults.object(forKey: Keys.islandOpacity) as? Double
        islandOpacity = min(max(storedOpacity ?? 1, 0.65), 1)
    }

    private enum Keys {
        static let defaultQuality = "conversion.defaultQuality"
        static let stripMetadata = "conversion.stripMetadata"
        static let revealOutput = "behavior.revealOutput"
        static let islandOpacity = "appearance.islandOpacity"
    }
}
