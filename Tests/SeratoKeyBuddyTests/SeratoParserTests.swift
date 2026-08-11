import Foundation
import Testing
@testable import SeratoKeyBuddy

/// These tests read the local Serato library, so they are skipped on machines
/// that do not have Serato DJ installed (e.g. CI).
@Test
func testParseDatabase() async throws {
    let parser = SeratoParser()
    let tracks = parser.parseDatabase()
    try #require(!tracks.isEmpty, "No Serato database V2 found, skipping")
    if let first = tracks.first {
        #expect(!first.title.isEmpty)
    }
}

@Test
func testLatestSession() async throws {
    let parser = SeratoParser()
    let url = try #require(parser.latestSessionURL(), "No Serato history session found, skipping")
    let entries = parser.parseSession(at: url)
    #expect(!entries.isEmpty)
}

@Test
func testCamelotParsing() {
    #expect(CamelotWheel.parse("Bm")?.description == "10A")
    #expect(CamelotWheel.parse("Fm")?.description == "4A")
    #expect(CamelotWheel.parse("8d")?.description == "8B")
    #expect(CamelotWheel.parse("1m")?.description == "1A")
    #expect(CamelotWheel.parse("C Major")?.description == "8B")
    #expect(CamelotWheel.parse("A Minor")?.description == "8A")
    #expect(CamelotWheel.parse("A m")?.description == "8A")
    #expect(CamelotWheel.parse("Amin")?.description == "8A")
    #expect(CamelotWheel.parse("A# Major")?.description == "5B")
    #expect(CamelotWheel.parse("C# Major")?.description == "3B")
    #expect(CamelotWheel.parse("Ab Major")?.description == "7B")
    #expect(CamelotWheel.parse("Db Minor")?.description == "12A")
}

@Test
func testStreamingSourceDetection() {
    #expect(SeratoSQLite.streamingSource(from: "streaming://beatport/28778223") == "beatport")
    #expect(SeratoSQLite.streamingSource(from: "streaming://spotify/7l6cafHnlKFvLszG2CN8mq") == "spotify")
    #expect(SeratoSQLite.streamingSource(from: "Users/zunn/Music/track.mp3") == nil)
    #expect(SeratoSQLite.streamingSource(from: "/Users/zunn/Desktop/track.mp3") == nil)
}

@Test
func testLibraryContainsOnlyExistingLocalFiles() throws {
    let sqlite = SeratoSQLite()
    try #require(sqlite.isAvailable, "No Serato 4 SQLite library found, skipping")
    let tracks = try sqlite.readLibrary(localFilesOnly: true)
    #expect(!tracks.isEmpty)
    for track in tracks {
        #expect(!track.isStreaming)
        #expect(FileManager.default.fileExists(atPath: track.filePath))
    }
}

@Test
func testCamelotCompatibility() {
    let key8A = CamelotWheel.CamelotKey(number: 8, mode: .A)
    #expect(CamelotWheel.compatibility(current: key8A, candidate: key8A) == .perfect)
    #expect(CamelotWheel.compatibility(current: key8A, candidate: CamelotWheel.CamelotKey(number: 9, mode: .A)) == .plus1)
    #expect(CamelotWheel.compatibility(current: key8A, candidate: CamelotWheel.CamelotKey(number: 7, mode: .A)) == .minus1)
    #expect(CamelotWheel.compatibility(current: key8A, candidate: CamelotWheel.CamelotKey(number: 8, mode: .B)) == .relative)
    #expect(CamelotWheel.compatibility(current: key8A, candidate: CamelotWheel.CamelotKey(number: 10, mode: .A)) == .energyBoost)
    #expect(CamelotWheel.compatibility(current: key8A, candidate: CamelotWheel.CamelotKey(number: 1, mode: .A)) == nil)
}
