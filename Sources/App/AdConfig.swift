import simd
import Foundation

/// AdMob configuration for AstroShip.
///
/// Debug builds embed Google's test app ID and always request the test App Open unit.
/// Release builds embed the production app ID; only an App Store copy requests the production unit.
enum AdConfig {
    static let testApplicationID = "ca-app-pub-3940256099942544~1458002511"
    static let testAppOpenUnitID = "ca-app-pub-3940256099942544/5575463023"
    /// AstroShip in AdMob (publisher pub-7991339056188042). Release builds embed this app ID.
    static let productionApplicationID: String? = "ca-app-pub-7991339056188042~2002874937"
    /// App Open unit. Served only to App Store copies; Debug, simulator and TestFlight use the test unit.
    static let productionAppOpenUnitID: String? = "ca-app-pub-7991339056188042/2445728065"

    static var plistApplicationID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String
    }

    /// Production unit only for an App Store copy and only when both production IDs are configured
    /// and the Info.plist carries the production app ID. Everything else uses the test unit.
    static func appOpenUnitID(productionAds: Bool) -> String {
        if productionAds, let unit = productionAppOpenUnitID, let app = productionApplicationID, plistApplicationID == app {
            return unit
        }
        return testAppOpenUnitID
    }

    /// Refuse to request when the plist app ID is neither the test ID nor the configured production ID,
    /// or when a debug build carries the production app ID.
    static func isConfigured(debug: Bool) -> Bool {
        guard let id = plistApplicationID else { return false }
        if id == testApplicationID { return true }
        if let prod = productionApplicationID, id == prod { return !debug }
        return false
    }
}

enum AdRuntime {
    static var compiledDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
    static var hasProvisioningProfile: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }
    static var receiptName: String? { Bundle.main.appStoreReceiptURL?.lastPathComponent }
    static var receiptExists: Bool {
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

@MainActor
enum AdGate {
    /// Simulator screenshot runs never show consent or ads.
    static var disabledForScreenshots = false
}
