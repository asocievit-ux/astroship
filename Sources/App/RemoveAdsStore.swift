import simd
import Foundation
import StoreKit
import UIKit
#if canImport(UserMessagingPlatform)
import UserMessagingPlatform
#endif

/// One-time non-consumable "Remove Ads". Configured in code; App Store Connect must have the same product ID.
@MainActor
final class RemoveAdsStore: ObservableObject {
    static let productID = "com.aihasakuramoto22.astroship.removeads"
    static let shared = RemoveAdsStore()

    @Published private(set) var adsRemoved: Bool {
        didSet { if adsRemoved { premiumNoticeVisible = false } }
    }
    @Published private(set) var premiumNoticeVisible = false
    @Published private(set) var displayPrice: String?
    @Published private(set) var unavailable = false
    @Published private(set) var note: String?
    /// True from the first tap on the purchase button until StoreKit answers. Further taps are ignored,
    /// so a slow purchase sheet cannot be queued several times.
    @Published private(set) var purchasing = false
    @Published private(set) var restoring = false
    @Published private(set) var consentRevision = 0

    static let premiumNoticeSeconds: UInt64 = 40
    private var updates: Task<Void, Never>?
    private var noticeTimer: Task<Void, Never>?
    private var product: Product?

    private init() {
        adsRemoved = AdSchedule.load().removed
        updates = Task { await listen() }
    }

    func refresh() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let t = verified(result), t.productID == Self.productID, t.revocationDate == nil { entitled = true }
        }
        let next = AdPolicy.entitlement(cached: adsRemoved, checkFinished: true, hasVerifiedEntitlement: entitled)
        adsRemoved = next
        AdSchedule.setRemoved(next)
    }

    func showPremiumNotice() {
        guard !adsRemoved else { return }
        premiumNoticeVisible = true
        noticeTimer?.cancel()
        noticeTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.premiumNoticeSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.premiumNoticeVisible = false
        }
    }

    func dismissPremiumNotice() {
        noticeTimer?.cancel(); noticeTimer = nil
        premiumNoticeVisible = false
    }

    func loadProduct() async {
        guard !adsRemoved else { return }
        do {
            if let p = try await Product.products(for: [Self.productID]).first {
                product = p
                displayPrice = p.displayPrice
                unavailable = false
            } else {
                displayPrice = nil; unavailable = true; note = L("ads.productUnavailable")
            }
        } catch {
            displayPrice = nil; unavailable = true; note = L("ads.priceUnavailable")
        }
    }

    func purchase() async {
        // Main actor: the check and the flag are set before the first await, so a second tap stops here.
        guard !purchasing, !restoring, !adsRemoved else { return }
        purchasing = true
        defer { purchasing = false }
        note = nil
        do {
            let found: Product?
            if let cached = product { found = cached } else { found = try await Product.products(for: [Self.productID]).first }
            guard let p = found else { unavailable = true; note = L("ads.productUnavailable"); return }
            product = p
            displayPrice = p.displayPrice
            switch try await p.purchase() {
            case .success(let result):
                guard let t = verified(result) else { note = L("ads.purchaseUnverified"); return }
                await t.finish()
                adsRemoved = true
                AdSchedule.setRemoved(true)
                note = L("ads.thanks")
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch {
            note = L("ads.purchaseFailed")
        }
    }

    func restore() async {
        guard !restoring, !purchasing else { return }
        restoring = true
        defer { restoring = false }
        note = nil
        do {
            try await AppStore.sync()
            await refresh()
            note = adsRemoved ? L("ads.restoreDone") : L("ads.restoreNothing")
        } catch {
            note = L("ads.restoreFailed")
        }
    }

    var privacyOptionsRequired: Bool {
        _ = consentRevision
        return ConsentPresenter.optionsRequired
    }
    func presentPrivacyOptions() { ConsentPresenter.presentPrivacyOptions() }
    func consentUpdated() { consentRevision += 1 }

    private func listen() async {
        for await result in Transaction.updates {
            guard let t = verified(result) else { continue }
            if t.productID == Self.productID {
                let keep = t.revocationDate == nil
                adsRemoved = keep
                AdSchedule.setRemoved(keep)
                await t.finish()
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) -> T? {
        guard case .verified(let v) = result else { return nil }
        return v
    }
}

@MainActor
enum ConsentPresenter {
    static var optionsRequired: Bool {
        #if canImport(UserMessagingPlatform)
        UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
        #else
        false
        #endif
    }
    static var rootViewController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = (scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first)?.rootViewController
        while let p = top?.presentedViewController { top = p }
        return top
    }
    static func presentPrivacyOptions() {
        #if canImport(UserMessagingPlatform)
        guard let root = rootViewController else { return }
        UMPConsentForm.presentPrivacyOptionsForm(from: root) { _ in }
        #endif
    }
}
