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

    func testBundledCatalogContainsAccessibleInputPickerTranslations() {
        let catalog = BundleLocalizationCatalog()

        XCTAssertEqual(
            catalog.string(
                forKey: "Choose Files or Folder…",
                language: .simplifiedChinese
            ),
            "选择文件或文件夹…"
        )
        XCTAssertEqual(
            catalog.string(
                forKey: "Select one or more files, or an ordinary folder. Sources stay untouched.",
                language: .simplifiedChinese
            ),
            "请选择一个或多个文件，或一个普通文件夹。源文件不会被修改。"
        )
        XCTAssertEqual(
            catalog.string(forKey: "Choose", language: .simplifiedChinese),
            "选择"
        )
    }

    func testBundledCatalogContainsCompactVideoSplitTranslations() {
        let catalog = BundleLocalizationCatalog()

        XCTAssertEqual(
            catalog.string(forKey: "Split for Sharing", language: .simplifiedChinese),
            "分享切分"
        )
        XCTAssertEqual(
            catalog.string(
                forKey: "Maximum segment size",
                language: .simplifiedChinese
            ),
            "每段最大大小"
        )
        XCTAssertEqual(
            catalog.string(forKey: "min", language: .simplifiedChinese),
            "分钟"
        )
        XCTAssertEqual(
            catalog.string(forKey: "hr", language: .simplifiedChinese),
            "小时"
        )
        XCTAssertEqual(
            catalog.string(forKey: "Checking keyframes…", language: .simplifiedChinese),
            "正在检查关键帧…"
        )
        XCTAssertEqual(
            catalog.string(
                forKey: "The original files were not changed and no partial results were kept.",
                language: .simplifiedChinese
            ),
            "源文件未被修改，也未保留任何不完整结果。"
        )
    }

    func testBundledCatalogContainsFirstRunAndSettingsMaturityTranslations() {
        let catalog = BundleLocalizationCatalog()

        XCTAssertEqual(
            catalog.string(forKey: "Drop to convert", language: .simplifiedChinese),
            "拖入即可转换"
        )
        XCTAssertEqual(
            catalog.string(
                forKey: "Images, video, audio, or folders",
                language: .simplifiedChinese
            ),
            "图片、视频、音频或文件夹"
        )
        XCTAssertEqual(
            catalog.string(forKey: "Choose files", language: .simplifiedChinese),
            "选择文件"
        )
        XCTAssertEqual(
            catalog.string(forKey: "Private and on-device", language: .simplifiedChinese),
            "私密且仅在本机处理"
        )
        XCTAssertEqual(
            catalog.string(forKey: "Latest Release", language: .simplifiedChinese),
            "最新版本"
        )
        XCTAssertEqual(
            catalog.string(
                forKey: "Conversions run locally. File Island does not upload your files or collect usage telemetry.",
                language: .simplifiedChinese
            ),
            "转换完全在本地运行。File Island 不会上传你的文件，也不会收集使用情况遥测。"
        )
    }

    func testBundledCatalogContainsResultShelfTranslations() {
        let catalog = BundleLocalizationCatalog()

        let expected: [String: String] = [
            "Copy": "复制",
            "Conversion outputs": "转换结果",
            "Drag files anywhere": "拖到任意位置",
            "Drag this output file": "拖出此结果文件",
            "Select All": "全选",
            "Show all outputs in Finder": "在访达中显示全部结果",
            "Show in Finder": "在访达中显示",
            "This output file is no longer available": "此结果文件已不可用",
        ]

        for (key, translation) in expected {
            XCTAssertEqual(
                catalog.string(forKey: key, language: .simplifiedChinese),
                translation,
                "Missing result shelf translation for \(key)"
            )
        }
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
