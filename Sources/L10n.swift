import Foundation

/// Resolves strings and locale from the language chosen in Preferences,
/// so switching between English and Turkish works without a relaunch.
@MainActor
enum L10n {
    private static var cachedCode: String?
    private static var cachedBundle: Bundle = .main

    static var bundle: Bundle {
        let code = AppSettings.shared.language.code
        if code == cachedCode { return cachedBundle }
        cachedCode = code
        if let code,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let localized = Bundle(path: path) {
            cachedBundle = localized
        } else {
            cachedBundle = .main
        }
        return cachedBundle
    }

    static var locale: Locale {
        if let id = AppSettings.shared.language.localeIdentifier {
            return Locale(identifier: id)
        }
        return .autoupdatingCurrent
    }
}

@MainActor
func L(_ key: String) -> String {
    L10n.bundle.localizedString(forKey: key, value: key, table: nil)
}

@MainActor
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: L10n.locale, arguments: args)
}
