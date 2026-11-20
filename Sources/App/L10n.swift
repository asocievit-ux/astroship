import simd
import Foundation
import AstroCore

/// Localized string from Localizable.strings (11 languages; base English).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }
func L(_ key: String, _ args: CVarArg...) -> String { String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args) }

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

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()
}
