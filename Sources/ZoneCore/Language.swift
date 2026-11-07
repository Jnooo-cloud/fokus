import Foundation

/// German or English, picked in Fokus' settings. `system` follows the Mac's preferred language.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, german = "de", english = "en"

    public static let defaultsKey = "language"
    public var id: Self { self }

    public static var isEnglish: Bool {
        switch UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .system {
        case .german: false
        case .english: true
        case .system: !(Locale.preferredLanguages.first ?? "en").hasPrefix("de")
        }
    }

    public static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "de_DE") }

    public var title: String {
        switch self {
        case .system: L("Wie macOS", "Like macOS")
        case .german: "Deutsch"
        case .english: "English"
        }
    }
}

/// Every visible text is written in both languages right where it is used, so nothing can go missing.
public func L(_ german: String, _ english: String) -> String { AppLanguage.isEnglish ? english : german }
