import simd
import SwiftUI
import UIKit

@main
struct AstroShipApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = RemoveAdsStore.shared
    @StateObject private var sleepTimer = SleepTimer.shared
    @StateObject private var lang = AppLanguage.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(store)
                .environmentObject(sleepTimer)
                .appLanguage(lang)
                .task {
                    sleepTimer.onSleep = { [weak m = model] in
                        m?.endTour(restoreControls: false)   // keep the screen clean while it dims
                        m?.setRendering(false)
                    }
                    sleepTimer.onWake = { [weak m = model] in m?.setRendering(true) }
                    UIApplication.shared.isIdleTimerDisabled = true   // a viewing app: no auto-lock while open
                    AmbientMusic.shared.start()
                    await store.refresh()
                    await AppOpenCoordinator.shared.onColdStart(store: store, model: model)
                }
        }
        #if os(visionOS)
        .defaultSize(width: 1280, height: 820)
        #endif
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
        #if os(visionOS)
        ImmersiveSpace(id: "orrery") {
            SolarImmersiveView()
                .environmentObject(model)
                .onDisappear { model.immersiveOpen = false }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
        #endif
    }
}
