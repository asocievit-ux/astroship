import simd
import SwiftUI

@main
struct AstroShipApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var store = RemoveAdsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(store)
                .task {
                    await store.refresh()
                    await AppOpenCoordinator.shared.onColdStart(store: store, model: model)
                }
        }
    }
}
