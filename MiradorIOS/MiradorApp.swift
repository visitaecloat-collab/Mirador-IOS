import SwiftUI

@main
struct MiradorApp: App {
    @StateObject private var appState = MiradorAppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    Task {
                        await appState.handleDeepLink(url)
                    }
                }
                .task {
                    await appState.bootstrap()
                }
        }
    }
}
