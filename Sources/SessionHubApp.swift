import SwiftUI

@main
struct SessionHubApp: App {
    @State private var store = SessionStore()

    init() {
        // Start polling immediately at launch (connects via WebSocket, no TCC needed)
        _store = State(initialValue: {
            let s = SessionStore()
            s.startPolling(interval: 3.0)
            return s
        }())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            Label("SessionHub", systemImage: "terminal")
        }
        .menuBarExtraStyle(.window)
    }
}
