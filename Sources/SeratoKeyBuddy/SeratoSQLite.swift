import Foundation
import SQLite3

enum SeratoSQLiteError: Error {
    case openFailed(String)
    case queryFailed(String)
}

final class SeratoSQLite {
    let path: URL

    init(path: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Serato/Library/master.sqlite")) {
        self.path = path
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: path.path)
    }

    private func withConnection<T>(_ action: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path.path, &db, flags, nil) == SQLITE_OK, let connection = db else {
            let msg = String(cString: sqlite3_errmsg(db) ?? ("Cannot open database" as NSString).utf8String!)
            sqlite3_close(db)
            throw SeratoSQLiteError.openFailed(msg)
        }
        defer { sqlite3_close(connection) }
        return try action(connection)
    }

    /// Read all tracks from the asset table with resolved full file paths.
    /// - Parameter localFilesOnly: when true, streaming entries (Beatport, Spotify,
    ///   Tidal, SoundCloud) and files that no longer exist on disk are excluded,
    ///   since they cannot be loaded onto a deck.
    func readLibrary(localFilesOnly: Bool = true) throws -> [SeratoTrack] {
        let basePaths = try resolveBasePaths()
        let query = """
            SELECT portable_id, file_name, artist, name, bpm, key, length_ms, location_id
            FROM asset
            WHERE is_missing = 0
        """
        return try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }

            let fileManager = FileManager.default
            var tracks: [SeratoTrack] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let portableId = string(statement, index: 0)
                let fileName = string(statement, index: 1)
                let artist = string(statement, index: 2)
                let name = string(statement, index: 3)
                let bpm = double(statement, index: 4)
                let key = string(statement, index: 5)
                let lengthMs = int(statement, index: 6)
                let locationId = int(statement, index: 7)
                let length = lengthMs > 0 ? formattedLength(ms: lengthMs) : nil

                let rawId = portableId ?? fileName ?? ""
                let streamingSource = Self.streamingSource(from: rawId)

                if localFilesOnly && streamingSource != nil { continue }

                let fullPath = resolveFullPath(portableId: rawId, locationId: locationId, basePaths: basePaths)

                // Serato keeps stale rows for deleted files, so verify on disk.
                if localFilesOnly, streamingSource == nil, !fileManager.fileExists(atPath: fullPath) { continue }

                tracks.append(SeratoTrack(
                    filePath: fullPath,
                    title: name ?? fileName ?? "",
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    length: length,
                    streamingSource: streamingSource
                ))
            }
            return tracks
        }
    }

    /// Extract the streaming service from a portable id such as
    /// `streaming://beatport/28778223`. Returns nil for local files.
    static func streamingSource(from portableId: String) -> String? {
        guard portableId.hasPrefix("streaming://") else { return nil }
        let rest = portableId.dropFirst("streaming://".count)
        let source = rest.prefix { $0 != "/" }
        return source.isEmpty ? "streaming" : String(source)
    }

    private func resolveBasePaths() throws -> [Int: String] {
        let query = """
            SELECT c.location_id, c.database_uri
            FROM connection c
        """
        return try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }

            var paths: [Int: String] = [:]
            while sqlite3_step(statement) == SQLITE_ROW {
                let locationId = int(statement, index: 0)
                let databaseUri = string(statement, index: 1) ?? ""
                paths[locationId] = basePath(from: databaseUri)
            }
            return paths
        }
    }

    private func basePath(from databaseUri: String) -> String {
        if databaseUri.hasSuffix("/root.sqlite") || databaseUri.hasSuffix("/beatport.sqlite") {
            return "/"
        }
        if let regex = try? NSRegularExpression(pattern: "^(.+)/_Serato_/Library/location\\.sqlite$"),
           let match = regex.firstMatch(in: databaseUri, range: NSRange(location: 0, length: databaseUri.utf16.count)) {
            let range = match.range(at: 1)
            if let swiftRange = Range(range, in: databaseUri) {
                return String(databaseUri[swiftRange]) + "/"
            }
        }
        return "/"
    }

    private func resolveFullPath(portableId: String, locationId: Int, basePaths: [Int: String]) -> String {
        let base = basePaths[locationId] ?? "/"
        if portableId.hasPrefix("/") {
            return portableId
        }
        return base + portableId
    }

    struct DeckEntry {
        let deck: Int
        let track: SeratoTrack
        let startTime: Int
        let isActive: Bool
    }

    /// Fetch the currently loaded tracks for each deck in the latest session.
    /// Returns a map of deck number (1-4) to the most recent track on that deck,
    /// along with the start time and whether it is still playing.
    func deckTracks() throws -> [DeckEntry] {
        let basePaths = try resolveBasePaths()
        let query = """
            SELECT he.name, he.artist, he.bpm, he.key, he.file_name, he.portable_id, he.location_id, he.deck,
                   he.start_time, (he.end_time = -1) AS is_active
            FROM history_entry he
            WHERE he.session_id = (
                SELECT id FROM history_session ORDER BY start_time DESC LIMIT 1
            )
            AND he.played = 1
            ORDER BY he.deck, he.start_time DESC
        """
        return try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }

            var seenDecks = Set<Int>()
            var entries: [DeckEntry] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let name = string(statement, index: 0)
                let artist = string(statement, index: 1)
                let bpm = double(statement, index: 2)
                let key = string(statement, index: 3)
                let fileName = string(statement, index: 4)
                let portableId = string(statement, index: 5)
                let locationId = int(statement, index: 6)
                let deck = int(statement, index: 7)
                let startTime = int(statement, index: 8)
                let isActive = int(statement, index: 9) != 0

                let rawId = portableId ?? fileName ?? ""
                let fullPath = resolveFullPath(portableId: rawId, locationId: locationId, basePaths: basePaths)
                let track = SeratoTrack(
                    filePath: fullPath,
                    title: name ?? fileName ?? "",
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    length: nil,
                    streamingSource: Self.streamingSource(from: rawId)
                )

                // Keep only the most recent entry per deck.
                if seenDecks.insert(deck).inserted {
                    entries.append(DeckEntry(deck: deck, track: track, startTime: startTime, isActive: isActive))
                }
            }
            return entries
        }
    }

    private func string(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    private func double(_ statement: OpaquePointer?, index: Int32) -> Double? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func int(_ statement: OpaquePointer?, index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    // MARK: - Crates

    struct Crate: Identifiable, Hashable {
        let id: Int          // container.id
        let name: String
        let trackCount: Int
    }

    /// List all crates (top-level containers of type 1) with their track counts.
    func allCrates() throws -> [Crate] {
        let query = """
            SELECT c.id, c.name, COUNT(ca.id) AS track_count
            FROM container c
            LEFT JOIN location_container lc ON lc.container_id = c.id
            LEFT JOIN container_asset ca ON ca.location_container_id = lc.id
            WHERE c.type = 1 AND c.parent_id IS NULL
            GROUP BY c.id
            ORDER BY c.name COLLATE NOCASE
        """
        return try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }

            var crates: [Crate] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = int(statement, index: 0)
                let name = string(statement, index: 1) ?? "Unknown"
                let count = int(statement, index: 2)
                crates.append(Crate(id: id, name: name, trackCount: count))
            }
            return crates
        }
    }

    /// Best-effort detection of the crate currently displayed in Serato's library pane.
    /// Serato keeps crate view slots in `assetlist_context` (source_type = 5); the one
    /// whose backing `anonymous_table_*` has rows is the active crate.
    func currentCrate() throws -> Crate? {
        // Find active crate view slots.
        let contextQuery = """
            SELECT id, source_table FROM assetlist_context
            WHERE source_type = 5 AND is_active = 1
        """
        let contexts: [(id: Int, table: String)] = try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, contextQuery, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }
            var result: [(Int, String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = int(statement, index: 0)
                let table = string(statement, index: 1) ?? ""
                result.append((id, table))
            }
            return result
        }

        // Check each anonymous table for data; the first non-empty one is the current crate.
        for (_, table) in contexts {
            let count = try scalarQuery("SELECT COUNT(*) FROM \(table)")
            if count > 0 {
                // Resolve the crate name from the container_asset → location_container → container chain.
                let nameQuery = """
                    SELECT c.id, c.name, COUNT(*) AS cnt
                    FROM \(table) t
                    JOIN container_asset ca ON t.container_asset_id = ca.id
                    JOIN location_container lc ON ca.location_container_id = lc.id
                    JOIN container c ON lc.container_id = c.id
                    GROUP BY c.id
                    ORDER BY cnt DESC
                    LIMIT 1
                """
                return try withConnection { db in
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, nameQuery, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                        return nil
                    }
                    defer { sqlite3_finalize(statement) }
                    if sqlite3_step(statement) == SQLITE_ROW {
                        let id = int(statement, index: 0)
                        let name = string(statement, index: 1) ?? "Unknown"
                        let count = int(statement, index: 2)
                        return Crate(id: id, name: name, trackCount: count)
                    }
                    return nil
                }
            }
        }
        return nil
    }

    /// Read all tracks belonging to a specific crate (by container id).
    func readCrate(containerId: Int, localFilesOnly: Bool = true) throws -> [SeratoTrack] {
        let basePaths = try resolveBasePaths()
        let query = """
            SELECT a.portable_id, a.file_name, a.artist, a.name, a.bpm, a.key, a.length_ms, a.location_id
            FROM asset a
            JOIN container_asset ca ON ca.asset_id = a.id
            JOIN location_container lc ON ca.location_container_id = lc.id
            WHERE lc.container_id = ? AND a.is_missing = 0
            ORDER BY ca.list_order
        """
        return try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(containerId))

            let fileManager = FileManager.default
            var tracks: [SeratoTrack] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let portableId = string(statement, index: 0)
                let fileName = string(statement, index: 1)
                let artist = string(statement, index: 2)
                let name = string(statement, index: 3)
                let bpm = double(statement, index: 4)
                let key = string(statement, index: 5)
                let lengthMs = int(statement, index: 6)
                let locationId = int(statement, index: 7)
                let length = lengthMs > 0 ? formattedLength(ms: lengthMs) : nil

                let rawId = portableId ?? fileName ?? ""
                let streamingSource = Self.streamingSource(from: rawId)
                if localFilesOnly && streamingSource != nil { continue }

                let fullPath = resolveFullPath(portableId: rawId, locationId: locationId, basePaths: basePaths)
                if localFilesOnly, streamingSource == nil, !fileManager.fileExists(atPath: fullPath) { continue }

                tracks.append(SeratoTrack(
                    filePath: fullPath,
                    title: name ?? fileName ?? "",
                    artist: artist,
                    bpm: bpm,
                    key: key,
                    length: length,
                    streamingSource: streamingSource
                ))
            }
            return tracks
        }
    }

    private func scalarQuery(_ sql: String) throws -> Int {
        try withConnection { db in
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let statement = stmt else {
                throw SeratoSQLiteError.queryFailed(String(cString: sqlite3_errmsg(db) ?? ("Prepare failed" as NSString).utf8String!))
            }
            defer { sqlite3_finalize(statement) }
            if sqlite3_step(statement) == SQLITE_ROW {
                return Int(sqlite3_column_int64(statement, 0))
            }
            return 0
        }
    }

    private func formattedLength(ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
