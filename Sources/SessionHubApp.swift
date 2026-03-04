import SwiftUI

@main
struct SessionHubApp: App {
    @State private var store = SessionStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(store: store)
                .onAppear {
                    store.startPolling(interval: 2.0)
                }
        } label: {
            Label("SessionHub", systemImage: "terminal")
        }
        .menuBarExtraStyle(.window)
    }
}
