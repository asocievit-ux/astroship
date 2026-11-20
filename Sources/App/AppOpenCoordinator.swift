import simd
import Foundation
#if canImport(GoogleMobileAds)
import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// Same policy as the Bible app: at most one App Open ad per day, only on a cold start, never on the
/// very first launch, never after "Remove Ads", only after Google UMP consent allows requests.
/// A load that finishes after the user has started touching the 3D view is discarded.
@MainActor
final class AppOpenCoordinator: NSObject, FullScreenContentDelegate {
    static let shared = AppOpenCoordinator()
    private var didColdStart = false
    private var didPresentAd = false
    private var store: RemoveAdsStore?
    private var ad: AppOpenAd?
    weak var model: AppModel?

    func onColdStart(store: RemoveAdsStore, model: AppModel) async {
        self.store = store
        self.model = model
        guard !didColdStart, !AdGate.disabledForScreenshots else { return }
        didColdStart = true
        let saved = AdSchedule.load()
        let today = AdSchedule.dayString(Date())
        if !saved.opened {
            AdSchedule.markOpened()
            // EEA / UK / Switzerland: the consent message is shown once, before any ad is ever requested.
            if !store.adsRemoved { _ = await gatherConsent() }
            return
        }
        await store.refresh()
        // Every launch (Google's UMP guidance): refresh consent and show the form when it is required.
        let consent = store.adsRemoved ? false : await gatherConsent()
        let first = AdPolicy.opening(
            openedBefore: true, adsRemoved: store.adsRemoved, shownDay: saved.shownDay, today: today,
            coldStart: true, consentAllowsRequest: true, adReady: false, userStarted: model.interacted)
        let productionAds = AdPolicy.usesProductionAds(
            debug: AdRuntime.compiledDebug, hasProvisioningProfile: AdRuntime.hasProvisioningProfile,
            receiptName: AdRuntime.receiptName, receiptExists: AdRuntime.receiptExists)
        guard first.load, AdConfig.isConfigured(debug: AdRuntime.compiledDebug) else { return }
        guard consent, !model.interacted, !store.adsRemoved else { return }
        await MobileAds.shared.start()
        do {
            let loaded = try await AppOpenAd.load(with: AdConfig.appOpenUnitID(productionAds: productionAds), request: Request())
            guard !model.interacted, !store.adsRemoved else { return }
            loaded.fullScreenContentDelegate = self
            ad = loaded
            loaded.present(from: nil)
        } catch {
            ad = nil
        }
    }

    private func gatherConsent() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: UMPRequestParameters()) { _ in c.resume() }
        }
        if UMPConsentInformation.sharedInstance.consentStatus == .required, let root = ConsentPresenter.rootViewController {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                UMPConsentForm.loadAndPresentIfRequired(from: root) { _ in c.resume() }
            }
        }
        store?.consentUpdated()
        // App Tracking Transparency after the UMP message (Google's recommended order). Declining only
        // means non-personalised ads; the app works the same.
        if UMPConsentInformation.sharedInstance.canRequestAds,
           ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        return UMPConsentInformation.sharedInstance.canRequestAds
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        didPresentAd = true
        AdSchedule.markShown(day: AdSchedule.dayString(Date()))
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        let show = AdPolicy.offerAfterDismissedAd(presented: didPresentAd, failed: false, adsRemoved: store?.adsRemoved ?? true)
        didPresentAd = false
        self.ad = nil
        if show { store?.showPremiumNotice() }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        didPresentAd = false
        self.ad = nil
    }
}
#else
/// visionOS: no ads SDK, so nothing happens on launch.
@MainActor
final class AppOpenCoordinator {
    static let shared = AppOpenCoordinator()
    func onColdStart(store: RemoveAdsStore, model: AppModel) async {}
}
#endif
