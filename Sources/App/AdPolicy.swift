import simd
import Foundation

/// Launch-ad and purchase-cache rules. No network and no ad SDK.
enum AdPolicy {
    struct Decision: Equatable {
        var load: Bool
        var present: Bool
        /// True only when an ad is about to be shown. The caller records the day after it is actually presented.
        var consumeDay: Bool
        var markOpened: Bool
    }

    /// `coldStart` is the first activation of this process, not a return from background.
    static func opening(
        openedBefore: Bool,
        adsRemoved: Bool,
        shownDay: String?,
        today: String,
        coldStart: Bool,
        consentAllowsRequest: Bool,
        adReady: Bool,
        userStarted: Bool
    ) -> Decision {
        let markOpened = true
        if !coldStart || adsRemoved || !openedBefore || shownDay == today || !consentAllowsRequest || userStarted {
            return Decision(load: false, present: false, consumeDay: false, markOpened: markOpened)
        }
        if adReady {
            return Decision(load: false, present: true, consumeDay: true, markOpened: markOpened)
        }
        return Decision(load: true, present: false, consumeDay: false, markOpened: markOpened)
    }

    /// Our own notice after a full-screen ad was presented and then closed. A failed or skipped ad does not qualify.
    static func offerAfterDismissedAd(presented: Bool, failed: Bool, adsRemoved: Bool) -> Bool {
        presented && !failed && !adsRemoved
    }

    /// Live ads only for an App Store copy. Debug, a provisioning profile, TestFlight's
    /// sandbox receipt, or a missing receipt stay on Google's test ad unit.
    static func usesProductionAds(debug: Bool, hasProvisioningProfile: Bool, receiptName: String?, receiptExists: Bool) -> Bool {
        if debug || hasProvisioningProfile || !receiptExists { return false }
        return receiptName == "receipt"
    }

    /// A finished StoreKit check replaces the cache. A failed or unfinished check keeps it, including offline.
    static func entitlement(cached: Bool, checkFinished: Bool, hasVerifiedEntitlement: Bool) -> Bool {
        checkFinished ? hasVerifiedEntitlement : cached
    }
}

enum AdSchedule {
    static let openedKey = "ads.openedBefore"
    static let shownDayKey = "ads.lastShownDay"
    static let removedKey = "ads.removed"

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func load(_ defaults: UserDefaults = .standard) -> (opened: Bool, shownDay: String?, removed: Bool) {
        (defaults.bool(forKey: openedKey), defaults.string(forKey: shownDayKey), defaults.bool(forKey: removedKey))
    }

    static func markOpened(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: openedKey)
    }

    static func markShown(day: String, _ defaults: UserDefaults = .standard) {
        defaults.set(day, forKey: shownDayKey)
    }

    static func setRemoved(_ value: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: removedKey)
    }
}
