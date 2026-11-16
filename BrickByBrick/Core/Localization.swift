import Foundation
import os

/// The language the user picked in Settings. `.system` follows the device.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, english = "en", danish = "da"

    var id: String { rawValue }

    /// Explicit language code, or nil when following the device.
    var code: String? { self == .system ? nil : rawValue }

    var locale: Locale { code.map(Locale.init(identifier:)) ?? .autoupdatingCurrent }
}

/// Looks up strings that aren't SwiftUI literals (errors, stored messages) in the chosen language.
enum Localization {
    private static let current = OSAllocatedUnfairLock<AppLanguage>(initialState: .system)

    static func use(_ language: AppLanguage) { current.withLock { $0 = language } }

    static func string(_ key: String.LocalizationValue) -> String {
        let language = current.withLock { $0 }
        guard let code = language.code,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return String(localized: key) }
        return String(localized: key, bundle: bundle, locale: Locale(identifier: code))
    }
}
