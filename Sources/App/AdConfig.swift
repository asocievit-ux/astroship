import simd
import Foundation

/// AdMob configuration for AstroShip.
///
/// ┌──────────────────────────────────────────────────────────────────────────────┐
/// │ PLACEHOLDER: no production AdMob app / ad unit exists for AstroShip yet.     │
/// │ Until both IDs below are filled in, every build (Debug, TestFlight and an    │
/// │ App Store build) requests Google's official TEST app open ad only.           │
/// │ To go live: create the app + App Open unit in AdMob, put the IDs here AND    │
/// │ set GAD_APPLICATION_ID for the Release config in project.yml.                │
/// └──────────────────────────────────────────────────────────────────────────────┘
enum AdConfig {
    static let testApplicationID = "ca-app-pub-3940256099942544~1458002511"
    static let testAppOpenUnitID = "ca-app-pub-3940256099942544/5575463023"
    /// TODO(production): "ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"
    static let productionApplicationID: String? = nil
    /// TODO(production): "ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ"
    static let productionAppOpenUnitID: String? = nil

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
