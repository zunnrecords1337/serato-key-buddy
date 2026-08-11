import SwiftUI

@main
struct SeratoKeyBuddyApp: App {
    @StateObject private var settings = SettingsStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(settings.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 540)
    }
}
