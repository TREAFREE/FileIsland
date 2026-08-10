import Foundation
import Observation

protocol LocalizationCatalogProviding: Sendable {
    func string(forKey key: String, language: AppLanguage) -> String?
}

struct BundleLocalizationCatalog: LocalizationCatalogProviding, @unchecked Sendable {
    let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func string(forKey key: String, language: AppLanguage) -> String? {
        let identifier = language == .simplifiedChinese ? "zh-Hans" : "en"
        guard
            let path = bundle.path(forResource: identifier, ofType: "lproj"),
            let languageBundle = Bundle(path: path)
        else { return nil }

        let value = languageBundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? nil : value
    }
}

@MainActor
@Observable
final class LocalizationController {
    @ObservationIgnored
    private let preferences: AppPreferences

    @ObservationIgnored
    private let catalog: any LocalizationCatalogProviding

    @ObservationIgnored
    private let preferredLanguages: @Sendable () -> [String]

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            preferences.appLanguage = language
            NotificationCenter.default.post(name: .fileIslandLanguageDidChange, object: self)
        }
    }

    var resolvedLanguage: AppLanguage {
        language == .system
            ? AppLanguage.resolved(from: preferredLanguages())
            : language
    }

    var locale: Locale {
        Locale(identifier: resolvedLanguage.localeIdentifier)
    }

    init(
        preferences: AppPreferences,
        catalog: any LocalizationCatalogProviding = BundleLocalizationCatalog(),
        preferredLanguages: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }
    ) {
        self.preferences = preferences
        self.catalog = catalog
        self.preferredLanguages = preferredLanguages
        language = preferences.appLanguage
    }

    func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = catalog.string(forKey: key, language: resolvedLanguage) ?? key
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }
}

extension Notification.Name {
    static let fileIslandLanguageDidChange = Notification.Name("FileIsland.languageDidChange")
}
