import simd
import SwiftUI
import UIKit

@main
struct AstroShipApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = RemoveAdsStore.shared
    @StateObject private var sleepTimer = SleepTimer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(store)
                .environmentObject(sleepTimer)
                .task {
                    sleepTimer.onSleep = { [weak m = model] in m?.setRendering(false) }
                    sleepTimer.onWake = { [weak m = model] in m?.setRendering(true) }
                    UIApplication.shared.isIdleTimerDisabled = true   // a viewing app: no auto-lock while open
                    AmbientMusic.shared.start()
                    await store.refresh()
                    await AppOpenCoordinator.shared.onColdStart(store: store, model: model)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                sleepTimer.checkExpired()
                if !sleepTimer.asleep { UIApplication.shared.isIdleTimerDisabled = true }
                AmbientMusic.shared.start()
            case .background:
                AmbientMusic.shared.pause()
                UIApplication.shared.isIdleTimerDisabled = false
            default: break
            }
        }
    }
}
