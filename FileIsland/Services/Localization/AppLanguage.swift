import Foundation

enum AppLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case system
    case english
    case simplifiedChinese

    var localeIdentifier: String {
        switch self {
        case .system:
            Locale.autoupdatingCurrent.identifier
        case .english:
            "en"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }

    static func resolved(from preferredLanguages: [String]) -> AppLanguage {
        guard let preferred = preferredLanguages.first?.lowercased() else { return .english }
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}
