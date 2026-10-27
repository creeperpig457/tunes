import SwiftUI

@main
struct TunesApp: App {
    @StateObject private var library = Library()
    @StateObject private var player = Player()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(player)
                .onAppear { library.startWatching() }
                .onChange(of: phase) { p in
                    if p == .active { library.startWatching() } else { library.stopWatching() }
                }
        }
    }
}
