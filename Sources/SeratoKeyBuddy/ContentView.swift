import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = SeratoBuddyViewModel()
    @StateObject private var settings = SettingsStore.shared
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            deckSelector
            Divider()
            compatibleList
        }
        .padding()
        .frame(minWidth: 320, minHeight: 420)
        .onAppear {
            viewModel.startMonitoring()
            makeWindowFloating()
        }
        .onDisappear { viewModel.stopMonitoring() }
        .onChange(of: settings.localFilesOnly) { _, _ in
            viewModel.reloadLibrary()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .frame(minWidth: 280, minHeight: 180)
        }
    }

    private func makeWindowFloating() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Serato Key Buddy")
                    .font(.headline)
                if let active = viewModel.activeDeck {
                    Text("Serato active: Deck \(active)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: { viewModel.autoFollow.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.autoFollow ? "link.circle.fill" : "link.circle")
                    Text(viewModel.autoFollow ? "Auto" : "Manual")
                        .font(.caption)
                }
                .foregroundStyle(viewModel.autoFollow ? .green : .secondary)
            }
            .buttonStyle(.borderless)
            .help(viewModel.autoFollow ? "Auto-follow Serato deck (on)" : "Auto-follow Serato deck (off)")
            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
        }
    }

    private var deckSelector: some View {
        let decks = viewModel.deckTracks.keys.sorted()
        return HStack(spacing: 8) {
            ForEach(decks, id: \.self) { deck in
                DeckButton(
                    deck: deck,
                    track: viewModel.deckTracks[deck],
                    isSelected: viewModel.selectedDeck == deck,
                    isActive: viewModel.activeDeck == deck,
                    displayMode: settings.keyDisplayMode
                ) {
                    viewModel.selectDeck(deck)
                }
            }
            if decks.isEmpty {
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }

    private var compatibleList: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Compatible tracks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let track = viewModel.deckTracks[viewModel.selectedDeck] {
                    Text("Deck \(viewModel.selectedDeck): \(track.displayTitle)")
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            categoryFilter

            ScrollViewReader { proxy in
                List {
                    EmptyView().id("compatible-list-top")
                    ForEach(viewModel.filteredSections) { section in
                        Section {
                            ForEach(section.tracks) { item in
                                CompatibleTrackRow(
                                    item: item,
                                    displayMode: settings.keyDisplayMode
                                )
                            }
                        } header: {
                            HStack {
                                Text(section.category.description)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.plain)
                .onChange(of: viewModel.selectedDeck) { _, _ in
                    withAnimation {
                        proxy.scrollTo("compatible-list-top", anchor: .top)
                    }
                }
                .onChange(of: viewModel.selectedCategory) { _, _ in
                    withAnimation {
                        proxy.scrollTo("compatible-list-top", anchor: .top)
                    }
                }
            }
        }
    }

    private var categoryFilter: some View {
        HStack(spacing: 4) {
            ForEach(CamelotWheel.Compatibility.allCases, id: \.rawValue) { category in
                let selected = viewModel.selectedCategory == category
                Button(action: {
                    if viewModel.selectedCategory == category {
                        viewModel.selectedCategory = nil
                    } else {
                        viewModel.selectedCategory = category
                    }
                }) {
                    Text(category.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(selected ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CompatibleTrackRow: View {
    let item: CompatibleTrack
    let displayMode: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.track.displayTitle)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let bpm = item.track.bpm {
                        Text(String(format: "%.2f BPM", bpm))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let source = item.track.streamingSource {
                        Label(source.capitalized, systemImage: "cloud")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Text(item.camelot.description)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                KeyBadge(
                    label: displayMode == "normal" ? (item.track.key ?? item.camelot.description) : item.camelot.description,
                    color: CamelotWheel.color(for: item.camelot)
                )
            }
        }
        .opacity(item.track.isStreaming ? 0.55 : 1)
        .onDrag {
            // Streaming tracks have no local file, so there is nothing to drag.
            guard !item.track.isStreaming else { return NSItemProvider() }
            let fileURL = URL(fileURLWithPath: item.track.filePath)
            let provider = NSItemProvider(contentsOf: fileURL)
                ?? NSItemProvider(item: fileURL as NSSecureCoding, typeIdentifier: "public.file-url")
            provider.suggestedName = item.track.displayTitle
            return provider
        }
    }
}

struct DeckButton: View {
    let deck: Int
    let track: SeratoTrack?
    let isSelected: Bool
    let isActive: Bool
    let displayMode: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Deck \(deck)")
                        .font(.caption)
                    if isActive {
                        Spacer()
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                }
                .foregroundStyle(isSelected ? .white : .primary)
                if let track = track {
                    Text(track.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundStyle(isSelected ? .white : .primary)
                    HStack(spacing: 6) {
                        if let camelot = track.key.flatMap({ CamelotWheel.parse($0) }) {
                            if displayMode == "normal", let key = track.key {
                                Text(key)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                            }
                            Text(camelot.description)
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : CamelotWheel.color(for: camelot))
                        } else if let key = track.key {
                            Text(key)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        }
                        Spacer()
                    }
                } else {
                    Text("Empty")
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct KeyBadge: View {
    let label: String
    var color: Color = .blue

    var body: some View {
        Text(label)
            .font(.system(.body, design: .rounded, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SettingsView: View {
    @StateObject private var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.title3.weight(.bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Theme")
                    .font(.subheadline.weight(.semibold))
                Picker("Theme", selection: $settings.theme) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Key display")
                    .font(.subheadline.weight(.semibold))
                Picker("Key display", selection: $settings.keyDisplayMode) {
                    Text("Camelot").tag("camelot")
                    Text("Normal").tag("normal")
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Only local files", isOn: $settings.localFilesOnly)
                Text("Hides streaming tracks (Beatport, Spotify) and files missing from disk — they can't be dragged to a deck.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 280, minHeight: 160)
    }
}
