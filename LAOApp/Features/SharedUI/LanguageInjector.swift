import SwiftUI

/// Supported UI languages, persisted as `AppSettings.language`.
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case en
    case ko

    /// UserDefaults key for the persisted language preference.
    static let userDefaultsKey = "lao.lastLanguage"

    var id: String { rawValue }

    /// Native display name shown in the language picker.
    var displayName: String {
        switch self {
        case .en: return "English"
        case .ko: return "한국어"
        }
    }

    var strings: AppStrings {
        switch self {
        case .en: return .en
        case .ko: return .ko
        }
    }

    /// Resolve the current AppStrings from the persisted language preference.
    /// Use in non-SwiftUI contexts (AppDelegate, ViewModels) where `@Environment(\.lang)` is unavailable.
    static var currentStrings: AppStrings {
        let raw = UserDefaults.standard.string(forKey: userDefaultsKey) ?? "en"
        return AppLanguage(rawValue: raw)?.strings ?? AppLanguage.en.strings
    }
}

// MARK: - Environment Key

private struct LangKey: EnvironmentKey {
    static let defaultValue: AppStrings = .en
}

extension EnvironmentValues {
    var lang: AppStrings {
        get { self[LangKey.self] }
        set { self[LangKey.self] = newValue }
    }
}

// MARK: - Language Injector

/// Injects the localized string catalog into the environment,
/// mirroring the `ThemeInjector` pattern used for theming.
struct LanguageInjector<Content: View>: View {
    let language: AppLanguage
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.lang, language.strings)
    }
}
