# Serato Key Buddy

A small always-on-top macOS app that shows what Serato DJ Pro is playing right now and suggests harmonically compatible tracks from your own library using the Camelot Wheel.

Built for DJs: no buttons to press mid-set, drag straight onto a deck.

## Features

- **Real-time** — reads Serato's live history, updates every 0.5s. No manual refresh.
- **Per-deck view** — cards for each deck; the app follows whichever deck you just loaded (`Auto`), or stays put if you pick one yourself (`Manual`).
- **Camelot grouping** — suggestions split into `Perfect`, `Relative`, `+1`, `−1` and `Energy Boost (+2)`, each filterable with one click.
- **Drag to deck** — drag any suggestion straight onto a Serato deck.
- **Local files only** — streaming entries (Beatport, Spotify, Tidal) and files missing from disk are hidden by default, because you can't load them onto a deck.
- **Crate-aware** — suggestions can come from your entire library, the crate currently open in Serato, or a specific crate you pick. Switch crates in Serato and the app follows.
- **Always on top** — floating window, visible across all Spaces, draggable by its background.
- **Themes** — System / Dark / Light, and keys shown as Camelot (`8A`) or standard (`Am`).

## Harmonic mixing rules

Camelot notation turns keys into `1A–12A` (minor) and `1B–12B` (major). If you're playing `8A`, the app groups your library into:

| Group | Example | Meaning |
| --- | --- | --- |
| Perfect | `8A` | Same key, safest blend |
| Relative | `8B` | Relative major, mood shift |
| +1 | `9A` | Energy up |
| −1 | `7A` | Deeper / calmer |
| Energy Boost | `10A` | Bigger jump, use deliberately |

The wheel wraps around, so `12A → 1A` are neighbours.

Camelot is a map, not a prison — it tells you where a blend is *likely* to work. Bass, vocals and arrangement still decide. Your ears have the final say.

## Requirements

- macOS 14 or later
- Serato DJ Pro 4.x (reads `~/Library/Application Support/Serato/Library/master.sqlite`, with a fallback to the older `~/Music/_Serato_/database V2`)
- Tracks must be analysed by Serato so they have a key

## Install

Grab `SeratoKeyBuddy.dmg` from [Releases](../../releases), open it and drag the app into `Applications`.

The app is not signed with an Apple Developer certificate, so on first launch macOS will block it. Right-click the app → **Open** → **Open**, or allow it under `System Settings → Privacy & Security`.

## Build from source

```bash
git clone https://github.com/zunnrecords1337/serato-key-buddy.git
cd serato-key-buddy
swift build -c release
swift test
```

To produce a universal (Intel + Apple Silicon) `.app` and `.dmg`:

```bash
./scripts/build-dmg.sh
```

The bundle and disk image are written to `dist/`.

## How it works

Serato DJ Pro has no public API, so the app reads Serato's own SQLite library:

1. The currently playing track per deck comes from `history_entry` — the row with `played = 1` and `end_time = -1` is the one on air.
2. The library comes from `asset`, with full paths rebuilt from `portable_id` plus the location's base path.
3. Keys are normalised from every format Serato writes (`Abm`, `A Minor`, `A m`, `Amin`, `8A`, `8d`, …) into Camelot, then matched against the current key.

## License

MIT
