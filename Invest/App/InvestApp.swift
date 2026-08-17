import SwiftUI

@main
struct InvestApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState.settings)
                .environment(appState.portfolio)
                .environment(appState.watchlist)
                .environment(appState.chat)
                .environment(appState.agent)
        }
    }
}
