import Foundation

struct TLV {
    let tag: Data
    let length: UInt32
    let value: Data

    var tagString: String? {
        String(data: tag, encoding: .ascii)
    }

    var tagCode: UInt32 {
        tag.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
}

func parseTLV(data: Data, offset: Int = 0, end: Int? = nil) -> [TLV] {
    let end = end ?? data.count
    var result: [TLV] = []
    var cursor = offset
    while cursor + 8 <= end {
        let tag = data.subdata(in: cursor..<cursor + 4)
        let length = data.subdata(in: cursor + 4..<cursor + 8).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }
        let valueStart = cursor + 8
        let valueEnd = valueStart + Int(length)
        guard valueEnd <= end else { break }
        result.append(TLV(tag: tag, length: length, value: data.subdata(in: valueStart..<valueEnd)))
        cursor = valueEnd
    }
    return result
}

func readUTF16BE(_ data: Data) -> String {
    var bytes = data
    // Serato sometimes prepends a zero byte for numeric fields stored as strings.
    if bytes.first == 0, bytes.count % 2 == 1 {
        bytes.removeFirst()
    }
    // Pad to even length if needed.
    if bytes.count % 2 == 1 {
        bytes.append(0)
    }
    return String(data: bytes, encoding: .utf16BigEndian)?.replacingOccurrences(of: "\0", with: "") ?? ""
}

struct SeratoTrack: Identifiable, Hashable {
    var id = UUID()
    var filePath: String
    var title: String
    var artist: String?
    var bpm: Double?
    var key: String?
    var length: String?
    /// Streaming tracks (Beatport, Spotify, Tidal, SoundCloud) have no local file
    /// and therefore cannot be dragged onto a deck.
    var streamingSource: String?

    var isStreaming: Bool { streamingSource != nil }

    var displayTitle: String {
        let effectiveTitle = title.isEmpty ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent : title
        if let artist = artist, !artist.isEmpty {
            return "\(artist) - \(effectiveTitle)"
        }
        return effectiveTitle
    }
}

final class SeratoParser {
    let seratoPath: URL

    init(seratoPath: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Music/_Serato_")) {
        self.seratoPath = seratoPath
    }

    var databaseURL: URL {
        seratoPath.appendingPathComponent("database V2")
    }

    var historySessionsURL: URL {
        seratoPath.appendingPathComponent("History/Sessions")
    }

    // MARK: - Database V2

    func parseDatabase() -> [SeratoTrack] {
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let data = try? Data(contentsOf: databaseURL) else {
            return []
        }

        var tracks: [SeratoTrack] = []
        for chunk in parseTLV(data: data) {
            guard chunk.tagString == "otrk" else { continue }
            var track = SeratoTrack(filePath: "", title: "", artist: nil, bpm: nil, key: nil, length: nil)
            for sub in parseTLV(data: chunk.value) {
                guard let tag = sub.tagString else { continue }
                let value = readUTF16BE(sub.value)
                switch tag {
                case "pfil": track.filePath = value
                case "tsng": track.title = value
                case "tart": track.artist = value.isEmpty ? nil : value
                case "tbpm": track.bpm = Double(value)
                case "tkey": track.key = value
                case "tlen": track.length = value
                default: break
                }
            }
            tracks.append(track)
        }
        return tracks
    }

    // MARK: - History Session

    struct HistoryEntry {
        let index: UInt32
        let filePath: String
        let title: String
        let artist: String
        let bpm: Double?
        let startTime: Date?
        let deck: UInt32
        let playTime: Date?
        let played: Bool
    }

    func parseSession(at url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var entries: [HistoryEntry] = []

        for chunk in parseTLV(data: data) {
            guard chunk.tagString == "oent" else { continue }
            var entry: [UInt32: Any] = [:]

            for sub in parseTLV(data: chunk.value) {
                guard sub.tagString == "adat" else { continue }
                for field in parseTLV(data: sub.value) {
                    let code = field.tagCode
                    switch code {
                    case 0x00000001:
                        entry[1] = field.value.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    case 0x00000002:
                        entry[2] = readUTF16BE(field.value)
                    case 0x00000006:
                        entry[6] = readUTF16BE(field.value)
                    case 0x00000007:
                        entry[7] = readUTF16BE(field.value)
                    case 0x0000000f:
                        if field.value.count == 4 {
                            let raw = field.value.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                            entry[0x0f] = Double(raw) / 100.0
                        }
                    case 0x0000001c:
                        if field.value.count == 4 {
                            let raw = field.value.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                            entry[0x1c] = Date(timeIntervalSince1970: TimeInterval(raw))
                        }
                    case 0x0000001f:
                        entry[0x1f] = field.value.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    case 0x0000002d:
                        if field.value.count == 4 {
                            let raw = field.value.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                            entry[0x2d] = Date(timeIntervalSince1970: TimeInterval(raw))
                        }
                    case 0x00000032:
                        entry[0x32] = (field.value.first ?? 0) != 0
                    default:
                        break
                    }
                }
            }

            guard let idx = entry[1] as? UInt32 else { continue }
            entries.append(HistoryEntry(
                index: idx,
                filePath: (entry[2] as? String) ?? "",
                title: (entry[6] as? String) ?? "",
                artist: (entry[7] as? String) ?? "",
                bpm: entry[0x0f] as? Double,
                startTime: entry[0x1c] as? Date,
                deck: (entry[0x1f] as? UInt32) ?? 0,
                playTime: entry[0x2d] as? Date,
                played: (entry[0x32] as? Bool) ?? false
            ))
        }
        return entries.sorted { $0.index < $1.index }
    }

    func latestSessionURL() -> URL? {
        guard FileManager.default.fileExists(atPath: historySessionsURL.path) else { return nil }
        let files = (try? FileManager.default.contentsOfDirectory(at: historySessionsURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension == "session" }
            .max {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return lhs < rhs
            }
    }

    func currentTrack(from entries: [HistoryEntry], database: [SeratoTrack]) -> SeratoTrack? {
        // Prefer the last entry that was actually played.
        let played = entries.filter(\.played)
        let candidate = played.last ?? entries.last
        guard let candidate else { return nil }

        // Try to match by file path first, then by title.
        let path = candidate.filePath
        let title = candidate.title

        if let match = database.first(where: {
            !$0.filePath.isEmpty && (path.hasSuffix($0.filePath) || $0.filePath.hasSuffix(path) || path.contains($0.filePath))
        }) {
            return match
        }
        if !title.isEmpty, let match = database.first(where: { $0.title.contains(title) || title.contains($0.title) }) {
            return match
        }

        // Fall back to the raw history entry as a synthetic track.
        return SeratoTrack(filePath: path, title: title, artist: candidate.artist.isEmpty ? nil : candidate.artist, bpm: candidate.bpm, key: nil, length: nil)
    }
}
