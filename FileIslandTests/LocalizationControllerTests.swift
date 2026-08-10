import Foundation
import XCTest
@testable import FileIsland

@MainActor
final class LocalizationControllerTests: XCTestCase {
    func testLanguagePersistsAndSystemLanguageResolvesToSupportedLocale() {
        let defaults = isolatedDefaults()
        let preferences = AppPreferences(defaults: defaults)
        let controller = LocalizationController(
            preferences: preferences,
            catalog: StubLocalizationCatalog(),
            preferredLanguages: { ["zh-Hans-CN"] }
        )

        XCTAssertEqual(controller.language, .system)
        XCTAssertEqual(controller.resolvedLanguage, .simplifiedChinese)

        controller.language = .english

        XCTAssertEqual(AppPreferences(defaults: defaults).appLanguage, .english)
        XCTAssertEqual(controller.resolvedLanguage, .english)
    }

    func testExplicitLanguageLookupFormattingAndMissingKeyFallback() {
        let preferences = AppPreferences(defaults: isolatedDefaults())
        let controller = LocalizationController(
            preferences: preferences,
            catalog: StubLocalizationCatalog(strings: [
                .english: ["progress.percent": "Progress: %d%%"],
                .simplifiedChinese: ["progress.percent": "进度：%d%%"],
            ]),
            preferredLanguages: { ["en-US"] }
        )

        controller.language = .simplifiedChinese

        XCTAssertEqual(controller.string("progress.percent", 42), "进度：42%")
        XCTAssertEqual(controller.string("missing.key"), "missing.key")
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        let controller = LocalizationController(
            preferences: AppPreferences(defaults: isolatedDefaults()),
            catalog: StubLocalizationCatalog(),
            preferredLanguages: { ["fr-FR"] }
        )

        XCTAssertEqual(controller.resolvedLanguage, .english)
        XCTAssertEqual(controller.locale.identifier, "en")
    }

    func testBundledCatalogContainsSimplifiedChineseMenuTranslation() {
        let catalog = BundleLocalizationCatalog()

        XCTAssertEqual(
            catalog.string(forKey: "Settings…", language: .simplifiedChinese),
            "设置…"
        )
    }

    func testBundledCatalogContainsSelectionAccessibilityTranslations() {
        let catalog = BundleLocalizationCatalog()

        XCTAssertEqual(
            catalog.string(forKey: "Selected", language: .simplifiedChinese),
            "已选择"
        )
        XCTAssertEqual(
            catalog.string(forKey: "Not selected", language: .simplifiedChinese),
            "未选择"
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "LocalizationControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private struct StubLocalizationCatalog: LocalizationCatalogProviding {
    var strings: [AppLanguage: [String: String]] = [:]

    func string(forKey key: String, language: AppLanguage) -> String? {
        strings[language]?[key]
    }
}
