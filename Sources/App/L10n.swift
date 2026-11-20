import simd
import Foundation
import SwiftUI
import AstroCore

/// Localized string from Localizable.strings (11 languages; base English), in the language picked in
/// Settings (or the system's).
func L(_ key: String) -> String { NSLocalizedString(key, bundle: AppLanguage.bundle, comment: "") }
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: AppLanguage.bundle, comment: ""), locale: AppLanguage.locale, arguments: args)
}

/// In-app language override (Settings > Language). "" = follow the system. Switching applies at once:
/// the root view swaps its locale / layout direction environment and rebuilds the UI layer (not the scene).
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()
    static let codes = ["en", "ja", "zh-Hans", "es", "pt", "fr", "de", "tl", "ru", "sv", "he"]
    private static let key = "app.language"

    nonisolated(unsafe) private(set) static var bundle: Bundle = .main
    nonisolated(unsafe) private(set) static var locale: Locale = .current

    @Published var code: String {
        didSet {
            UserDefaults.standard.set(code, forKey: Self.key)
            Self.apply(code)
        }
    }

    private init() {
        let c = UserDefaults.standard.string(forKey: Self.key) ?? ""
        code = Self.codes.contains(c) ? c : ""
        Self.apply(code)
    }

    private static func apply(_ c: String) {
        if c.isEmpty {
            bundle = .main
            locale = .current
        } else {
            bundle = Bundle.main.path(forResource: c, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
            locale = Locale(identifier: c)
        }
        Fmt.resetFormatters()
    }

    /// Effective language (override, else the localization the system picked for the app).
    var effectiveCode: String { code.isEmpty ? (Bundle.main.preferredLocalizations.first ?? "en") : code }
    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: effectiveCode).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    var environmentLocale: Locale { code.isEmpty ? .current : Locale(identifier: code) }

    /// Each language in its own name ("日本語", "Español", "עברית" …).
    static func nativeName(_ c: String) -> String {
        let l = Locale(identifier: c)
        let n = l.localizedString(forIdentifier: c) ?? c
        return n.prefix(1).uppercased(with: l) + n.dropFirst()
    }
}

extension BodyID {
    var localizedName: String { L("body.\(key)") }
}

extension BodyKind {
    var localizedName: String {
        switch self {
        case .star: return L("kind.star")
        case .planet: return L("kind.planet")
        case .dwarf: return L("kind.dwarf")
        case .moon: return L("kind.moon")
        case .comet: return L("kind.comet")
        }
    }
}

enum Fmt {
    static func number(_ v: Double, digits: Int = 0) -> String {
        let f = NumberFormatter()
        f.locale = AppLanguage.locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    static func distance(km: Double) -> String {
        let au = km / Frames.au
        if au >= 0.1 { return L("unit.au", number(au, digits: au < 10 ? 3 : 2)) }
        return L("unit.km", number(km))
    }

    static func duration(days: Double) -> String {
        if days < 2 { return L("unit.hours", number(days * 24, digits: 1)) }
        if days < 800 { return L("unit.days", number(days, digits: days < 30 ? 2 : 1)) }
        return L("unit.years", number(days / 365.25, digits: days < 36_525 ? 2 : 0))
    }

    static func lightTime(km: Double) -> String {
        let s = km / 299_792.458
        if s < 120 { return L("unit.lightSeconds", number(s, digits: 1)) }
        if s < 7200 { return L("unit.lightMinutes", number(s / 60, digits: 1)) }
        return L("unit.lightHours", number(s / 3600, digits: 2))
    }

    nonisolated(unsafe) private static var cachedDate: DateFormatter?
    static var dateFormatter: DateFormatter {
        if let f = cachedDate { return f }
        let f = DateFormatter()
        f.locale = AppLanguage.locale
        f.dateStyle = .medium
        f.timeStyle = .medium
        cachedDate = f
        return f
    }
    nonisolated(unsafe) private static var cachedDay: DateFormatter?
    nonisolated(unsafe) private static var cachedTime: DateFormatter?
    /// Top bar: date (with year) and time on two short lines so long locales (Hebrew, Russian) fit
    /// beside the one-row icon bar.
    static func twoLineDate(_ d: Date) -> String {
        if cachedDay == nil {
            let f = DateFormatter(); f.locale = AppLanguage.locale; f.dateStyle = .medium; f.timeStyle = .none; cachedDay = f
            let t = DateFormatter(); t.locale = AppLanguage.locale; t.dateStyle = .none; t.timeStyle = .medium; cachedTime = t
        }
        return cachedDay!.string(from: d) + "\n" + cachedTime!.string(from: d)
    }
    static func resetFormatters() { cachedDate = nil; cachedDay = nil; cachedTime = nil }
}

extension View {
    /// Locale + layout direction (RTL for Hebrew) of the in-app language; `.id` rebuilds text that was
    /// resolved through `L()`.
    func appLanguage(_ lang: AppLanguage) -> some View {
        self.environment(\.locale, lang.environmentLocale)
            .environment(\.layoutDirection, lang.layoutDirection)
            .environmentObject(lang)
    }
}
