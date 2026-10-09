import AppKit

/// The language of the app's text. Follows the system (falling back to English) unless the user
/// picks one in the settings. The choice is stored like macOS stores a per-app language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case german = "de"

    var id: Self { self }

    /// Language names stay in their own language, as in every language menu.
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .english: "English"
        case .german: "Deutsch"
        }
    }

    private static let key = "AppleLanguages"

    /// The choice stored for this app only; the system's list lives in the global domain.
    static var selected: AppLanguage {
        guard let domain = Bundle.main.bundleIdentifier,
              let languages = UserDefaults.standard.persistentDomain(forName: domain)?[key] as? [String],
              let first = languages.first
        else { return .system }
        return AppLanguage(rawValue: String(first.prefix(2))) ?? .system
    }

    static func select(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: key)
        }
    }

    /// The localization this choice leads to: a supported system language, otherwise English.
    var localization: String {
        guard self == .system else { return rawValue }
        let system = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[Self.key] as? [String] ?? []
        return Bundle.preferredLocalizations(from: Bundle.main.localizations.filter { $0 != "Base" }, forPreferences: system).first ?? "en"
    }

    /// The text is loaded at launch, so another language needs a restart.
    var needsRestart: Bool {
        localization != (Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// Opens a new instance of the app and quits this one.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { MenuBarMode.quit() }
        }
    }
}
