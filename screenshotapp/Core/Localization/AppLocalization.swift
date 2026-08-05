import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var title: String {
        switch self {
        case .english:
            AppLocalization.string("language.english")
        case .turkish:
            AppLocalization.string("language.turkish")
        }
    }
}

enum AppLocalization {
    private static let tableName = "Localizable"

    static var currentLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: ToolboxSettings.Keys.language)
            ?? ToolboxSettings.defaultLanguage.rawValue
        return AppLanguage(rawValue: rawValue) ?? ToolboxSettings.defaultLanguage
    }

    static var currentLocale: Locale {
        currentLanguage.locale
    }

    static func string(_ key: String) -> String {
        languageBundle.localizedString(forKey: key, value: key, table: tableName)
    }

    static func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        let format = string(key)
        return String(format: format, locale: currentLocale, arguments: arguments)
    }

    private static var languageBundle: Bundle {
        guard
            let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .main
        }

        return bundle
    }
}
