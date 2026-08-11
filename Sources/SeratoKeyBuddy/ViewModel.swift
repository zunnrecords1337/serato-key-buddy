import Foundation
import SwiftUI
import Combine

struct CompatibleTrack: Identifiable {
    let id = UUID()
    let track: SeratoTrack
    let category: CamelotWheel.Compatibility
    let camelot: CamelotWheel.CamelotKey
}

struct CompatibleSection: Identifiable {
    var id: String { category.rawValue }
    let category: CamelotWheel.Compatibility
    let tracks: [CompatibleTrack]
}

@MainActor
final class SeratoBuddyViewModel: ObservableObject {
    @Published var deckTracks: [Int: SeratoTrack] = [:]
    @Published var selectedDeck: Int = 1
    @Published var activeDeck: Int?
    @Published var autoFollow: Bool = true
    @Published var currentKey: CamelotWheel.CamelotKey?
    @Published var compatibleSections: [CompatibleSection] = []
    @Published var selectedCategory: CamelotWheel.Compatibility?
    @Published var lastUpdated: Date?
    @Published var statusMessage: String = "Waiting for Serato..."

    var filteredSections: [CompatibleSection] {
        guard let selected = selectedCategory else { return compatibleSections }
        return compatibleSections.filter { $0.category == selected }
    }

    private var timer: Timer?
    private let parser = SeratoParser()
    private let sqlite = SeratoSQLite()
    private var library: [SeratoTrack] = []
    private var lastObservedActiveDeck: Int?

    var currentTrack: SeratoTrack? {
        deckTracks[selectedDeck]
    }

    func selectDeck(_ deck: Int) {
        selectedDeck = deck
        lastObservedActiveDeck = deck
        autoFollow = false
        updateCompatibleTracks()
    }

    func startMonitoring() {
        loadLibrary()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if library.isEmpty {
            loadLibrary()
        }

        do {
            let entries = try sqlite.deckTracks()
            var newTracks: [Int: SeratoTrack] = [:]
            for entry in entries {
                newTracks[entry.deck] = entry.track
            }
            deckTracks = newTracks

            // Determine the active/last-active deck for auto-follow and UI indication.
            // Prefer the active deck that started most recently, then the latest played deck.
            let computedActiveDeck: Int?
            if let active = entries.filter({ $0.isActive }).max(by: { $0.startTime < $1.startTime }) {
                computedActiveDeck = active.deck
            } else if let latest = entries.max(by: { $0.startTime < $1.startTime }) {
                computedActiveDeck = latest.deck
            } else {
                computedActiveDeck = newTracks.keys.sorted().first
            }
            self.activeDeck = computedActiveDeck

            if autoFollow, let activeDeck = computedActiveDeck, activeDeck != lastObservedActiveDeck {
                selectedDeck = activeDeck
                lastObservedActiveDeck = activeDeck
            }

            lastUpdated = Date()
            statusMessage = "Live from Serato"
            updateCompatibleTracks()
        } catch {
            statusMessage = "SQLite error: \(error.localizedDescription)"
        }
    }

    private func updateCompatibleTracks() {
        guard let track = currentTrack else {
            compatibleSections = []
            currentKey = nil
            statusMessage = "No track on selected deck."
            return
        }

        currentKey = track.key.flatMap { CamelotWheel.parse($0) }

        guard let key = track.key, let currentCamelot = CamelotWheel.parse(key) else {
            compatibleSections = []
            statusMessage = "Selected track has no key data."
            return
        }

        var all: [CompatibleTrack] = []
        for t in library where t.filePath != track.filePath && t.title != track.title {
            guard let k = t.key, let c = CamelotWheel.parse(k), let category = CamelotWheel.compatibility(current: currentCamelot, candidate: c) else { continue }
            all.append(CompatibleTrack(track: t, category: category, camelot: c))
        }

        all.sort { a, b in
            if a.category.sortRank != b.category.sortRank { return a.category.sortRank > b.category.sortRank }
            if a.camelot.number != b.camelot.number { return a.camelot.number < b.camelot.number }
            return a.track.title.localizedStandardCompare(b.track.title) == .orderedAscending
        }

        let grouped = Dictionary(grouping: all) { $0.category }
            .map { CompatibleSection(category: $0.key, tracks: $0.value) }
            .sorted { $0.category.sortRank > $1.category.sortRank }

        compatibleSections = grouped
        statusMessage = "Deck \(selectedDeck): \(track.displayTitle)"
    }

    /// Reload the library, e.g. after the "local files only" setting changed.
    func reloadLibrary() {
        library = []
        loadLibrary()
        updateCompatibleTracks()
    }

    private func loadLibrary() {
        let localOnly = SettingsStore.shared.localFilesOnly
        do {
            library = try sqlite.readLibrary(localFilesOnly: localOnly)
            statusMessage = "Loaded \(library.count) tracks from SQLite"
        } catch {
            library = parser.parseDatabase()
            statusMessage = "Falling back to database V2 (\(library.count) tracks)"
        }
    }
}
