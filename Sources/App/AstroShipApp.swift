import simd
import SwiftUI

@main
struct AstroShipApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = RemoveAdsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(store)
                .task {
                    AmbientMusic.shared.start()
                    await store.refresh()
                    await AppOpenCoordinator.shared.onColdStart(store: store, model: model)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: AmbientMusic.shared.start()
            case .background: AmbientMusic.shared.pause()
            default: break
            }
        }
    }
}
