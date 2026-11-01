import Foundation

/// Resolve strings from the SwiftUI environment locale rather than the process
/// language, so previews and a changed app locale update together with the UI.
struct SnakeStrings {
    private let localizedBundle: Bundle?
    private let englishBundle: Bundle?
    private let formattingLocale: Locale

    init(locale: Locale, bundle: Bundle = .main) {
        let language = locale.language.languageCode?.identifier == "zh" ? "zh-Hans" : "en"
        localizedBundle = Self.localizationBundle(language, in: bundle)
        englishBundle = Self.localizationBundle("en", in: bundle)
        formattingLocale = Locale(identifier: language)
    }

    func text(_ key: String) -> String {
        let fallback = englishBundle?.localizedString(forKey: key, value: key, table: "Localizable") ?? key
        return localizedBundle?.localizedString(forKey: key, value: fallback, table: "Localizable") ?? fallback
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: formattingLocale, arguments: arguments)
    }

    private static func localizationBundle(_ language: String, in bundle: Bundle) -> Bundle? {
        guard let path = bundle.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}
