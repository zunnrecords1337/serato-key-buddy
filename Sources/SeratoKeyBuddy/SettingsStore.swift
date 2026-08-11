import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("theme") var theme: String = "system" {
        didSet { applyTheme() }
    }

    @AppStorage("keyDisplayMode") var keyDisplayMode: String = "camelot" // "camelot" or "normal"

    /// When true, only tracks that exist as local files are suggested. Streaming
    /// entries (Beatport, Spotify, ...) cannot be dragged onto a deck.
    @AppStorage("localFilesOnly") var localFilesOnly: Bool = true

    var colorScheme: ColorScheme? {
        switch theme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    private init() {
        applyTheme()
    }

    private func applyTheme() {
        // Notification can be observed by the App to set preferredColorScheme.
        NotificationCenter.default.post(name: .themeChanged, object: nil)
    }
}

extension Notification.Name {
    static let themeChanged = Notification.Name("themeChanged")
}
